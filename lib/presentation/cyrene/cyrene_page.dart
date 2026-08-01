import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// 标准页面骨架：MiuixScaffold + HyperOS 风格大标题可折叠顶栏。
///
/// [largeTitle] 为 true（默认）时使用 [MiuixTopAppBar]：展开显示大标题、
/// 上滑先折叠为小标题再滚动内容（HyperOS 系统设置的标志性布局）；为 false
/// 时退回静态小标题顶栏。内容自行处理滚动；顶栏高度与安全区以 padding.top
/// 应用到内容根部。页面底色走 MiuixScaffold 默认 `colors.surface`
/// （浅色 #F7F7F7 灰），卡片用 `surfaceContainer`（白），即 HyperOS 灰底白卡。
class CyrenePage extends StatefulWidget {
  const CyrenePage({
    super.key,
    required this.title,
    this.body,
    this.bodyBuilder,
    this.actions = const [],
    this.showBackButton = true,
    this.largeTitle = true,
    this.topBarTintAlpha,
  }) : assert(
         (body == null) != (bodyBuilder == null),
         'body 与 bodyBuilder 必须二选一',
       );

  final String title;

  /// 传统模式：内容整体下移到顶栏之下，不参与毛玻璃穿透。
  final Widget? body;

  /// 毛玻璃穿透模式：页面把回调给的 padding（顶栏当前占位）融入自己
  /// 滚动视图的 padding，内容从顶栏下方滚过，顶栏的实时虚化才有对象。
  final Widget Function(BuildContext context, EdgeInsets padding)? bodyBuilder;

  final List<Widget> actions;
  final bool showBackButton;
  final bool largeTitle;

  /// 顶栏毛玻璃色调不透明度 [0,1]，仅 [largeTitle] 为 true 时生效。
  /// 不传时走 [MiuixTopAppBar] 默认 0.55；登录页等需要让背景渐变/光斑
  /// 透到栏内、栏与内容区连成一片时传 0 即可得到「栏完全透明、只有模糊」。
  final double? topBarTintAlpha;

  @override
  State<CyrenePage> createState() => _CyrenePageState();
}

class _CyrenePageState extends State<CyrenePage> {
  final _scrollBehavior = MiuixExitUntilCollapsedScrollBehavior();

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final navigationIcon = widget.showBackButton && canPop
        ? CyreneBackButton(onPressed: () => Navigator.maybePop(context))
        : null;
    final actions = widget.actions.isEmpty ? null : widget.actions;
    return MiuixScaffold(
      topBar: widget.largeTitle
          ? MiuixTopAppBar(
              title: widget.title,
              navigationIcon: navigationIcon,
              actions: actions,
              scrollBehavior: _scrollBehavior,
              // 顶栏毛玻璃：BackdropFilter 实时虚化身后滚过的内容。
              blurred: true,
              blurTintAlpha: widget.topBarTintAlpha ?? 0.55,
            )
          : MiuixSmallTopAppBar(
              title: widget.title,
              navigationIcon: navigationIcon,
              actions: actions,
            ),
      content: (padding) {
        final inset = EdgeInsets.only(top: padding.top);
        final child = widget.bodyBuilder != null
            ? Builder(builder: (context) => widget.bodyBuilder!(context, inset))
            : Padding(padding: inset, child: widget.body);
        return Material(
          type: MaterialType.transparency,
          child: widget.largeTitle
              ? MiuixScrollBehaviorListener(
                  behavior: _scrollBehavior,
                  child: child,
                )
              : child,
        );
      },
    );
  }
}

/// 顶栏返回按钮。
class CyreneBackButton extends StatelessWidget {
  const CyreneBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => MiuixIconButton(
    onPressed: onPressed ?? () => Navigator.maybePop(context),
    child: MiuixIcon(vector: MiuixIcons.extended.byName('back')!, size: 24),
  );
}

class CyreneSectionTitle extends StatelessWidget {
  const CyreneSectionTitle({
    super.key,
    required this.title,
    this.description,
    this.trailing,
  });

  final String title;
  final String? description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textStyles.title3.copyWith(
                  color: theme.colors.onBackground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 4),
                Text(
                  description!,
                  style: theme.textStyles.body2.copyWith(
                    color: theme.colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// 彩色 squircle 图标块。图形优先取 miuix 矢量图标 [vector]，
/// 仅在 miuix 图标集无对应物时回退到 Material [icon]（两者必须给其一）。
class CyreneIconBox extends StatelessWidget {
  const CyreneIconBox({
    super.key,
    this.icon,
    this.vector,
    this.foregroundColor,
    this.backgroundColor,
    this.size = 40,
  }) : assert(
         (icon != null) != (vector != null),
         'CyreneIconBox: icon / vector 必须二选一',
       );

  /// Material 图标（回退路径）。与 [vector] 二选一。
  final IconData? icon;

  /// miuix 矢量图标，取自 `MiuixIcons.extended.byName(...)`。与 [icon] 二选一。
  final MiuixVectorIcon? vector;

  final Color? foregroundColor;
  final Color? backgroundColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final tint = foregroundColor ?? colors.onSecondaryContainer;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: backgroundColor ?? colors.secondaryContainer,
        shape: MiuixSquircleBorder(cornerRadius: size * .25),
      ),
      // miuix 矢量图标的可视图形普遍比视口小一圈，放大到 .68 才与
      // Material 图标 .55 的观感体量一致。
      child: vector != null
          ? MiuixIcon(vector: vector, size: size * .68, tint: tint)
          : Icon(icon, size: size * .55, color: tint),
    );
  }
}

class CyreneEmptyState extends StatelessWidget {
  const CyreneEmptyState({
    super.key,
    this.icon,
    this.vector,
    required this.title,
    required this.description,
    this.action,
  }) : assert(
         (icon != null) != (vector != null),
         'CyreneEmptyState: icon / vector 必须二选一',
       );

  /// Material 图标（回退路径）。与 [vector] 二选一。
  final IconData? icon;

  /// miuix 矢量图标，取自 `MiuixIcons.extended.byName(...)`。与 [icon] 二选一。
  final MiuixVectorIcon? vector;

  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SizedBox(
            width: double.infinity,
            child: MiuixCard(
              insideMargin: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CyreneIconBox(icon: icon, vector: vector, size: 52),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textStyles.title4.copyWith(
                      color: theme.colors.onSurfaceContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: theme.textStyles.body2.copyWith(
                      color: theme.colors.onSurfaceVariantSummary,
                    ),
                  ),
                  if (action != null) ...[const SizedBox(height: 18), action!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 行内提示条（替代原 ShadAlert）。
class CyreneInlineAlert extends StatelessWidget {
  const CyreneInlineAlert({
    super.key,
    this.icon,
    this.vector,
    this.title,
    required this.description,
    this.destructive = false,
  }) : assert(
         (icon != null) != (vector != null),
         'CyreneInlineAlert: icon / vector 必须二选一',
       );

  /// Material 图标（回退路径）。与 [vector] 二选一。
  final IconData? icon;

  /// miuix 矢量图标，取自 `MiuixIcons.extended.byName(...)`。与 [icon] 二选一。
  final MiuixVectorIcon? vector;

  final String? title;
  final String description;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final background = destructive
        ? colors.errorContainer
        : colors.secondaryContainer;
    final foreground = destructive
        ? colors.onErrorContainer
        : colors.onSecondaryContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: ShapeDecoration(
        color: background,
        shape: const MiuixSquircleBorder(cornerRadius: 14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          vector != null
              ? MiuixIcon(vector: vector, size: 20, tint: foreground)
              : Icon(icon, size: 20, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: theme.textStyles.body2.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                Text(
                  description,
                  style: theme.textStyles.footnote1.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// HyperOS 风格的分组卡片：白色 squircle 大圆角卡片，组内行直接堆叠、
/// 无分隔线（对照系统设置截图）。
class CyreneMenuGroup extends StatelessWidget {
  const CyreneMenuGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // MiuixCard 只裁剪背景不裁剪子级，行按压高亮是全宽矩形，
    // 需在此裁剪到卡片同款 squircle，否则首末行按压时方角会溢出圆角。
    return MiuixCard(
      cornerRadius: 20,
      child: ClipPath(
        clipper: const ShapeBorderClipper(
          shape: MiuixSquircleBorder(cornerRadius: 20),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: children),
        ),
      ),
    );
  }
}

/// HyperOS 风格的设置行：彩色圆角图标块（白色图形）+ 标题/摘要 +
/// 右侧灰色状态文字（[value]）+ 浅灰箭头。
class CyreneMenuRow extends StatelessWidget {
  const CyreneMenuRow({
    super.key,
    this.icon,
    this.vector,
    this.leading,
    required this.title,
    this.subtitle,
    this.value,
    this.iconBackground,
    this.trailing,
    this.onTap,
    this.destructive = false,
  }) : assert(
         (icon != null) != (vector != null) || leading != null,
         'CyreneMenuRow: leading 与 icon/vector 必须二选一',
       );

  /// Material 图标（回退路径）。与 [vector] 二选一，或与 [leading] 互斥。
  final IconData? icon;

  /// miuix 矢量图标，取自 `MiuixIcons.extended.byName(...)`。与 [icon] 二选一，
  /// 或与 [leading] 互斥。
  final MiuixVectorIcon? vector;

  /// 自定义起始侧内容（如用户头像）。非空时取代默认的 [CyreneIconBox]，
  /// 用于图标块无法表达的内容（真实头像等）。与 [icon]/[vector] 互斥。
  final Widget? leading;

  final String title;
  final String? subtitle;

  /// 右侧状态文字（如「已开启」「自动」），HyperOS 式灰色小字。
  final String? value;

  /// 图标块底色；非空时图形固定为白色（HyperOS 彩色图标样式），
  /// 为空时退回中性 secondaryContainer 底 + 前景色图形。
  final Color? iconBackground;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final background = iconBackground ?? (destructive ? colors.error : null);
    return MiuixBasicComponent(
      // 不走组件默认的 title/summary（headline1 17px + w500 偏大偏粗），
      // 用 content 自绘：标题 15px 常规字重、摘要 13px。
      content: [
        MiuixText(
          title,
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: destructive ? colors.error : colors.onBackground,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          MiuixText(
            subtitle!,
            fontSize: 13,
            color: colors.onSurfaceVariantSummary,
          ),
        ],
      ],
      insideMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      startAction: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: leading ??
            CyreneIconBox(
              icon: icon,
              vector: vector,
              // HyperOS 系统设置图标块约 28~30px；原 34 偏大，统一收敛到 30，
              // 设置主页与各二级菜单/选项 sheet 共用此行，一并缩小。
              size: 30,
              backgroundColor: background,
              foregroundColor: background != null ? Colors.white : null,
            ),
      ),
      endActions: [
        if (value != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              value!,
              style: theme.textStyles.footnote1.copyWith(
                color: colors.onSurfaceVariantActions,
              ),
            ),
          ),
        trailing ??
            MiuixIcon(
              vector: MiuixIcons.extended.byName('chevronForward')!,
              size: 15,
              tint: colors.onSurfaceVariantActions,
            ),
      ],
      onClick: onTap,
      role: MiuixBasicComponentRole.button,
    );
  }
}

/// HyperOS 风格下拉刷新：把 Material `RefreshIndicator` 的「async 回调自驱」
/// 语义适配到 [MiuixPullToRefresh] 的「外部提升 isRefreshing」语义。
///
/// 两者模型不同，差异都收敛在这里，调用方只需照旧提供一个 async 回调：
/// - Material：`onRefresh: () => Future`，指示器在 future 期间自行转圈；
/// - Miuix：`isRefreshing` 由外部持有，`onRefresh` 是 VoidCallback，越过阈值
///   松手时触发，需调用方尽快把 isRefreshing 置 true、结束后置 false。
///
/// 另外 [MiuixPullToRefresh] 依赖顶边 `OverscrollNotification` 驱动下拉头，
/// 因此 [child] 的滚动体必须用 `ClampingScrollPhysics`（iOS 默认 bouncing 会
/// 自行消化越界位移、不发该通知），并配合这里关掉的 overscroll 拉伸指示器。
///
/// 页面自身已有真实刷新态（如 HomeController.state.isRefreshing）时，直接用
/// [MiuixPullToRefresh] 即可，无需本组件多存一份状态。
class CyrenePullToRefresh extends StatefulWidget {
  const CyrenePullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.contentPadding = EdgeInsets.zero,
  });

  final Future<void> Function() onRefresh;

  /// 需自行使用 `AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics())`
  /// 的纵向滚动体。
  final Widget child;

  /// 把下拉头下移到顶栏之下，等价于 `RefreshIndicator.edgeOffset`。
  /// 配合 [CyrenePage.bodyBuilder] 回调给的 padding 使用。
  final EdgeInsetsGeometry contentPadding;

  @override
  State<CyrenePullToRefresh> createState() => _CyrenePullToRefreshState();
}

class _CyrenePullToRefreshState extends State<CyrenePullToRefresh> {
  bool _refreshing = false;

  Future<void> _handleRefresh() async {
    if (_refreshing) return;
    // 必须同步置位：MiuixPullToRefresh 在回调后的下一帧就检查 isRefreshing，
    // 若仍为 false 会直接走「刷新完成」回弹。
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) => MiuixPullToRefresh(
    isRefreshing: _refreshing,
    onRefresh: _handleRefresh,
    contentPadding: widget.contentPadding,
    refreshTexts: const ['下拉刷新', '释放立即刷新', '正在刷新...', '刷新成功'],
    child: ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
      child: widget.child,
    ),
  );
}
