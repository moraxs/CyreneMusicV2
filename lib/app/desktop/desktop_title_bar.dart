import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';

import '../debug_probe.dart';
import '../../features/search/desktop_search_bar.dart';
import '../../infrastructure/services/system_tray_service.dart';

/// 桌面融合标题栏:替代被隐藏的 Win32 原生标题栏(见 main.dart
/// `_initDesktopWindow`,`TitleBarStyle.hidden`)。
///
/// 结构与 Win11 原生 App 一致:最左侧导航折叠按钮 + 应用图标 + 应用名,中间
/// 整条空白为拖拽区(双击最大化/还原),右侧最小化 / 最大化·还原 / 关闭三枚
/// caption 按钮。caption 按钮直接用 window_manager 自带的
/// [WindowCaptionButton](Chrome 系矢量图标,与系统一致),明暗跟随 fluent 主题。
///
/// 应用名右侧是「后退 / 前进」双按钮:常驻显示(不随导航状态隐藏),图标用
/// 自带的 Ooui 箭头 SVG,驱动首页二级页导航栈的后退 / 前进。不可后退 / 前进
/// 时按钮置灰(禁用),但仍占位显示。
///
/// 导航按钮之后是**居中的搜索框** [DesktopSearchBar]:夹在两段
/// [DragToMoveArea] 之间(自身也在拖拽区外,见下),两段等分剩余宽度把它推到
/// 正中。聚焦弹出热搜 / 历史 / 建议下拉,提交后交给 [onSubmitSearch]。
///
/// **为什么按钮不能放进 [DragToMoveArea]**:任何 hover 事件都会触发子树重建
/// (fluent 的按钮都有 hover 样式),而重建会打断 DragToMoveArea 的 pan 识别,
/// 表现为窗口拖不动(此前把按钮放拖拽区里实测即如此)。故本类把所有可交互
/// 按钮全部放在拖拽区之外;拖拽区内只有纯展示的图标与文字。后退/前进按钮
/// 因此夹在两段拖拽区之间:左段裹住图标与应用名,右段占满剩余宽度。
///
/// 由 `DesktopShell` 塞进 `NavigationView.titleBar` 槽,fluent 会把它摆在侧栏
/// 与内容区之上、横跨整个窗口宽度,高度取 Win11 标准 48。
class DesktopTitleBar extends StatefulWidget {
  const DesktopTitleBar({
    super.key,
    required this.title,
    required this.paneOpen,
    required this.onTogglePane,
    this.canGoBack = false,
    this.canGoForward = false,
    this.onBack,
    this.onForward,
    this.onSubmitSearch,
  });

  /// 当前区块标题(随左侧导航选中项变化),显示在应用名之后。
  final String title;

  /// 侧栏当前是否展开,只用来决定汉堡按钮的提示文案。
  final bool paneOpen;

  /// 点汉堡按钮:展开 / 收起侧栏。
  final VoidCallback onTogglePane;

  /// 首页二级页导航栈:是否有上一级 / 下一级页面可跳。按钮常驻显示,这两个
  /// 只决定按钮的可点态(为 false 时置灰、不可点),不再控制显隐。
  final bool canGoBack;
  final bool canGoForward;

  /// 后退 / 前进:对应导航栈的后退 / 前进。
  final VoidCallback? onBack;
  final VoidCallback? onForward;

  /// 标题栏搜索框提交关键词(已 trim、非空)。由外壳切到「搜索」页展示结果。
  final ValueChanged<String>? onSubmitSearch;

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
          // 折叠/展开侧栏。不放进拖拽区,否则点击会被 onPanStart 抢走。
          _PaneToggleButton(
            expanded: widget.paneOpen,
            onPressed: widget.onTogglePane,
          ),
          // 拖拽区(左段):只裹图标与应用名,内容宽度,不 Expanded。整段可拖动
          // 窗口、双击最大化。可交互按钮一律不进这里(见类文档)。
          DragToMoveArea(
            child: SizedBox(
              height: 48,
              child: Row(
                mainAxisSize: MainAxisSize.min,
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
                ],
              ),
            ),
          ),
          // 后退 / 前进:常驻显示,放在应用名右侧、拖拽区之外(见类文档)。
          // 驱动首页二级页导航栈;不可后退/前进时置灰,不隐藏。
          const SizedBox(width: 8),
          _TitleNavButton(
            asset: 'assets/icons/OouiNextRtl.svg',
            tooltip: '后退',
            onPressed: widget.canGoBack ? widget.onBack : null,
          ),
          const SizedBox(width: 2),
          _TitleNavButton(
            asset: 'assets/icons/OouiNextLtr.svg',
            tooltip: '前进',
            onPressed: widget.canGoForward ? widget.onForward : null,
          ),
          // 拖拽区(左段):占满搜索框左侧的剩余宽度,把搜索框推向正中。
          Expanded(
            child: DragToMoveArea(child: const SizedBox.expand()),
          ),
          // 居中搜索框:自身在拖拽区之外(输入框 hover/聚焦会重建,放进拖拽区
          // 会打断拖拽,见类文档)。两侧等分的拖拽区把它挤到标题栏正中。
          SizedBox(
            width: 360,
            child: DesktopSearchBar(
              onSubmit: widget.onSubmitSearch ?? (_) {},
            ),
          ),
          // 拖拽区(右段):占满搜索框右侧的剩余宽度,继续可拖动、双击最大化。
          Expanded(
            child: DragToMoveArea(child: const SizedBox.expand()),
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
            onPressed: () => SystemTrayService.instance.hideToTray(),
          ),
        ],
      ),
    );
  }
}

/// 标题栏的后退 / 前进按钮。图标是自带的 Ooui 箭头 SVG,按标题栏前景色着色
/// (srcIn 覆盖 SVG 内置的绿色填充),与应用名同色;`onPressed` 为 null 时改用
/// 禁用色手动置灰(IconButton 不会自动给自绘的 SVG 子部件降透明)。用 fluent
/// 的 [IconButton] 承载,点击交给它的 InkWell,不会触发相邻 [DragToMoveArea]
/// 的拖拽。外面再补一层 Tooltip 给悬停说明(500ms 延迟由桌面 fluent 主题统一
/// 给出)。
class _TitleNavButton extends StatelessWidget {
  const _TitleNavButton({
    required this.asset,
    required this.tooltip,
    required this.onPressed,
  });

  final String asset;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    final color = onPressed == null
        ? resources.textFillColorDisabled
        : resources.textFillColorPrimary;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: SvgPicture.asset(
          asset,
          width: 14,
          height: 14,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        ),
        onPressed: onPressed,
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
