// 临时性能探针（非产品代码，定位「安卓端键盘弹出动画掉帧」用，用完即删）。
//
// 目的：在真机 profile 模式下拿到**逐帧** FrameTiming，把键盘弹出/收起动画期间
// 的应用侧开销（UI 线程 build+layout+paint / 栅格线程）量出来，并对比三种变体，
// 判断瓶颈到底在应用侧还是平台/合成侧：
//   A_glass     = 真实登录页（CyrenePage largeTitle + 玻璃顶栏 + 捕获层 + 光斑）
//   B_smallbar  = 仅把顶栏换成静态小标题栏（无玻璃、无 MiuixLayerBackdropCapture）
//   C_noaurora  = 同 A 但去掉 CyreneAuroraBackdrop
//
// 用法：flutter run --profile -t lib/perf/kb_perf_main.dart -d <device>
// 全自动：脚本按变体循环——切换 → 静置 → 聚焦输入框（唤起键盘）→ 收起，重复 3 轮。
// 输出：logcat tag=flutter，所有行以 KBPERF 开头。

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../application/auth/account_session_controller.dart';
import '../domain/auth/auth_repository.dart';
import '../domain/auth/auth_session_store.dart';
import '../domain/models/user.dart';
import '../features/settings/login_page.dart';
import '../presentation/cyrene/cyrene_aurora_backdrop.dart';
import '../presentation/cyrene/cyrene_page.dart';
import '../presentation/cyrene/cyrene_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 玻璃 shader 必须先就绪：否则玻璃会静默降级成「模糊+混色」，测出来的
  // 代价与真机实际不符。
  await MiuixGlassRendering.load();
  KbProbe.instance.start();
  runApp(const KbPerfApp());
}

/// 逐帧采集器：按「键盘是否弹出」分桶，另对每次 inset 变化后的 600ms 内的帧
/// 单独打点（那正是键盘动画逐帧推进的时间窗）。
class KbProbe {
  KbProbe._();
  static final KbProbe instance = KbProbe._();

  final Stopwatch _clock = Stopwatch()..start();
  final List<ui.FrameTiming> _window = <ui.FrameTiming>[];
  Timer? _ticker;
  bool started = false;

  String variant = '-';
  double inset = 0;
  double sizeH = 0;
  late final double refreshRate = WidgetsBinding
      .instance
      .platformDispatcher
      .views
      .first
      .display
      .refreshRate;
  int _lastInsetChangeMs = -1 << 20;
  int _insetChanges = 0;
  int _windowAnimFrames = 0;
  int _lastFrameWallUs = -1;
  double _windowMaxGapMs = 0;

  void start() {
    if (started) return;
    started = true;
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _report());
    _log('start refresh=${refreshRate.toStringAsFixed(1)}Hz');
  }

  void stop() {
    _ticker?.cancel();
    _report();
    _log('DONE');
  }

  void setVariant(String value) {
    _report();
    variant = value;
    _insetChanges = 0;
    _windowAnimFrames = 0;
    _windowMaxGapMs = 0;
    _log('VARIANT $value');
  }

  void noteInsets(double bottom, double height) {
    sizeH = height;
    if (bottom == inset) return;
    inset = bottom;
    _lastInsetChangeMs = _clock.elapsedMilliseconds;
    _insetChanges++;
  }

  void _onTimings(List<ui.FrameTiming> timings) {
    for (final t in timings) {
      _window.add(t);
      // 帧间隔用墙上时间算：间隔明显大于刷新周期即丢帧（键盘动画期间最关心）。
      final wallUs = _clock.elapsedMicroseconds;
      if (_lastFrameWallUs >= 0) {
        final gap = (wallUs - _lastFrameWallUs) / 1000.0;
        if (gap < 500 && gap > _windowMaxGapMs) _windowMaxGapMs = gap;
      }
      _lastFrameWallUs = wallUs;
      // 键盘动画窗口内逐帧打点。
      if (_clock.elapsedMilliseconds - _lastInsetChangeMs < 600) {
        _windowAnimFrames++;
        _log(
          'IME_FRAME inset=${inset.toStringAsFixed(0)} size=${sizeH.toStringAsFixed(0)} '
          'ui=${_ms(t.buildDuration)} raster=${_ms(t.rasterDuration)} '
          'span=${_ms(t.totalSpan)} vsyncOver=${_ms(t.vsyncOverhead)}',
        );
      }
    }
    if (_window.length > 600) {
      _window.removeRange(0, _window.length - 600);
    }
  }

  void _report() {
    if (_window.isEmpty) return;
    var uiSum = 0.0, uiMax = 0.0, rSum = 0.0, rMax = 0.0;
    var over = 0;
    final budget = 1000 / refreshRate;
    for (final t in _window) {
      final ui = t.buildDuration.inMicroseconds / 1000.0;
      final r = t.rasterDuration.inMicroseconds / 1000.0;
      uiSum += ui;
      rSum += r;
      if (ui > uiMax) uiMax = ui;
      if (r > rMax) rMax = r;
      if (ui > budget || r > budget) over++;
    }
    final n = _window.length;
    _log(
      'WINDOW variant=$variant phase=${inset > 0 ? 'ime' : 'idle'} '
      'frames=$n ui_avg=${_ms2(uiSum / n)} ui_max=${_ms2(uiMax)} '
      'raster_avg=${_ms2(rSum / n)} raster_max=${_ms2(rMax)} '
      'over=${(100 * over / n).toStringAsFixed(0)}% maxgap=${_ms2(_windowMaxGapMs)} '
      'inset=${inset.toStringAsFixed(0)} size=${sizeH.toStringAsFixed(0)} '
      'animFrames=$_windowAnimFrames insetChanges=$_insetChanges',
    );
    _window.clear();
    _insetChanges = 0;
    _windowAnimFrames = 0;
    _windowMaxGapMs = 0;
  }
}

String _ms(Duration d) => (d.inMicroseconds / 1000).toStringAsFixed(1);
String _ms2(double ms) => ms.toStringAsFixed(1);

void _log(String message) => debugPrint('KBPERF $message');

class KbPerfApp extends StatefulWidget {
  const KbPerfApp({super.key});

  @override
  State<KbPerfApp> createState() => _KbPerfAppState();
}

class _KbPerfAppState extends State<KbPerfApp> {
  static const _variants = ['A_glass', 'B_smallbar', 'C_noaurora'];

  final _variant = ValueNotifier<String>(_variants.first);
  final _account = AccountSessionController(
    const _NoopAuthRepository(),
    _MemoryAuthStore(),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_runScript());
  }

  @override
  void dispose() {
    _account.dispose();
    _variant.dispose();
    super.dispose();
  }

  Future<void> _runScript() async {
    for (var round = 0; round < 3; round++) {
      final order = round.isEven
          ? _variants
          : _variants.reversed.toList();
      for (final v in order) {
        _variant.value = v;
        KbProbe.instance.setVariant(v);
        await Future<void>.delayed(const Duration(milliseconds: 2500));
        _focusFirstEditable();
        await Future<void>.delayed(const Duration(milliseconds: 2500));
        FocusManager.instance.primaryFocus?.unfocus();
        await Future<void>.delayed(const Duration(milliseconds: 2500));
      }
    }
    KbProbe.instance.stop();
  }

  /// 聚焦页面里第一个输入框（等价用户点一下输入框唤起键盘）。
  void _focusFirstEditable() {
    FocusNode? target;
    void visit(Element element) {
      if (target != null) return;
      final widget = element.widget;
      if (widget is EditableText && widget.focusNode.canRequestFocus) {
        target = widget.focusNode;
        return;
      }
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    target?.requestFocus();
  }

  Widget _buildVariant(String variant) {
    final glass = variant != 'B_smallbar';
    final aurora = variant != 'C_noaurora';
    return CyrenePage(
      key: ValueKey('page-$variant'),
      title: '登录',
      largeTitle: glass,
      topBarTintAlpha: 0,
      bodyBuilder: (context, topPadding) => Stack(
        children: [
          if (aurora) const Positioned.fill(child: CyreneAuroraBackdrop()),
          Positioned.fill(
            child: LoginView(
              key: ValueKey('login-$variant'),
              account: _account,
              padding: EdgeInsets.fromLTRB(20, topPadding.top + 32, 20, 32),
            ),
          ),
          const Positioned(left: 0, bottom: 0, child: _InsetProbe()),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MiuixThemeController(
    colorSchemeMode: MiuixColorSchemeMode.light,
    textStyles: CyreneMiuixTheme.textStyles(),
    child: Builder(
      builder: (context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: CyreneMiuixTheme.material(MiuixTheme.of(context)),
        initialRoute: '/login',
        onGenerateRoute: (settings) => CupertinoPageRoute<void>(
          settings: settings,
          builder: (_) => settings.name == '/login'
              ? ValueListenableBuilder<String>(
                  valueListenable: _variant,
                  builder: (context, variant, _) => _buildVariant(variant),
                )
              : const SizedBox.shrink(),
        ),
      ),
    ),
  );
}

/// 零尺寸探针：把当前 viewInsets/size 报给 [KbProbe]。
///
/// 刻意放在叶子节点：只让这一小块随 viewInsets 重建，与真实登录页里
/// 「只有 LoginView 依赖 viewInsets」的代价结构一致。
class _InsetProbe extends StatelessWidget {
  const _InsetProbe();

  @override
  Widget build(BuildContext context) {
    KbProbe.instance.noteInsets(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.sizeOf(context).height,
    );
    return const SizedBox.shrink();
  }
}

class _NoopAuthRepository implements AuthRepository {
  const _NoopAuthRepository();

  @override
  Future<AuthResponse> login(String account, String password) async =>
      const AuthResponse(success: false, message: '探针不登录');

  @override
  Future<bool> validateToken(String token) async => false;

  @override
  Future<AuthResponse> register(
    String email,
    String username,
    String password,
    String code, {
    String? inviteCode,
  }) async => const AuthResponse(success: false);

  @override
  Future<AuthResponse> sendRegisterCode(String email, String username) async =>
      const AuthResponse(success: false);

  @override
  Future<({bool success, bool enabled})> checkRegistrationStatus() async =>
      (success: true, enabled: true);
}

class _MemoryAuthStore implements AuthSessionStore {
  AuthSession? _session;

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> write(AuthSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}
