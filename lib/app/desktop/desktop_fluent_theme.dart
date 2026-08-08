import 'dart:io' show Platform;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_miuix/miuix.dart' show MiuixTheme;

import '../../application/stores/window_material_settings_store.dart';
import '../../presentation/cyrene/breakpoints.dart' show isDesktopLayout;
import '../../presentation/cyrene/cyrene_theme.dart';

/// 桌面外壳(融合标题栏 + fluent [NavigationView] 侧栏)统一的 fluent 主题。
///
/// 亮度与主色同步 Miuix:明暗切换、主题色变更会由上层 MiuixThemeController
/// 重建整树带动这里重算,每次读到的都是最新值。
///
/// **底色透明策略(Windows 11 窗口背景效果)**:由用户选择的窗口材质决定
/// (见 WindowMaterialSettingsStore)。fluent_ui 的 [Mica] 组件并非系统
/// 材质,只是一个用 `micaBackgroundColor` 填充的纯色 [DecoratedBox];
/// [NavigationView] 内部又用它包裹整片区域。若把这些背景色设为不透明的
/// surface 灰,系统 Mica/Acrylic 就被完全遮住。因此「云母/亚克力」材质下把
/// `micaBackgroundColor`/`scaffoldBackgroundColor`/`navigationPaneTheme`
/// 的背景统统设为透明,让 flutter_acrylic 通过 DWM 设置的窗口效果透出;
/// 内容区可读性由 [DesktopShell._buildBody] 里的半透明 [ColoredBox]
/// (surface 55% 不透明度) 保证,既维持可读性又让效果透过内容区。选择
/// 「默认不透明」时则用不透明 surface 底色,由 Flutter 侧自绘。
FluentThemeData desktopFluentTheme(BuildContext context) {
  final miuix = MiuixTheme.of(context);
  final isWindowsDesktop =
      !kIsWeb && Platform.isWindows && isDesktopLayout(context);
  // Windows 桌面端:仅「云母/亚克力」走透明(让 DWM 背景效果透出);
  // 「默认不透明」及非 Windows 平台(移动端/非 Windows,无窗口效果可透)
  // 仍用不透明 surface 灰,避免窗口透出桌面壁纸影响可读性。
  final translucent =
      isWindowsDesktop &&
      WindowMaterialSettingsStore.instance.material !=
          WindowMaterialType.opaque;
  final backdrop = translucent ? Colors.transparent : miuix.colors.surface;
  return FluentThemeData(
    brightness: miuix.brightness,
    accentColor: miuix.colors.primary.toAccentColor(),
    visualDensity: VisualDensity.standard,
    // fluent 自带一套 Typography(默认 Windows 平台字体),不指定就会让侧栏与
    // 标题栏的字形和用 MiSans 的其余部分不一致。
    fontFamily: cyreneFontFamily,
    scaffoldBackgroundColor: backdrop,
    micaBackgroundColor: backdrop,
    navigationPaneTheme: NavigationPaneThemeData(
      backgroundColor: backdrop,
      overlayBackgroundColor: miuix.colors.surface,
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
