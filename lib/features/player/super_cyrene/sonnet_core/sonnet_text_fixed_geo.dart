import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'sonnet_animated_graphics.dart';

enum SonnetTextFixedGeoCategory { hollow, solid }

class SonnetTextFixedGeoPlan {
  const SonnetTextFixedGeoPlan({
    required this.category,
    required this.variant,
  });

  final SonnetTextFixedGeoCategory category;
  final String variant;
}

const _kHollowVariants = [
  'straight-frame',
  'rotated-frame',
  'orbit-crosshair',
  'split-arches',
];

const _kSolidVariants = ['orb-hatch', 'music-steps', 'bent-lines'];

String _resolveHollowVariant(int seed, int divisor, int offset) {
  final index = (seed / divisor).floor() + offset;
  return _kHollowVariants[
      ((index % _kHollowVariants.length) + _kHollowVariants.length) %
          _kHollowVariants.length];
}

SonnetTextFixedGeoPlan resolveSonnetTextFixedGeoPlan(
  int seed,
  bool isChorusEffect,
) {
  if (isChorusEffect) {
    final chorusSeed = ((seed % 10) + 10) % 10;
    if (chorusSeed < 9) {
      return SonnetTextFixedGeoPlan(
        category: SonnetTextFixedGeoCategory.hollow,
        variant: _resolveHollowVariant(seed, 10, chorusSeed),
      );
    }
    return SonnetTextFixedGeoPlan(
      category: SonnetTextFixedGeoCategory.solid,
      variant: _kSolidVariants[(seed / 10).floor() % _kSolidVariants.length],
    );
  }

  final legacyType = ((seed % 4) + 4) % 4;
  if (legacyType == 1 || legacyType == 2) {
    return SonnetTextFixedGeoPlan(
      category: SonnetTextFixedGeoCategory.hollow,
      variant: _resolveHollowVariant(seed, 4, legacyType),
    );
  }
  return SonnetTextFixedGeoPlan(
    category: SonnetTextFixedGeoCategory.solid,
    variant: _kSolidVariants[(seed / 4).floor() % _kSolidVariants.length],
  );
}

class SonnetTextFixedGeoOptions {
  const SonnetTextFixedGeoOptions({
    required this.seed,
    required this.isChorusEffect,
    required this.fontSize,
    required this.layoutWidth,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
  });

  final int seed;
  final bool isChorusEffect;
  final double fontSize;
  final double layoutWidth;
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
}

void _drawMusicSteps(
  AnimatedGraphics graphic,
  double width,
  double height,
  double alpha,
  Color accentColor,
  Color secondaryColor,
) {
  const heights = [0.24, 0.35, 0.2, 0.82, 0.3, 0.1, 0.23, 0.16];
  final spacing = width / (heights.length + 1);
  for (var index = 0; index < heights.length; index++) {
    final heightRatio = heights[index];
    final x = -width / 2.0 + spacing * (index + 1);
    final baseline = height * (0.12 - index * 0.035);
    final color = index % 2 == 0 ? accentColor : secondaryColor;
    graphic
        .moveTo(x - spacing * 0.12, baseline - height * heightRatio * 0.5)
        .lineTo(x + spacing * 0.12, baseline + height * heightRatio * 0.5)
        .stroke(
          color: color,
          width: math.max(2.0, height * 0.025),
          alpha: alpha * 0.52,
        );
  }
}

void _drawBentLines(
  AnimatedGraphics graphic,
  double width,
  double height,
  double alpha,
  Color accentColor,
  Color secondaryColor,
) {
  const lineCount = 5;
  for (var index = 0; index < lineCount; index++) {
    final x = -width * 0.34 + index * width * 0.17;
    final topY = -height * (0.42 - index * 0.035);
    final elbowY = -height * (0.08 - index * 0.025);
    final bottomY = height * (0.35 + index * 0.035);
    final color = index % 2 == 0 ? accentColor : secondaryColor;
    graphic
        .moveTo(x - width * 0.16, topY)
        .lineTo(x, elbowY)
        .lineTo(x - width * 0.015, bottomY)
        .stroke(
          color: color,
          width: math.max(2.0, height * 0.022),
          alpha: alpha * 0.52,
        );
  }
}

void _drawOrbitCrosshair(
  AnimatedGraphics graphic,
  double width,
  double height,
  double alpha,
  Color color,
  Color secondaryColor,
) {
  final radius = math.min(width, height) * 0.46;
  graphic.circle(0.0, 0.0, radius).stroke(color: color, width: 1.5, alpha: alpha);
  graphic
      .circle(-width * 0.17, 0.0, radius * 0.72)
      .stroke(color: secondaryColor, width: 1.0, alpha: alpha * 0.72);
  graphic
      .circle(width * 0.17, 0.0, radius * 0.72)
      .stroke(color: secondaryColor, width: 1.0, alpha: alpha * 0.72);
  graphic
      .moveTo(-width * 0.62, 0.0)
      .lineTo(width * 0.62, 0.0)
      .stroke(color: color, width: 1.0, alpha: alpha * 0.64);
  graphic
      .moveTo(0.0, -height * 0.62)
      .lineTo(0.0, height * 0.62)
      .stroke(color: color, width: 1.0, alpha: alpha * 0.64);
}

void _drawSplitArches(
  AnimatedGraphics graphic,
  double width,
  double height,
  double alpha,
  Color color,
  Color secondaryColor,
) {
  final halfWidth = width * 0.46;
  final archRadius = math.min(width * 0.34, height * 0.52);
  final directions = [-1.0, 1.0];

  for (var index = 0; index < directions.length; index++) {
    final direction = directions[index];
    final x = direction * halfWidth * 0.42;
    graphic
        .moveTo(x - archRadius * 0.72, height * 0.42)
        .lineTo(x - archRadius * 0.72, 0.0)
        .arc(x, 0.0, archRadius * 0.72, math.pi, 0.0)
        .lineTo(x + archRadius * 0.72, height * 0.42)
        .stroke(
          color: index == 0 ? color : secondaryColor,
          width: 1.5,
          alpha: alpha,
        );

    graphic
        .moveTo(x - archRadius * 0.48, height * 0.42)
        .lineTo(x - archRadius * 0.48, 0.0)
        .arc(x, 0.0, archRadius * 0.48, math.pi, 0.0)
        .lineTo(x + archRadius * 0.48, height * 0.42)
        .stroke(
          color: index == 0 ? secondaryColor : color,
          width: 1.0,
          alpha: alpha * 0.58,
        );
  }
  graphic
      .moveTo(-halfWidth, height * 0.42)
      .lineTo(halfWidth, height * 0.42)
      .stroke(color: color, width: 2.0, alpha: alpha * 0.72);
}

AnimatedGraphics buildSonnetTextFixedGeo(SonnetTextFixedGeoOptions options) {
  final seed = options.seed;
  final isChorusEffect = options.isChorusEffect;
  final fontSize = options.fontSize;
  final layoutWidth = options.layoutWidth;
  final primaryColor = options.primaryColor;
  final secondaryColor = options.secondaryColor;
  final accentColor = options.accentColor;

  final plan = resolveSonnetTextFixedGeoPlan(seed, isChorusEffect);
  final graphic = AnimatedGraphics();
  final color = seed % 2 == 0 ? primaryColor : secondaryColor;
  final alpha = (isChorusEffect ? 0.4 : 0.25) + (seed % 10) * 0.03;
  final scaleMultiplier = isChorusEffect ? 1.5 + (seed % 5) * 0.3 : 1.0;
  final width = math.max(
    fontSize * 2.5 * scaleMultiplier,
    layoutWidth * 0.12 * scaleMultiplier,
  );
  final height = math.max(
    fontSize * 1.8 * scaleMultiplier,
    layoutWidth * 0.08 * scaleMultiplier,
  );

  if (plan.category == SonnetTextFixedGeoCategory.hollow) {
    if (plan.variant == 'orbit-crosshair') {
      _drawOrbitCrosshair(graphic, width, height, alpha, color, secondaryColor);
      return graphic;
    }
    if (plan.variant == 'split-arches') {
      _drawSplitArches(graphic, width, height, alpha, color, secondaryColor);
      return graphic;
    }
    final frameWidth = plan.variant == 'rotated-frame' ? width * 0.8 : width;
    final frameHeight = plan.variant == 'rotated-frame' ? height * 0.8 : height;
    graphic.rect(
      -frameWidth / 2.0,
      -frameHeight / 2.0,
      frameWidth,
      frameHeight,
    ).stroke(
      color: color,
      width: math.max(1.5, fontSize * 0.02),
      alpha: alpha,
    );

    if (isChorusEffect && seed % 2 == 0) {
      graphic.rect(
        -frameWidth * 0.6,
        -frameHeight * 0.6,
        frameWidth * 1.2,
        frameHeight * 1.2,
      ).stroke(
        color: color,
        width: 1.0,
        alpha: alpha * 0.5,
      );
    }
    return graphic;
  }

  if (plan.variant == 'music-steps') {
    _drawMusicSteps(graphic, width, height, alpha, accentColor, secondaryColor);
    return graphic;
  }
  if (plan.variant == 'bent-lines') {
    _drawBentLines(graphic, width, height, alpha, accentColor, secondaryColor);
    return graphic;
  }

  final radius = width * 0.5;
  graphic.circle(0.0, 0.0, radius).fill(color: color, alpha: alpha * 0.15);
  final hatchSpacing = math.max(4.0, width * 0.05);
  for (var offset = -radius; offset < radius; offset += hatchSpacing) {
    final lineHeight =
        math.sqrt(math.max(0.0, radius * radius - offset * offset));
    graphic
        .moveTo(offset + radius * 0.4, -lineHeight + radius * 0.4)
        .lineTo(offset + radius * 0.4, lineHeight + radius * 0.4);
  }
  graphic.stroke(color: color, width: 1.5, alpha: alpha * 0.6);
  return graphic;
}
