/// 把 `styles/index.css` 与 `styles/lyric-player.module.css` 里的每一条尺寸
/// 规则翻成 px。这是「1:1 逐像素」的唯一真相来源——排版与绘制都只读这里，
/// 不允许在别处写魔数。
///
/// 单位换算约定：
/// - `vw` / `vh` 是**视口**单位，取整个窗口的宽高（和浏览器一致），
///   不是歌词组件自身的尺寸；
/// - 百分比（如 `padding: 2.5% 0.75em` 的 2.5%）按 CSS 规范取**包含块的宽度**，
///   也就是歌词组件的宽度；
/// - `em` 取当前元素自身的 `font-size`（背景人声行的 em 比主行小）。
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// `.amll-lyric-player.dom` 上的自定义属性默认值。
const double kBgLineScale = 0.7; // --amll-lp-bg-line-scale
const double kLineHeightEm = 1.2; // .dom { line-height: 1.2em }
const double kSubLineHeightEm = 1.5; // .lyricSubLine { line-height: 1.5em }

class V2CssMetrics {
  V2CssMetrics({
    required this.playerSize,
    required this.windowSize,
    required this.hasDuetLine,
    double? fontSizeOverride,
    this.fontFamily,
    this.color = const Color(0xFFFFFFFF),
    this.fontWeight = FontWeight.w700,
  }) : fontSize = fontSizeOverride ?? _resolveFontSize(windowSize);

  /// 歌词组件自身的尺寸（`this.size`）
  final Size playerSize;

  /// 窗口尺寸，供 `vw` / `vh` 与媒体查询使用
  final Size windowSize;

  /// `.hasDuetLine` 是否挂在了根节点上
  final bool hasDuetLine;

  /// 解析后的 `--amll-lp-font-size`
  final double fontSize;

  final String? fontFamily;

  /// `--amll-lp-color`，默认 white
  final Color color;

  /// 上游样式表没有设 font-weight，实际粗体来自宿主页面。
  /// 保留为参数，默认沿用项目其余歌词视图的 w700。
  final FontWeight fontWeight;

  /// `font-size: var(--amll-lp-font-size, max(max(5vh, 2.5vw), 12px))`
  /// `@media (max-width: 768px)` → `max(8vw, 12px)`
  static double _resolveFontSize(Size window) {
    final vw = window.width / 100;
    final vh = window.height / 100;
    if (window.width <= 768) return math.max(8 * vw, 12);
    return math.max(math.max(5 * vh, 2.5 * vw), 12);
  }

  double get vw => windowSize.width / 100;
  double get vh => windowSize.height / 100;

  /// `.dom { line-height: 1.2em }`
  double get lineHeight => kLineHeightEm * fontSize;

  /// `.lyricBgLine { font-size: max(calc(1em * 0.7), 10px) }`
  double get bgFontSize => math.max(fontSize * kBgLineScale, 10);

  /// 某一行自己的 font-size
  double lineFontSize(bool isBG) => isBG ? bgFontSize : fontSize;

  /// 某一行主歌词的行高
  double lineTextHeight(bool isBG) => kLineHeightEm * lineFontSize(isBG);

  /// `.lyricSubLine { font-size: max(0.5em, 10px) }`
  double subFontSize(bool isBG) => math.max(0.5 * lineFontSize(isBG), 10);

  /// `.lyricSubLine { line-height: 1.5em }`（em 取副行自己的 font-size）
  double subLineHeight(bool isBG) => kSubLineHeightEm * subFontSize(isBG);

  /// `.lyricMainLine .romanWord { font-size: 0.5em; line-height: 1em }`
  double romanWordFontSize(bool isBG) => 0.5 * lineFontSize(isBG);
  double romanWordHeight(bool isBG) => romanWordFontSize(isBG);

  /// `.lyricLine { padding: 0.5em 1em }`，主行纵向内边距。
  /// 背景行被 `.lyricBgLine { padding: 1vh ... }` 覆盖。
  double linePaddingTop(bool isBG) => isBG ? 1 * vh : 0.5 * fontSize;
  double linePaddingBottom(bool isBG) => linePaddingTop(isBG);

  /// 主行横向内边距：`padding-left/right: 1em`，
  /// `@media (max-width: 500px)` → `20px`。
  ///
  /// 背景行走 `.lyricBgLine` 的
  /// `calc(var(--amll-lp-line-padding-x, 1em) / var(--amll-lp-bg-line-scale, 0.7))`：
  /// `--amll-lp-line-padding-x` 在 `.dom` 上是 `1em`（此处 em = 背景行字号），
  /// 除以 0.7 后正好等于主行字号；`@media (max-width: 768px)` 把该变量改成 0。
  double linePaddingX(bool isBG) {
    if (isBG) {
      if (windowSize.width <= 768) return 0;
      return (bgFontSize * 1) / kBgLineScale;
    }
    if (windowSize.width <= 500) return 20;
    return fontSize;
  }

  /// `.hasDuetLine .lyricLine:not(.lyricDuetLine) { padding-right: 15% }`
  /// `.hasDuetLine .lyricDuetLine { padding-left: 15% }`
  double duetExtraPadding(bool isDuet) =>
      hasDuetLine ? playerSize.width * 0.15 : 0;

  double linePaddingLeft(bool isBG, bool isDuet) =>
      isDuet ? duetExtraPadding(true) : linePaddingX(isBG);

  double linePaddingRight(bool isBG, bool isDuet) =>
      isDuet ? linePaddingX(isBG) : duetExtraPadding(false);

  /// `.lyricLine { border-radius: 0.25em }`
  double get lineBorderRadius => 0.25 * fontSize;

  /// `.lyricMainLine > span { padding: 1em; margin: -1em }`。
  /// 内外边距互相抵消，不影响排版，但决定遮罩渐变的坐标系。
  double wordPadding(bool isBG) => lineFontSize(isBG);

  /// `.interludeDots { height: clamp(0.5em, 1vh, 3em) }`，圆点同尺寸
  double get interludeDotSize =>
      (1 * vh).clamp(0.5 * fontSize, 3 * fontSize).toDouble();

  /// `.interludeDots { padding: 2.5% 0.75em }`，纵向百分比按包含块宽度算
  double get interludeDotsPaddingY => playerSize.width * 0.025;
  double get interludeDotsPaddingX => 0.75 * fontSize;

  /// `.interludeDots { gap: 0.25em }`
  double get interludeDotsGap => 0.25 * fontSize;

  /// `.interludeDots > * { margin-right: 4px }`
  static const double interludeDotMarginRight = 4;

  Size get interludeDotsSize => Size(
    interludeDotsPaddingX * 2 +
        interludeDotSize * 3 +
        interludeDotsGap * 2 +
        interludeDotMarginRight * 3,
    interludeDotsPaddingY * 2 + interludeDotSize,
  );

  TextStyle mainTextStyle(bool isBG) => TextStyle(
    fontFamily: fontFamily,
    fontSize: lineFontSize(isBG),
    fontWeight: fontWeight,
    height: kLineHeightEm,
    color: color,
  );

  TextStyle subTextStyle(bool isBG) => TextStyle(
    fontFamily: fontFamily,
    fontSize: subFontSize(isBG),
    fontWeight: fontWeight,
    height: kSubLineHeightEm,
    color: color,
  );

  TextStyle romanWordTextStyle(bool isBG) => TextStyle(
    fontFamily: fontFamily,
    fontSize: romanWordFontSize(isBG),
    fontWeight: fontWeight,
    height: 1,
    color: color,
  );

  /// 布局是否需要重算：只要这些量变了，所有行的尺寸都会变。
  bool sameLayoutInputsAs(V2CssMetrics? other) =>
      other != null &&
      other.playerSize == playerSize &&
      other.windowSize == windowSize &&
      other.hasDuetLine == hasDuetLine &&
      other.fontSize == fontSize &&
      other.fontFamily == fontFamily &&
      other.fontWeight == fontWeight;
}
