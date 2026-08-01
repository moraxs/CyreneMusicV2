import 'package:fluent_ui/fluent_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../debug_probe.dart';

/// 桌面融合标题栏:替代被隐藏的 Win32 原生标题栏(见 main.dart
/// `_initDesktopWindow`,`TitleBarStyle.hidden`)。
///
/// 结构与 Win11 原生 App 一致:最左侧导航折叠按钮 + 应用图标 + 应用名/当前
/// 区块标题,中间整条空白为拖拽区(双击最大化/还原),右侧最小化 / 最大化·
/// 还原 / 关闭三枚 caption 按钮。caption 按钮直接用 window_manager 自带的
/// [WindowCaptionButton](Chrome 系矢量图标,与系统一致),明暗跟随 fluent 主题。
///
/// 由 `DesktopShell` 塞进 `NavigationView.titleBar` 槽,fluent 会把它摆在侧栏
/// 与内容区之上、横跨整个窗口宽度,高度取 Win11 标准 48。
class DesktopTitleBar extends StatefulWidget {
  const DesktopTitleBar({
    super.key,
    required this.title,
    required this.paneOpen,
    required this.onTogglePane,
    this.onBack,
  });

  /// 当前区块标题(随左侧导航选中项变化),显示在应用名之后。
  final String title;

  /// 侧栏当前是否展开,只用来决定汉堡按钮的提示文案。
  final bool paneOpen;

  /// 点汉堡按钮:展开 / 收起侧栏。
  final VoidCallback onTogglePane;

  /// 二级页返回:非 null 时在汉堡按钮左侧渲染一枚返回按钮,点击回调
  /// (由外壳置回首页);null 则与之前一样只有汉堡按钮。
  final VoidCallback? onBack;

  @override
  State<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<DesktopTitleBar> with WindowListener {
  /// 最大化状态决定右侧中间那枚按钮是「最大化」还是「还原」。
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  // 拖拽吸附(Win+方向键 / 拖到屏幕边缘)也会改变最大化状态,故两个回调都同步。
  @override
  void onWindowMaximize() => _setMaximized(true);

  @override
  void onWindowUnmaximize() => _setMaximized(false);

  Future<void> _syncMaximized() async {
    final maximized = await windowManager.isMaximized();
    _setMaximized(maximized);
  }

  void _setMaximized(bool value) {
    if (!mounted || _isMaximized == value) return;
    setState(() => _isMaximized = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          // 二级页返回:覆盖首页内容时出现,与汉堡按钮同列(50 宽)。
          if (widget.onBack != null)
            SizedBox(
              width: kCompactNavigationPaneWidth,
              child: probeTooltip(
                child: IconButton(
                  icon: const Icon(FluentIcons.chrome_back),
                  onPressed: widget.onBack,
                ),
                build: () => Tooltip(
                  message: '返回首页',
                  child: IconButton(
                    icon: const Icon(FluentIcons.chrome_back),
                    onPressed: widget.onBack,
                  ),
                ),
              ),
            ),
          // 折叠/展开侧栏。不放进拖拽区,否则点击会被 onPanStart 抢走。
          _PaneToggleButton(
            expanded: widget.paneOpen,
            onPressed: widget.onTogglePane,
          ),
          // 拖拽区占满剩余宽度:整条标题栏(除按钮外)都能拖动窗口、双击最大化。
          Expanded(
            child: DragToMoveArea(
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  // 应用图标：与登录页/关于页同源的真实品牌图标（深色底白
                  // 字），替换此前占位的音符。整图本身带底色，不做着色
                  // （Image color 是 srcIn 整体替换像素，会把图标染成单色）。
                  Image.asset(
                    'assets/icons/new_ico_white.png',
                    width: 20,
                    height: 20,
                    // 按显示尺寸解码，避免 2048² 原图占用无谓内存。
                    cacheWidth: (20 *
                            MediaQuery.devicePixelRatioOf(context))
                        .round(),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Cyrene Music',
                    style: theme.typography.caption?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 分隔点 + 区块标题:标题过长时省略,不挤压 caption 按钮。
                  Text('·', style: theme.typography.caption),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.caption,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
          // caption 按钮不放进拖拽区,否则点击会被 onPanStart 抢走。
          WindowCaptionButton.minimize(
            brightness: theme.brightness,
            onPressed: () => windowManager.minimize(),
          ),
          if (_isMaximized)
            WindowCaptionButton.unmaximize(
              brightness: theme.brightness,
              onPressed: () => windowManager.unmaximize(),
            )
          else
            WindowCaptionButton.maximize(
              brightness: theme.brightness,
              onPressed: () => windowManager.maximize(),
            ),
          WindowCaptionButton.close(
            brightness: theme.brightness,
            onPressed: () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}

/// 标题栏最左侧的导航折叠按钮(汉堡),等价于 fluent 自带的 [PaneToggleButton]。
///
/// 之所以自己画一枚:一是库里那枚的 Tooltip 文案写死英文 'Toggle navigation',
/// 与全中文界面不搭;二是它按的是 `NavigationView.togglePane()`,而侧栏固定在
/// expanded 显示模式(理由见 `DesktopShell` 类文档),那个方法在此模式下直接
/// return,按了没反应——收展状态由外壳自己持有。
///
/// 宽度对齐收起态侧栏(50),图标恰好落在侧栏图标的同一列上,和 Win11 一致。
class _PaneToggleButton extends StatelessWidget {
  const _PaneToggleButton({required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kCompactNavigationPaneWidth,
      child: probeTooltip(
        child: IconButton(
          icon: const Icon(WindowsIcons.global_nav_button),
          onPressed: onPressed,
        ),
        build: () => Tooltip(
          message: expanded ? '收起侧栏' : '展开侧栏',
          child: IconButton(
            icon: const Icon(WindowsIcons.global_nav_button),
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}
