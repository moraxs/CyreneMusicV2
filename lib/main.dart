import 'dart:async';
import 'dart:io' show Platform;

import 'package:fluent_ui/fluent_ui.dart' show FluentLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/window.dart' as acrylic;
import 'package:flutter_acrylic/window_effect.dart' as acrylic;
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'app/app_dependencies.dart';
import 'app/app_gate.dart';
import 'app/app_version.dart';
import 'app/debug_probe.dart';
import 'app/desktop/desktop_fluent_theme.dart';
import 'app/desktop/window_accent_acrylic.dart';
import 'application/playback/playback_history_recorder.dart';
import 'application/stores/appearance_settings_store.dart';
import 'application/stores/fullscreen_settings_store.dart';
import 'application/stores/onboarding_store.dart';
import 'application/stores/window_material_settings_store.dart';
import 'features/desktop_player/desktop_player_app.dart';
import 'features/desktop_player/desktop_player_controller.dart';
import 'features/taskbar_player/taskbar_player_app.dart';
import 'features/taskbar_player/taskbar_player_controller.dart';
import 'features/player/mobile/compat/lyric_font_service.dart';
import 'features/player/mobile/compat/lyric_style_service.dart';
import 'features/player/mobile/compat/player_background_service.dart';
import 'infrastructure/core/url_service.dart';
import 'infrastructure/media_notification/media_notification_service.dart';
import 'infrastructure/media_notification/smtc_service.dart';
import 'infrastructure/services/developer_mode_service.dart';
import 'infrastructure/services/listening_card_sync.dart';
import 'infrastructure/services/update_service.dart';
import 'presentation/cyrene/cyrene_theme.dart';
import 'presentation/cyrene/cyrene_toast.dart';

/// 应用入口。
///
/// runner 自托管的子引擎使用同一个入口，通过 args 区分：
/// - 主窗口：args 为空或包含 flutter 命令行参数
/// - 壁纸层子引擎：args 含 'wallpaper-player'（由 desktop_lyrics_window.cpp 的
///   DartProject 入口参数传入，runner 自建 WS_POPUP 覆盖层并跑第二个引擎）
/// - 任务栏播放器子引擎：args 含 'taskbar-player'（由 taskbar_player_window.cpp
///   传入，runner 自建置顶 WS_POPUP 窄条并跑第三个引擎）
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // ===== 桌面歌词子引擎入口分支 =====
  // runner 的 desktop_lyrics_window.cpp 在创建覆盖层时给子引擎传入
  // entrypoint args = ["wallpaper-player"]，走此分支挂桌面歌词 App。
  if (args.contains('wallpaper-player')) {
    runApp(const DesktopPlayerApp());
    return;
  }

  // ===== 任务栏播放器子引擎入口分支 =====
  // runner 的 taskbar_player_window.cpp 传入 entrypoint args =
  // ["taskbar-player"]。这条窄栏只显示封面/标题/播放态/进度，不需要
  // media_kit、窗口效果、偏好存储等任何主窗口的初始化。
  if (args.contains('taskbar-player')) {
    runApp(const TaskbarPlayerApp());
    return;
  }

  // 捕获全应用 debugPrint 到开发者日志缓冲（开发者选项 → 运行日志）。
  final defaultDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) DeveloperModeService.instance.addLog(message);
    defaultDebugPrint(message, wrapWidth: wrapWidth);
  };
  installProbe();
  // media_kit 必须在使用前初始化（会加载 libmpv 原生库）。
  MediaKit.ensureInitialized();
  // 桌面端融合标题栏：隐藏 Win32 原生标题栏，改由 fluent TitleBar 绘制
  // （见 app/desktop/desktop_title_bar.dart）。必须在首帧前完成，否则会先
  // 闪一下原生标题栏。移动端不触碰（插件在 Android/iOS 上无对应实现）。
  await _initDesktopWindow();
  // 窗口材质与外观偏好须在窗口效果之前就绪：初始效果要按已保存的材质与
  // 明暗选择，否则暗色模式或换材质后启动会先闪一帧错误效果（见
  // _initDesktopBackdrop）。
  await Future.wait([
    WindowMaterialSettingsStore.instance.init(),
    AppearanceSettingsStore.instance.init(),
  ]);
  // Win11 窗口背景效果（云母 / 亚克力 / 不透明）见 _initDesktopBackdrop：
  // 仅桌面平台生效，需在首帧前初始化 flutter_acrylic（在 window_manager
  // 设完 titleBarStyle 后调用，避免原生标题栏残留）。
  await _initDesktopBackdrop();
  await Future.wait([
    if (!probeNoGlass) LiquidGlassWidgets.initialize(),
    UrlService.instance.init(),
    FullscreenSettingsStore.instance.init(),
    // 首启引导的进度标记（协议是否已同意 / 引导是否走完）。必须在首帧前就绪，
    // 否则老用户冷启动会先闪一帧引导页再切回主界面（见 AppGate）。
    OnboardingStore.instance.init(),
    // 开发者模式状态（决定设置页「开发者选项」入口与性能叠加层）。
    DeveloperModeService.instance.ensureLoaded(),
    // 移植版播放器（原版全屏播放器）的样式/背景/字体偏好，与原版 main 一致。
    LyricStyleService().initialize(),
    PlayerBackgroundService().initialize(),
    LyricFontService().initialize(),
  ]);
  UpdateService.instance.setCurrentVersion(appVersion);
  final dependencies = AppDependencies.production();
  // 桌面播放器的播放状态来源：子窗口是独立 isolate，歌词要靠主窗口把状态
  // 推送过去（见 desktop_player_bridge.dart）。无条件注入——设置页里随时
  // 可能打开开关，那里拿不到 AppDependencies。
  DesktopPlayerController.instance.playback = dependencies.playback;
  // 面板上的收藏按钮由主窗口代为执行（子窗口没有鉴权/网络栈）。
  DesktopPlayerController.instance.account = dependencies.account;
  // 启动时恢复桌面播放器：上次退出时如果开关是开着的，重新创建覆盖层窗口。
  // 否则会出现状态脱节——设置显示"已开启"但实际无窗口运行，关闭时卡死。
  if (Platform.isWindows &&
      FullscreenSettingsStore.instance.wallpaperPlayerEnabled) {
    DesktopPlayerController.instance.enable().catchError((e) {
      debugPrint('[桌面播放器] 启动恢复失败: $e');
      return null;
    });
  }
  // 任务栏播放器同理：状态由主窗口推送，开关状态跨启动恢复。
  TaskbarPlayerController.instance.playback = dependencies.playback;
  // 拖拽后的形态与悬浮位置由原生回报，落到偏好存储，下次启动原样恢复。
  TaskbarPlayerController.instance.onPlacementChanged =
      FullscreenSettingsStore.instance.setTaskbarPlayerPlacement;
  if (Platform.isWindows &&
      FullscreenSettingsStore.instance.taskbarPlayerEnabled) {
    final store = FullscreenSettingsStore.instance;
    TaskbarPlayerController.instance
        .enable(
          store.taskbarPlayerAlignment,
          mode: store.taskbarPlayerMode,
          x: store.taskbarPlayerFloatingX,
          y: store.taskbarPlayerFloatingY,
        )
        .catchError((e) {
          debugPrint('[任务栏播放器] 启动恢复失败: $e');
          return null;
        });
  }
  Widget app = MyApp(dependencies: dependencies);
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
  final options = WindowOptions(
    size: const Size(1180, 760),
    minimumSize: const Size(640, 480),
    center: true,
    title: 'Cyrene Music',
    // Windows：窗口背景设透明,让 flutter_acrylic 的 DWM 背景效果
    // （云母/亚克力，见 _initDesktopBackdrop）透出。若不设,window_manager
    // 会给客户区填一层不透明底色,盖住窗口效果——即便 setEffect 成功,窗口
    // 看上去仍是完全不透明。
    // macOS/Linux 尚未适配透明窗口(见 _initDesktopBackdrop 说明),保持不透明,
    // 否则会直接露出桌面。
    backgroundColor: Platform.isWindows ? Colors.transparent : Colors.white,
    // hidden：去掉系统标题栏与边框按钮，由应用自绘（含拖拽区与 caption 按钮）。
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

/// 按用户选择的窗口材质应用 Windows 背景效果，明暗随 [brightness] 切换。
///
/// - 不透明：`disabled` 关闭 DWM 背景效果，壳层由不透明 surface 自绘；
/// - 云母：Mica，flutter_acrylic 文档明确 `dark` 参数用于切换其明暗变体；
/// - 亚克力：真正的毛玻璃，走原生 ACCENT_ENABLE_ACRYLICBLURBEHIND（见
///   [_applyTrueAcrylic]）——flutter_acrylic 在 Win11 的 acrylic 只是 Mica
///   系 wallpaper backdrop，没有实时模糊桌面，达不到亚克力的效果。
///
/// 启动（[_initDesktopBackdrop]）与材质/明暗切换（[_MyAppState] 的
/// [_syncWindowBackdrop]）都汇聚到这里，保证 DWM 侧栏/标题栏底色与应用
/// 选择一致——否则切深色后透明背景仍露出浅色效果，侧栏和标题栏就还是白的。
Future<void> _applyWindowBackdrop({required Brightness brightness}) async {
  final dark = brightness == Brightness.dark;
  switch (WindowMaterialSettingsStore.instance.material) {
    case WindowMaterialType.opaque:
      return acrylic.Window.setEffect(
        effect: acrylic.WindowEffect.disabled,
        dark: dark,
      );
    case WindowMaterialType.mica:
      return acrylic.Window.setEffect(
        effect: acrylic.WindowEffect.mica,
        dark: dark,
      );
    case WindowMaterialType.acrylic:
      return _applyTrueAcrylic(dark: dark);
  }
}

/// 浅/深色下的亚克力半透明着色（AARRGGBB，A 在高字节），与参考实现
/// （cyrene_music_tauri 的 update_window_material）一致：
/// 浅 (255,255,255,180) / 深 (18,18,18,180)。
const _kAcrylicLightArgb = 0xB4FFFFFF;
const _kAcrylicDarkArgb = 0xB4121212;

/// 真正的亚克力：ACCENT_ENABLE_ACRYLICBLURBEHIND（毛玻璃）。
///
/// 先经 flutter_acrylic setEffect(disabled) 复位上一材质的 DWM 状态
/// （还原 Mica 的 DwmExtendFrameIntoClientArea 扩展边框与 MICA_EFFECT、
/// 置 ACCENT_DISABLED），再走原生通道叠加 ACCENT 亚克力——由 DWM 实时
/// 采样并模糊窗口背后的内容（壁纸/桌面图标/其他窗口）。
Future<void> _applyTrueAcrylic({required bool dark}) async {
  await acrylic.Window.setEffect(
    effect: acrylic.WindowEffect.disabled,
    dark: dark,
  );
  await WindowAccentAcrylic.instance.apply(
    argb: dark ? _kAcrylicDarkArgb : _kAcrylicLightArgb,
  );
}

/// Win11 窗口背景效果（云母 / 亚克力 / 不透明）：仅 Windows 生效
/// （Windows 10 上 Mica 不可用，亚克力/不透明正常）。
///
/// 必须在首帧前调用（在 [_initDesktopWindow] 设完 `TitleBarStyle.hidden`
/// 之后），否则会出现两帧不透明黑底再闪成背景效果的问题。只对 Windows
/// 启用的原因：
/// - macOS 走 NSVisualEffectView，由 flutter_acrylic 的 `setEffect` 映射，
///   但本项目 macOS 尚未适配透明窗口，先不动。
/// - Linux 需要宿主合成器支持（KWin 等），且需改 gtk 背景为透明
///   （linux/runner/my_application.cc 已同步修改），范围外。
Future<void> _initDesktopBackdrop() async {
  if (!Platform.isWindows) return;
  // 桌面布局按窗口宽度切（>=900），不在 _initDesktopWindow 判断里做。
  try {
    await acrylic.Window.initialize();
    // 背景效果为不透明/半透明材质：窗口底色会透出，Flutter 侧壳层
    // （DesktopShell 顶层 MaterialType.transparency）不遮挡，让效果透出。
    // 初始材质与明暗自适应：两个 store 已在调用前就绪（见 main），深色
    // 模式（含跟随系统的系统深色）启动直接用深色效果，不闪白帧。
    await _applyWindowBackdrop(
      brightness: _resolvedBrightness(AppearanceSettingsStore.instance),
    );
  } catch (e) {
    // Win10 / 不支持的合成器上静默降级，应用仍以纯色 surface 正常运行。
    debugPrint('[窗口材质] 初始化失败，已降级为纯色背景: $e');
  }
}

/// 解析当前应使用的明暗：themeMode 为 system 时跟随平台，否则取显式选择。
/// 状态栏图标 / 系统栏颜色 / 窗口背景效果明暗等需要「最终亮度」的地方都
/// 走它，保证与主题一致。
Brightness _resolvedBrightness(AppearanceSettingsStore appearance) {
  final mode = appearance.themeMode;
  if (mode == ThemeMode.light) return Brightness.light;
  if (mode == ThemeMode.dark) return Brightness.dark;
  // system：调用方可能没有 BuildContext，用平台 API 判系统明暗（与
  // MiuixThemeController 内部 MediaQuery.platformBrightnessOf 同源）。
  final view = WidgetsBinding.instance.platformDispatcher;
  return view.platformBrightness == Brightness.dark
      ? Brightness.dark
      : Brightness.light;
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
  late final SmtcService _smtc;
  ListeningCardSync? _listeningCardSync;

  /// 最近一次已同步到窗口背景效果的材质与明暗（Windows）。build 里据此
  /// 幂等跳过，材质/明暗未变时不重复打平台通道。
  WindowMaterialType? _appliedMaterial;
  Brightness? _appliedBackdropBrightness;

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
    // Windows 系统媒体传输控件（SMTC）：任务栏媒体浮层 / 键盘多媒体键。
    // 服务内部自检平台，非 Windows 上为空操作。
    _smtc = SmtcService(_dependencies.playback)..start();
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 播放进度平时是节流落盘的（见 PlaybackController._positionPersistInterval），
    // 离开前台时补一次精确值：安卓上进程随时可能被系统直接回收，届时不会再有
    // 任何回调，只有这里写下的位置能被下次冷启动读回。
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _dependencies.playback.flush();
      case AppLifecycleState.resumed:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _historyRecorder.dispose();
    _mediaNotification.dispose();
    _smtc.dispose();
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

  /// 窗口背景效果（材质 + 明暗）与应用主题同步（仅 Windows 桌面端）。
  ///
  /// 切换的路径（设置里改窗口材质 / 改深色 → 对应 store 通知、系统明暗
  /// 变化 → didChangePlatformBrightness 触发 setState）都会汇聚到 build 走到
  /// 这里。若不同步 DWM 的背景效果，侧栏/标题栏的透明背景会露出系统默认
  /// 浅色效果，切深色或换材质后依旧不匹配。材质与明暗都没变时直接返回，
  /// 幂等。
  void _syncWindowBackdrop(Brightness brightness) {
    if (!Platform.isWindows) return;
    final material = WindowMaterialSettingsStore.instance.material;
    if (_appliedMaterial == material &&
        _appliedBackdropBrightness == brightness) {
      return;
    }
    _appliedMaterial = material;
    _appliedBackdropBrightness = brightness;
    unawaited(
      _applyWindowBackdrop(brightness: brightness).catchError((Object e) {
        debugPrint('[窗口材质] 切换失败，已降级为纯色背景: $e');
      }),
    );
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
      // 窗口材质（云母/亚克力/不透明）变更时需整树重建，重算桌面壳层
      // 透明策略并同步 DWM 背景效果。
      WindowMaterialSettingsStore.instance,
      // 性能叠加层开关由 MaterialApp 消费，变更时需要整树重建。
      DeveloperModeService.instance,
    ]),
    // 系统明暗跟随见 didChangePlatformBrightness（走 setState 重建）。
    builder: (context, _) {
      final appearance = AppearanceSettingsStore.instance;
      final brightness = _resolvedBrightness(appearance);
      // 窗口背景效果（材质 + 明暗）随主题同步：设置切材质/深色、系统明暗
      // 变化都在这里收敛（幂等，未变直接返回，见 _syncWindowBackdrop）。
      _syncWindowBackdrop(brightness);
      // edgeToEdge + 透明系统栏：图标随明暗自适应，浅色模式不再白底白字。
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(_systemOverlayStyle(brightness));
      // 根部 AnnotatedRegion：按主题自适应状态栏图标明暗。普通页面无自己的
      // AnnotatedRegion 时走这里（浅色黑字 / 深色白字）；播放器/歌词页等深色
      // 页面自带 AnnotatedRegion 会作为栈顶覆盖，pop 后自动回退到这里的自适应
      // 样式——避免「进过深色播放器后返回浅色页面，状态栏仍钉成白字」。
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: _systemOverlayStyle(brightness),
        child: MiuixThemeController(
          colorSchemeMode: _colorSchemeMode(appearance),
          // keyColor 为空时 Monet 模式读取壁纸取色（Android 12+）。
          keyColor: appearance.followSystemColor ? null : appearance.seedColor,
          // 全应用统一 MiSans：库默认的 textStyles 不带字体族，Miuix 组件会吃
          // 平台默认字体（Windows Segoe UI / 安卓 Roboto），导致桌面端各页面
          // 字形粗细不一。字号字重不动，只补字体族。
          textStyles: CyreneMiuixTheme.textStyles(),
          child: _buildApp(),
        ),
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
        // 入口分流：首次启动走三步引导（协议 / 登录 / 音源），已完成则进主
        // 外壳。用户事后退出登录也会由它跳回登录步（见 AppGate）。
        home: AppGate(
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
