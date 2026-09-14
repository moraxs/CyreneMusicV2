import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// 推荐页的纸张、陶土与鼠尾草色。中性色仍来自 Miuix，暖色只作为局部氛围，
/// 不修改应用主题；深色模式使用独立的低亮度色阶，避免浅色卡片刺眼。
@immutable
class ForYouPalette {
  const ForYouPalette._({
    required this.background,
    required this.paper,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.peach,
    required this.rose,
    required this.sage,
    required this.sageAccent,
    required this.outline,
    required this.shadow,
  });

  factory ForYouPalette.of(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final dark = theme.brightness == Brightness.dark;
    Color tint(Color base, Color light, Color night, double amount) =>
        Color.lerp(base, dark ? night : light, amount)!;

    return ForYouPalette._(
      background: tint(
        colors.surface,
        const Color(0xFFF8F3ED),
        const Color(0xFF231E22),
        0.72,
      ),
      paper: tint(
        colors.surfaceContainer,
        const Color(0xFFFFFAF4),
        const Color(0xFF30282C),
        0.68,
      ),
      ink: colors.onSurfaceContainer,
      muted: Color.lerp(
        colors.onSurfaceVariantSummary,
        colors.onSurfaceContainer,
        0.14,
      )!,
      accent: tint(
        colors.primary,
        const Color(0xFFA15E4B),
        const Color(0xFFE7BAA5),
        0.86,
      ),
      onAccent: dark ? colors.surface : Colors.white,
      peach: tint(
        colors.surfaceContainer,
        const Color(0xFFF2DDCB),
        const Color(0xFF47342F),
        0.88,
      ),
      rose: tint(
        colors.surfaceContainer,
        const Color(0xFFF1DFDA),
        const Color(0xFF402D38),
        0.84,
      ),
      sage: tint(
        colors.surfaceContainer,
        const Color(0xFFE4EADF),
        const Color(0xFF2D3831),
        0.86,
      ),
      sageAccent: tint(
        colors.primary,
        const Color(0xFF4B6C59),
        const Color(0xFFBDD1B8),
        0.90,
      ),
      outline: colors.onSurfaceContainer.withValues(alpha: dark ? 0.09 : 0.055),
      shadow: Colors.black.withValues(alpha: dark ? 0.16 : 0.065),
    );
  }

  final Color background;
  final Color paper;
  final Color ink;
  final Color muted;
  final Color accent;
  final Color onAccent;
  final Color peach;
  final Color rose;
  final Color sage;
  final Color sageAccent;
  final Color outline;
  final Color shadow;
}
