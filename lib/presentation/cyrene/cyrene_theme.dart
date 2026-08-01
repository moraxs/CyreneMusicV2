import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// 全应用统一字体族：MiSans（小米 HyperOS 系统字体，assets/MiSans-Normal.ttf，
/// 在 pubspec.yaml 的 fonts: 段声明）。
///
/// 为什么要显式设：Flutter 不设 fontFamily 时用各平台默认字体（Windows 是
/// Segoe UI，安卓是 Roboto/系统中文字体），同一份 TextStyle 在桌面与移动端
/// 落到不同字形，粗细观感也不同。统一指到 MiSans 后各页面字形一致。
///
/// 注意该 ttf 只有 Normal 一个字重，w500/w600/bold 由引擎合成加粗。
const String cyreneFontFamily = 'MiSans';

/// 从 Miuix 主题派生 Material [ThemeData]。
///
/// 应用整体走 flutter_miuix 组件与 [MiuixTheme]；这里只桥接仍依赖 Material
/// 基础设施的部分（Scaffold 背景、页面转场、残留的 Material 控件配色）。
abstract final class CyreneMiuixTheme {
  static ThemeData material(MiuixThemeData miuix) {
    final colors = miuix.colors;
    return ThemeData(
      useMaterial3: true,
      brightness: miuix.brightness,
      // Material 侧的兜底字体：Material 控件与裸 Text 都从 textTheme 取样式，
      // 不设这里会继续吃平台默认字体。
      fontFamily: cyreneFontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: colors.primary,
        brightness: miuix.brightness,
      ),
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      splashFactory: NoSplash.splashFactory,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colors.onBackground,
        titleTextStyle: miuix.textStyles.title4.copyWith(
          color: colors.onBackground,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Miuix 的 14 个文本预设，全部打上 [cyreneFontFamily]。
  ///
  /// 库的 [defaultTextStyles] 只带字号/字重，不带字体族——Miuix 组件
  /// （MiuixText / 顶栏 / rail 标签 / 按钮…）因此都吃平台默认字体。把它整份
  /// apply 一遍字体族后传给 [MiuixThemeController.textStyles]，Miuix 与
  /// Material 两侧字形才真正统一。
  ///
  /// 字号/字重一个不动：只加字体族，不改 HyperOS 排版规范。
  static MiuixTextStyles textStyles() {
    final base = defaultTextStyles();
    TextStyle withFamily(TextStyle style) =>
        style.apply(fontFamily: cyreneFontFamily);
    return base.copy(
      main: withFamily(base.main),
      paragraph: withFamily(base.paragraph),
      body1: withFamily(base.body1),
      body2: withFamily(base.body2),
      button: withFamily(base.button),
      footnote1: withFamily(base.footnote1),
      footnote2: withFamily(base.footnote2),
      headline1: withFamily(base.headline1),
      headline2: withFamily(base.headline2),
      subtitle: withFamily(base.subtitle),
      title1: withFamily(base.title1),
      title2: withFamily(base.title2),
      title3: withFamily(base.title3),
      title4: withFamily(base.title4),
    );
  }
}
