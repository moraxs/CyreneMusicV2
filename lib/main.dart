import 'dart:io' show Platform;

import 'package:fluent_ui/fluent_ui.dart' show FluentLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'app/app_dependencies.dart';
import 'app/app_version.dart';
import 'app/debug_probe.dart';
import 'app/desktop/desktop_fluent_theme.dart';
import 'app/music_app_shell.dart';
import 'application/playback/playback_history_recorder.dart';
import 'application/stores/appearance_settings_store.dart';
import 'application/stores/fullscreen_settings_store.dart';
import 'features/player/mobile/compat/lyric_font_service.dart';
import 'features/player/mobile/compat/lyric_style_service.dart';
import 'features/player/mobile/compat/player_background_service.dart';
import 'infrastructure/core/url_service.dart';
import 'infrastructure/media_notification/media_notification_service.dart';
import 'infrastructure/services/developer_mode_service.dart';
import 'infrastructure/services/listening_card_sync.dart';
import 'infrastructure/services/update_service.dart';
import 'presentation/cyrene/cyrene_theme.dart';
import 'presentation/cyrene/cyrene_toast.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 捕获全应用 debugPrint 到开发者日志缓冲（开发者选项 → 运行日志）。
  final defaultDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) DeveloperModeService.instance.addLog(message);
    defaultDebugPrint(message, wrapWidth: wrapWidth);
  };
  // media_kit 必须在使用前初始化（会加载 libmpv 原生库）。
  installProbe();
  MediaKit.ensureInitialized();
  // 桌面端融合标题栏：隐藏 Win32 原生标题栏，改由 fluent TitleBar 绘制
  // （见 app/desktop/desktop_title_bar.dart）。必须在首帧前完成，否则会先
  // 闪一下原生标题栏。移动端不触碰（插件在 Android/iOS 上无对应实现）。
  await _initDesktopWindow();
  await Future.wait([
    if (!probeNoGlass) LiquidGlassWidgets.initialize(),
    UrlService.instance.init(),
    FullscreenSettingsStore.instance.init(),
    // 外观偏好（明暗模式 / 主题色）须在首帧前就绪，避免主题闪变。
    AppearanceSettingsStore.instance.init(),
    // 开发者模式状态（决定设置页「开发者选项」入口与性能叠加层）。
    DeveloperModeService.instance.ensureLoaded(),
    // 移植版播放器（原版全屏播放器）的样式/背景/字体偏好，与原版 main 一致。
    LyricStyleService().initialize(),
    PlayerBackgroundService().initialize(),
    LyricFontService().initialize(),
  ]);
  UpdateService.instance.setCurrentVersion(appVersion);
  Widget app = MyApp(dependencies: AppDependencies.production());
  if (!probeNoGlass) {
    app = LiquidGlassWidgets.wrap(
      adaptiveQuality: true,
      theme: const GlassThemeData(),
      child: app,
    );
  }
  if (probeNoSemantics) app = ExcludeSemantics(child: app);
  runApp(app);
}

/// 桌面窗口初始化：隐藏原生标题栏（走应用内融合标题栏）、设最小窗口尺寸。
///
/// 仅 Windows / macOS / Linux 执行；移动端直接返回。最小宽度取 640——低于
/// 桌面断点 900，窗口收窄到 900 以下即回落到移动端布局，仍可正常显示。
Future<void> _initDesktopWindow() async {
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1180, 760),
    minimumSize: Size(640, 480),
    center: true,
    title: 'Cyrene Music',
    // hidden：去掉系统标题栏与边框按钮，由应用自绘（含拖拽区与 caption 按钮）。
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.dependencies});

  final AppDependencies? dependencies;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late final AppDependencies _dependencies =
      widget.dependencies ?? AppDependencies.preview();
  late final PlaybackHistoryRecorder _historyRecorder;
  late final MediaNotificationService _mediaNotification;
  ListeningCardSync? _listeningCardSync;

  @override
  void initState() {
    super.initState();
    // 系统明暗切换（themeMode=system 时）要重建整树并刷新状态栏图标。
    WidgetsBinding.instance.addObserver(this);
    _dependencies.account.restore();
    _dependencies.audioSources.restore();
    _dependencies.playback.restore();
    // Cyrene Premium 自动下发：登录恢复后静默补发/刷新 OmniParse 配置（24h 节流）。
    _listeningCardSync = ListeningCardSync(
      account: _dependencies.account,
      audioSources: _dependencies.audioSources,
    )..start();
    // 播放历史/听歌统计记录：无它则「我的」中的历史与统计恒为空。
    _historyRecorder = PlaybackHistoryRecorder(
      playback: _dependencies.playback,
      account: _dependencies.account,
    );
    // 安卓系统通知栏媒体控制器：监听播放状态，同步到通知栏 + MediaSession。
    _mediaNotification = MediaNotificationService(_dependencies.playback)
      ..start();
    // Flutter 在 Android 上默认不申请高刷模式（小米/HyperOS 上常被锁 60Hz），
    // 首帧后再请求：过早调用在部分机型会拿到空的显示模式列表。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enableHighRefreshRate();
    });
  }

  Future<void> _enableHighRefreshRate() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (e) {
      // 不支持的机型/ROM 拿不到模式列表属正常情况，静默降级即可。
      debugPrint('[DisplayMode] 申请高刷新率失败: $e');
    }
  }

  @override
  void didChangePlatformBrightness() {
    // PlatformDispatcher 不是 Listenable，系统明暗只能靠此回调触发重建。
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _historyRecorder.dispose();
    _mediaNotification.dispose();
    _listeningCardSync?.dispose();
    _dependencies.dispose();
    super.dispose();
  }

  /// 外观偏好 → Miuix 配色模式：
  /// 开启跟随系统主题色或设置了种子色时走 Monet 动态取色，否则用静态
  /// HyperOS 配色；明暗维度由 themeMode 决定。
  static MiuixColorSchemeMode _colorSchemeMode(
    AppearanceSettingsStore appearance,
  ) {
    final dynamicColor =
        appearance.followSystemColor || appearance.seedColor != null;
    return switch (appearance.themeMode) {
      ThemeMode.system =>
        dynamicColor
            ? MiuixColorSchemeMode.monetSystem
            : MiuixColorSchemeMode.system,
      ThemeMode.light =>
        dynamicColor
            ? MiuixColorSchemeMode.monetLight
            : MiuixColorSchemeMode.light,
      ThemeMode.dark =>
        dynamicColor
            ? MiuixColorSchemeMode.monetDark
            : MiuixColorSchemeMode.dark,
    };
  }

  /// 解析当前应使用的明暗：themeMode 为 system 时跟随平台，否则取显式选择。
  /// 状态栏图标 / 系统栏颜色等需要「最终亮度」的地方都走它，保证与主题一致。
  static Brightness _resolvedBrightness(AppearanceSettingsStore appearance) {
    final mode = appearance.themeMode;
    if (mode == ThemeMode.light) return Brightness.light;
    if (mode == ThemeMode.dark) return Brightness.dark;
    // system：无法在此拿到 BuildContext，用平台 API 判系统明暗（与
    // MiuixThemeController 内部 MediaQuery.platformBrightnessOf 同源）。
    final view = WidgetsBinding.instance.platformDispatcher;
    return view.platformBrightness == Brightness.dark
        ? Brightness.dark
        : Brightness.light;
  }

  /// 根据当前主题亮度生成系统 UI 覆盖样式：
  /// - 状态栏 / 导航栏背景透明（走 edgeToEdge，由内容自己留白避让）；
  /// - 浅色主题下图标转黑、深色主题转白，解决「浅色模式状态栏仍是白底白字看不清」。
  static SystemUiOverlayStyle _systemOverlayStyle(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      // 安卓：状态栏图标亮度（light=白字 / dark=黑字）。
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      // iOS：状态栏文字亮度（dark=黑字 / light=白字，与安卓命名相反）。
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      AppearanceSettingsStore.instance,
      // 性能叠加层开关由 MaterialApp 消费，变更时需要整树重建。
      DeveloperModeService.instance,
    ]),
    // 系统明暗跟随见 didChangePlatformBrightness（走 setState 重建）。
    builder: (context, _) {
      final appearance = AppearanceSettingsStore.instance;
      final brightness = _resolvedBrightness(appearance);
      // edgeToEdge + 透明系统栏：图标随明暗自适应，浅色模式不再白底白字。
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(_systemOverlayStyle(brightness));
      return MiuixThemeController(
        colorSchemeMode: _colorSchemeMode(appearance),
        // keyColor 为空时 Monet 模式读取壁纸取色（Android 12+）。
        keyColor: appearance.followSystemColor ? null : appearance.seedColor,
        // 全应用统一 MiSans：库默认的 textStyles 不带字体族，Miuix 组件会吃
        // 平台默认字体（Windows Segoe UI / 安卓 Roboto），导致桌面端各页面
        // 字形粗细不一。字号字重不动，只补字体族。
        textStyles: CyreneMiuixTheme.textStyles(),
        child: _buildApp(),
      );
    },
  );

  Widget _buildApp() => Builder(
    builder: (context) {
      final miuix = MiuixTheme.of(context);
      return MaterialApp(
        title: 'Cyrene Music',
        debugShowCheckedModeBanner: false,
        // fluent_ui 的 NavigationView 等桌面组件需要 FluentLocalizations;
        // 追加此委托即可(Material/Cupertino 的默认本地化仍由 MaterialApp 兜底)。
        localizationsDelegates: const [FluentLocalizations.delegate],
        showPerformanceOverlay:
            DeveloperModeService.instance.showPerformanceOverlay,
        theme: CyreneMiuixTheme.material(miuix),
        builder: (context, child) {
          // 桌面融合标题栏隐藏了 Win32 原生边框,顶部边缘的窗口缩放由
          // VirtualWindowFrame 的 DragToResizeArea 接管(Windows:仅顶部三边,
          // 因原生 NCHITTEST 仍处理其余);移动端/窄窗不受影响。
          final frame = probeNoFrame
              ? (child ?? const SizedBox.shrink())
              : VirtualWindowFrameInit()(context, child);
          // fluent 的浮层(桌面侧栏折叠后每项的文字提示)只认根 Overlay,
          // 而根 Overlay 在这个 child 里面 —— FluentTheme 必须挂在它之上,
          // 否则浮层构建时找不到主题直接断言崩溃。这层不改任何既有样式,
          // 详见 DesktopRootFluentTheme 的文档。
          return DesktopRootFluentTheme(
            child: GlassTheme(
              data: const GlassThemeData(),
              child: Stack(
                children: [
                  frame,
                  // 全局 toast 层：挂在 Navigator 之上，任何路由都能弹出。
                  if (!probeNoToast) Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 92),
                        child: MiuixSnackbarHost(
                          state: CyreneToast.hostState,
                          blurSigma: 30,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        home: MusicAppShell(
          account: _dependencies.account,
          audioSources: _dependencies.audioSources,
          discover: _dependencies.discover,
          home: _dependencies.home,
          playback: _dependencies.playback,
          playlists: _dependencies.playlists,
          search: _dependencies.search,
        ),
      );
    },
  );
}
