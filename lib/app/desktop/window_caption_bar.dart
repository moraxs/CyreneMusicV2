import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:window_manager/window_manager.dart';

/// 极简窗口标题栏：应用图标 + 应用名 + 拖拽区 + caption 按钮。
///
/// Win32 原生标题栏在 main 的 `_initDesktopWindow` 里被隐藏了
/// （`TitleBarStyle.hidden`），**任何占满整窗的页面都必须自绘一条**，否则窗口
/// 既拖不动也没有最小化/关闭按钮。主界面那条是
/// [DesktopTitleBar]（带侧栏开关、前进后退与搜索框，依赖 fluent 与导航栈），
/// 首启引导 / 启动过渡这类还没有导航栈的页面用不了它，故有这条精简版。
///
/// 与 [DesktopTitleBar] 同构的两条约束：
/// - 高度取 Win11 标准 48；
/// - **可交互按钮一律放在 [DragToMoveArea] 之外**——hover 会触发子树重建，
///   而重建会打断 DragToMoveArea 的 pan 识别，表现为窗口拖不动。
///
/// 非桌面平台（Android / iOS）直接塌缩为零高度：那里既没有隐藏标题栏，也没有
/// window_manager 的原生实现，渲染它只会抛 MissingPluginException。
class WindowCaptionBar extends StatefulWidget {
  const WindowCaptionBar({super.key});

  /// 当前平台是否需要自绘标题栏（与 main 的 `_initDesktopWindow` 判定一致：
  /// 那里隐藏了哪些平台的原生标题栏，这里就要补上哪些）。
  static bool get isSupported =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  State<WindowCaptionBar> createState() => _WindowCaptionBarState();
}

class _WindowCaptionBarState extends State<WindowCaptionBar> with WindowListener {
  /// 最大化状态决定中间那枚按钮是「最大化」还是「还原」。
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (!WindowCaptionBar.isSupported) return;
    windowManager.addListener(this);
    _syncMaximized();
  }

  @override
  void dispose() {
    if (WindowCaptionBar.isSupported) windowManager.removeListener(this);
    super.dispose();
  }

  // 拖拽吸附（Win+方向键 / 拖到屏幕边缘）也会改变最大化状态，故两个回调都同步。
  @override
  void onWindowMaximize() => _setMaximized(true);

  @override
  void onWindowUnmaximize() => _setMaximized(false);

  Future<void> _syncMaximized() async {
    try {
      _setMaximized(await windowManager.isMaximized());
    } catch (_) {
      // 原生实现缺席（测试环境等）时保持未最大化，标题栏仍可正常渲染。
    }
  }

  void _setMaximized(bool value) {
    if (!mounted || _isMaximized == value) return;
    setState(() => _isMaximized = value);
  }

  @override
  Widget build(BuildContext context) {
    if (!WindowCaptionBar.isSupported) return const SizedBox.shrink();
    final theme = MiuixTheme.of(context);
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          // 拖拽区：占满 caption 按钮左侧的全部宽度，内含纯展示的图标与应用名
          // （可交互部件不能放进来，见类文档）。整段可拖动窗口、双击最大化。
          Expanded(
            child: DragToMoveArea(
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    // 与登录页/关于页同源的真实品牌图标（整图自带底色，不做
                    // 着色——Image color 是 srcIn 整体替换像素，会染成单色）。
                    Image.asset(
                      'assets/icons/new_ico_white.png',
                      width: 20,
                      height: 20,
                      // 按显示尺寸解码，避免 2048² 原图占用无谓内存。
                      cacheWidth:
                          (20 * MediaQuery.devicePixelRatioOf(context)).round(),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Cyrene Music',
                      style: theme.textStyles.footnote1.copyWith(
                        color: theme.colors.onBackground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // caption 按钮不放进拖拽区，否则点击会被 onPanStart 抢走。
          WindowCaptionButton.minimize(
            brightness: theme.brightness,
            onPressed: windowManager.minimize,
          ),
          if (_isMaximized)
            WindowCaptionButton.unmaximize(
              brightness: theme.brightness,
              onPressed: windowManager.unmaximize,
            )
          else
            WindowCaptionButton.maximize(
              brightness: theme.brightness,
              onPressed: windowManager.maximize,
            ),
          WindowCaptionButton.close(
            brightness: theme.brightness,
            onPressed: windowManager.close,
          ),
        ],
      ),
    );
  }
}
