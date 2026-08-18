import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'sonnet_random.dart';
import 'sonnet_types.dart';

const sonnetBackgroundDecorVariantCount = 6;

const List<String> sonnetBackgroundDecorVariants = [
  'scatter',
  'orbit',
  'edge-band',
  'corner-clusters',
  'constellation',
  'twin-columns',
];

int resolveSonnetBackgroundDecorVariant(int seed) =>
    mixSonnetSeed(seed, 0xc2b2ae35) % sonnetBackgroundDecorVariantCount;

const List<List<String>> _kShapePalettes = [
  ['square', 'diamond', 'sparkle'],
  ['ring', 'hexagon', 'dot'],
  ['bar', 'plus', 'square'],
  ['triangle', 'diamond', 'plus'],
  ['dot', 'ring', 'sparkle'],
  ['chevron', 'bar', 'hexagon'],
];

class SonnetParticleItem {
  const SonnetParticleItem({
    required this.shape,
    required this.size,
    required this.x,
    required this.y,
    required this.rotation,
    required this.color,
    required this.alpha,
  });

  final String shape;
  final double size;
  final double x;
  final double y;
  final double rotation;
  final Color color;
  final double alpha;
}

({double x, double y, double rotation}) _resolvePlacement(
  int variant,
  int index,
  int count,
  int seed,
  double width,
  double height,
) {
  final hw = width / 2.0;
  final hh = height / 2.0;
  final radius = math.min(width, height);
  double jitter(int salt, double range) =>
      (sonnetHash01(seed, index, salt) - 0.5) * range;
  final baseRotation = sonnetHash01(seed, index, 11) * math.pi * 2.0;

  switch (variant) {
    case 1: {
      final ring = index % 2;
      final ringRadius = radius * (0.36 + ring * 0.26);
      final angle = (index / count) * math.pi * 4.0 + jitter(13, 0.35);
      return (
        x: math.cos(angle) * ringRadius,
        y: math.sin(angle) * ringRadius * 0.86,
        rotation: angle + math.pi / 2.0,
      );
    }
    case 2: {
      final side = index % 2 == 0 ? -1.0 : 1.0;
      final t = ((index ~/ 2) + 0.5) / math.max(1, count ~/ 2);
      return (
        x: -hw + width * (0.06 + 0.88 * t) + jitter(17, width * 0.03),
        y: side * hh * 0.78 + jitter(19, height * 0.05),
        rotation: side < 0 ? 0.0 : math.pi,
      );
    }
    case 3: {
      final corner = index % 4;
      final sx = corner % 2 == 0 ? -1.0 : 1.0;
      final sy = corner < 2 ? -1.0 : 1.0;
      return (
        x: sx * hw * 0.68 + jitter(23, width * 0.12),
        y: sy * hh * 0.62 + jitter(29, height * 0.12),
        rotation: baseRotation,
      );
    }
    case 4: {
      const cols = 6;
      const rows = 4;
      final col = index % cols;
      final row = (index ~/ cols) % rows;
      return (
        x: -hw * 0.8 + (col / (cols - 1)) * hw * 1.6 + jitter(31, width * 0.06),
        y: -hh * 0.72 + (row / (rows - 1)) * hh * 1.44 + jitter(37, height * 0.06),
        rotation: baseRotation,
      );
    }
    case 5: {
      final side = index % 2 == 0 ? -1.0 : 1.0;
      final t = ((index ~/ 2) + 0.5) / math.max(1, (count / 2).ceil());
      return (
        x: side * hw * 0.74 + jitter(41, width * 0.04),
        y: -hh * 0.8 + t * hh * 1.6 + jitter(43, height * 0.05),
        rotation: side < 0 ? math.pi : 0.0,
      );
    }
    default:
      return (
        x: -hw + width * sonnetHash01(seed, index, 47),
        y: -hh + height * sonnetHash01(seed, index, 53),
        rotation: baseRotation,
      );
  }
}

void drawSonnetDecorShape(
  Canvas canvas,
  String shape,
  double pSize,
  Color color,
  double alpha,
) {
  final fillPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = color.withValues(alpha: alpha);
  final strokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.0, pSize * 0.18)
    ..color = color.withValues(alpha: alpha);

  switch (shape) {
    case 'diamond': {
      final path = Path()
        ..moveTo(0.0, -pSize)
        ..lineTo(pSize, 0.0)
        ..lineTo(0.0, pSize)
        ..lineTo(-pSize, 0.0)
        ..close();
      canvas.drawPath(
        path,
        fillPaint..color = color.withValues(alpha: (alpha * 0.85).clamp(0.0, 1.0)),
      );
      break;
    }
    case 'sparkle': {
      final path = Path()
        ..moveTo(0.0, -pSize * 1.5)
        ..quadraticBezierTo(0.0, 0.0, pSize * 1.5, 0.0)
        ..quadraticBezierTo(0.0, 0.0, 0.0, pSize * 1.5)
        ..quadraticBezierTo(0.0, 0.0, -pSize * 1.5, 0.0)
        ..quadraticBezierTo(0.0, 0.0, 0.0, -pSize * 1.5)
        ..close();
      canvas.drawPath(
        path,
        fillPaint..color = color.withValues(alpha: (alpha * 1.2).clamp(0.0, 1.0)),
      );
      break;
    }
    case 'plus': {
      final arm = pSize * 0.34;
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: pSize * 2.0, height: arm * 2.0),
        fillPaint..color = color.withValues(alpha: (alpha * 0.9).clamp(0.0, 1.0)),
      );
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: arm * 2.0, height: pSize * 2.0),
        fillPaint..color = color.withValues(alpha: (alpha * 0.9).clamp(0.0, 1.0)),
      );
      break;
    }
    case 'ring': {
      canvas.drawCircle(
        Offset.zero,
        pSize,
        strokePaint
          ..strokeWidth = math.max(1.0, pSize * 0.22)
          ..color = color.withValues(alpha: (alpha * 0.9).clamp(0.0, 1.0)),
      );
      break;
    }
    case 'triangle': {
      final path = Path()
        ..moveTo(0.0, -pSize)
        ..lineTo(pSize * 0.9, pSize * 0.7)
        ..lineTo(-pSize * 0.9, pSize * 0.7)
        ..close();
      canvas.drawPath(
        path,
        fillPaint..color = color.withValues(alpha: (alpha * 0.85).clamp(0.0, 1.0)),
      );
      break;
    }
    case 'hexagon': {
      final path = Path();
      for (var j = 0; j <= 6; j++) {
        final angle = (j * math.pi) / 3.0;
        final x = math.sin(angle) * pSize;
        final y = -math.cos(angle) * pSize;
        if (j == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        strokePaint
          ..strokeWidth = math.max(1.0, pSize * 0.16)
          ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0)),
      );
      break;
    }
    case 'bar': {
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: pSize * 2.0, height: pSize * 0.36),
        fillPaint..color = color.withValues(alpha: (alpha * 0.85).clamp(0.0, 1.0)),
      );
      break;
    }
    case 'dot': {
      canvas.drawCircle(Offset.zero, pSize * 0.34, fillPaint);
      break;
    }
    case 'chevron': {
      final path = Path()
        ..moveTo(-pSize * 0.5, -pSize * 0.55)
        ..lineTo(pSize * 0.35, 0.0)
        ..lineTo(-pSize * 0.5, pSize * 0.55);
      canvas.drawPath(
        path,
        strokePaint
          ..strokeWidth = math.max(1.5, pSize * 0.2)
          ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0)),
      );
      break;
    }
    default: {
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: pSize, height: pSize),
        fillPaint,
      );
    }
  }
}

List<SonnetParticleItem> buildSonnetBackgroundDecor({
  required SonnetShotKind kind,
  required double width,
  required double height,
  required int seed,
  required Color primary,
  required Color secondary,
}) {
  final variant = resolveSonnetBackgroundDecorVariant(seed);
  final palette = _kShapePalettes[variant];
  final particleCount = kind == SonnetShotKind.typeImpact ? 24 : 12;
  final particles = <SonnetParticleItem>[];

  for (var i = 0; i < particleCount; i++) {
    final pSize = (4 + (seed + i) % 12).toDouble();
    final shape = palette[(seed + i) % palette.length];
    final color = i % 2 == 0 ? primary : secondary;
    final alpha = 0.55 + sonnetHash01(seed, i, 59) * 0.3;
    final placement =
        _resolvePlacement(variant, i, particleCount, seed, width, height);

    particles.add(SonnetParticleItem(
      shape: shape,
      size: pSize,
      x: placement.x,
      y: placement.y,
      rotation: placement.rotation,
      color: color,
      alpha: alpha,
    ));
  }
  return particles;
}
