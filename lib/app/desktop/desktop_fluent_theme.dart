import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixTheme;

import '../../presentation/cyrene/cyrene_theme.dart';

/// 桌面外壳(融合标题栏 + fluent [NavigationView] 侧栏)统一的 fluent 主题。
///
/// 亮度与主色同步 Miuix:明暗切换、主题色变更会由上层 MiuixThemeController
/// 重建整树带动这里重算,每次读到的都是最新值。
///
/// 三处底色统统压成 Miuix 的页面灰(侧栏 Mica、内容区底、浮层):内容页是
/// HyperOS 灰底白卡,fluent 默认那套灰会和它打架。侧栏与内容区之间的分界改由
/// fluent 内容卡的 1px 描边 + 左上圆角承担。
FluentThemeData desktopFluentTheme(BuildContext context) {
  final miuix = MiuixTheme.of(context);
  final surface = miuix.colors.surface;
  return FluentThemeData(
    brightness: miuix.brightness,
    accentColor: miuix.colors.primary.toAccentColor(),
    visualDensity: VisualDensity.standard,
    // fluent 自带一套 Typography(默认 Windows 平台字体),不指定就会让侧栏与
    // 标题栏的字形和用 MiSans 的其余部分不一致。
    fontFamily: cyreneFontFamily,
    scaffoldBackgroundColor: surface,
    micaBackgroundColor: surface,
    navigationPaneTheme: NavigationPaneThemeData(
      backgroundColor: surface,
      overlayBackgroundColor: surface,
    ),
    // 标题栏上一级/下一级等按钮的提示延迟:与 Material Tooltip 的 500ms
    // 体验对齐(fluent 默认悬停 0 延迟即显,偏急躁)。**不要动 showDuration**:
    // merge 时非空的 showDuration 会覆盖掉默认的 1500ms,导致拖拽区里的
    // Tooltip 按 150ms tick 高频显隐、整条标题栏子树反复重建,进而打断
    // DragToMoveArea 的 pan 识别,窗口变成不可拖动(见 desktop_title_bar.dart
    // 顶部类文档对《拖不动》问题的完整分析)。
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
  );
}

/// 把 [FluentTheme] 挂到根 Overlay 之上,同时**不改变**下游任何既有样式。
///
/// 为什么必须挂这么高:fluent 的 Tooltip / Flyout 一律把浮层插进
/// `Overlay.of(context, rootOverlay: true)`——也就是 MaterialApp 里 Navigator
/// 自带的那个根 Overlay,它在桌面外壳*外面*。只在外壳内部包 FluentTheme 的话,
/// 浮层构建时找不到主题会直接断言崩溃:侧栏收成 compact 后,每个 PaneItem 都会
/// 用文字提示代替标签,悬停必现。
///
/// 为什么要还原样式:[FluentTheme] 会往子树注入自己的 DefaultTextStyle 与
/// IconTheme(fluent 的 14 号 body + 16 号图标),整个应用吃下去就全变样了。
/// 这里把「包裹之前」的两者原样还原给下游,于是真正吃 fluent 主题的仍然只有
/// 桌面外壳自己那棵子树,以及确实需要它的浮层。
///
/// 为什么不按平台跳过:桌面布局是按窗口宽度切的(见 `isDesktopLayout`),安卓
/// 平板横屏同样会走桌面外壳,按 `Platform` 判断会漏掉这种情况。包一层不改样式,
/// 移动端只多一层惰性 InheritedWidget。
class DesktopRootFluentTheme extends StatelessWidget {
  const DesktopRootFluentTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 逐字段复刻:DefaultTextStyle 不与祖先合并,只有最近的那层生效,所以照抄
    // 字段就等价于「没被包过」。
    final text = DefaultTextStyle.of(context);
    return FluentTheme(
      data: desktopFluentTheme(context),
      child: DefaultTextStyle(
        style: text.style,
        textAlign: text.textAlign,
        softWrap: text.softWrap,
        overflow: text.overflow,
        maxLines: text.maxLines,
        textWidthBasis: text.textWidthBasis,
        textHeightBehavior: text.textHeightBehavior,
        child: IconTheme(data: IconTheme.of(context), child: child),
      ),
    );
  }
}
