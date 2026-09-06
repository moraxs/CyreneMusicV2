import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// folia「莫奈」可视化用的四个语义色。
///
/// 上游（`src/components/visualizer/monet/*`）读的是主题对象里的
/// `primaryColor` / `secondaryColor` / `accentColor` / `backgroundColor`，
/// 每个色位的语义都被大量硬编码的 alpha 依赖（歌词暗态 0.34、标题投影 0.28、
/// 封面外发光 0.22 ……）。本项目没有「歌词主题」这一层，只有封面提出来的一个
/// 主题色，所以这里把那一个色拆成上游需要的四个色位，让所有 alpha 常量可以
/// 原样照搬。
///
/// - [background]：封面主题色压暗后的底色，只用于各种遮罩/veil，不铺满全屏
///   （全屏底色仍归 `MobilePlayerBackground` 管）。
/// - [accent]：封面主题色本身，提饱和后用于泛光与逐字点亮的暖色。
/// - [primary]：正文色。播放器恒为深色底，因此是掺了一点 accent 的近白。
/// - [secondary]：副文本 / 飘落装饰色，介于 primary 与 accent 之间。
@immutable
class MonetPalette {
  const MonetPalette({
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.background,
  });

  /// 没有封面主题色时的兜底（冷灰蓝，与播放器默认底色同调）。
  factory MonetPalette.fromThemeColor(Color? themeColor) {
    if (themeColor == null) return fallback;

    final hsl = HSLColor.fromColor(themeColor);
    final accent = hsl
        .withSaturation(_clamp(hsl.saturation * 1.12, .26, .92))
        .withLightness(_clamp(hsl.lightness, .42, .70))
        .toColor();
    final background = hsl
        .withSaturation(_clamp(hsl.saturation * .82, 0, .70))
        .withLightness(_clamp(hsl.lightness * .30, .045, .17))
        .toColor();
    final primary = Color.lerp(const Color(0xFFFFFFFF), accent, .07)!;

    return MonetPalette(
      primary: primary,
      secondary: Color.lerp(primary, accent, .34)!,
      accent: accent,
      background: background,
    );
  }

  static const fallback = MonetPalette(
    primary: Color(0xFFF6F4F8),
    secondary: Color(0xFFD2CCDD),
    accent: Color(0xFF8FA7D8),
    background: Color(0xFF14131A),
  );

  final Color primary;
  final Color secondary;
  final Color accent;
  final Color background;

  @override
  bool operator ==(Object other) =>
      other is MonetPalette &&
      other.primary == primary &&
      other.secondary == secondary &&
      other.accent == accent &&
      other.background == background;

  @override
  int get hashCode => Object.hash(primary, secondary, accent, background);
}

/// 上游 `colorWithAlpha` 的等价物：只换 alpha，不动色相。
Color monetAlpha(Color color, double alpha) =>
    color.withValues(alpha: _clamp(alpha, 0, 1));

/// 上游 `mixColors(from, to, amount)`。
Color monetMix(Color from, Color to, double amount) =>
    Color.lerp(from, to, _clamp(amount, 0, 1))!;

double _clamp(double value, double min, double max) =>
    math.min(max, math.max(min, value));
