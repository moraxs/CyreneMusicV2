import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'sonnet_glyph_layout.dart';
import 'sonnet_motion.dart';
import 'sonnet_random.dart';
import 'sonnet_types.dart';
import 'sonnet_typography_layout.dart';

const sonnetFrameDecorProbability = 0.4;
const sonnetFrameDecorVariants = 4;

class SonnetFrameDecorSpec {
  const SonnetFrameDecorSpec({
    required this.applied,
    required this.variant,
  });

  final bool applied;
  final int variant;
}

SonnetFrameDecorSpec resolveSonnetFrameDecorSpec(
  SonnetSemanticSegment segment,
) {
  final hash = hashSonnetSeed([
    segment.text,
    segment.startOffset,
    segment.endOffset,
    'frame-decor',
  ].join(':'));
  return SonnetFrameDecorSpec(
    applied: (hash & 1023) / 1024.0 < sonnetFrameDecorProbability,
    variant: ((hash >> 10) & 0xFFFFFFFF) % sonnetFrameDecorVariants,
  );
}

double _hypot(double a, double b) => math.sqrt(a * a + b * b);

class SonnetFrameCorner {
  const SonnetFrameCorner({
    required this.x,
    required this.y,
    required this.sx,
    required this.sy,
  });
  final double x;
  final double y;
  final double sx;
  final double sy;
}

class SonnetFrameGeometry {
  SonnetFrameGeometry({
    required this.halfW,
    required this.halfH,
    required this.cornerGap,
    required this.pad,
  });
  final double halfW;
  final double halfH;
  final double cornerGap;
  final double pad;
}

List<SonnetFrameCorner> _resolveCorners(SonnetFrameGeometry geom) => [
      SonnetFrameCorner(x: -geom.halfW, y: -geom.halfH, sx: -1.0, sy: -1.0),
      SonnetFrameCorner(x: geom.halfW, y: -geom.halfH, sx: 1.0, sy: -1.0),
      SonnetFrameCorner(x: geom.halfW, y: geom.halfH, sx: 1.0, sy: 1.0),
      SonnetFrameCorner(x: -geom.halfW, y: geom.halfH, sx: -1.0, sy: 1.0),
    ];

({double startX, double startY, double endX, double endY}) _resolveSideEnds(
  SonnetFrameGeometry geom,
  List<SonnetFrameCorner> corners,
  int side,
) {
  final from = corners[side];
  final to = corners[(side + 1) % 4];
  final insetX = to.x == from.x ? 0.0 : geom.cornerGap * (to.x > from.x ? 1.0 : -1.0);
  final insetY = to.y == from.y ? 0.0 : geom.cornerGap * (to.y > from.y ? 1.0 : -1.0);
  return (
    startX: from.x + insetX,
    startY: from.y + insetY,
    endX: to.x - insetX,
    endY: to.y - insetY,
  );
}

({double width, double height}) resolveSonnetFrameLocalDimensions(
  SonnetTypographyPlacement placement,
) {
  final quarterTurns = (placement.rotation / (math.pi / 2.0)).round();
  final snappedRotation = quarterTurns * (math.pi / 2.0);
  final isOddQuarterTurn =
      (placement.rotation - snappedRotation).abs() < 1e-6 &&
          quarterTurns.abs() % 2 == 1;

  return isOddQuarterTurn
      ? (width: placement.measuredHeight, height: placement.measuredWidth)
      : (width: placement.measuredWidth, height: placement.measuredHeight);
}

class SonnetFrameDecorView {
  SonnetFrameDecorView({
    required this.placement,
    required this.startTime,
    required this.endTime,
    required this.variant,
    required this.color,
    required this.geometry,
    required this.corners,
    required this.strokeWidth,
  });

  final SonnetTypographyPlacement placement;
  final double startTime;
  final double endTime;
  final int variant;
  final Color color;
  final SonnetFrameGeometry geometry;
  final List<SonnetFrameCorner> corners;
  final double strokeWidth;

  void paint(Canvas canvas, double progress) {
    final eased = easeSonnetExpoOut(clamp01(progress));
    if (eased <= 0) return;

    canvas.save();
    canvas.translate(placement.x, placement.y);
    canvas.rotate(placement.rotation);

    final isDashed = variant == 3;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color.withValues(alpha: 0.85);

    // Trace sides
    for (var side = 0; side < 4; side++) {
      final sideProgress = clamp01((eased - side * 0.2) / 0.4);
      if (sideProgress <= 0) continue;
      final ends = _resolveSideEnds(geometry, corners, side);
      final tipX = ends.startX + (ends.endX - ends.startX) * sideProgress;
      final tipY = ends.startY + (ends.endY - ends.startY) * sideProgress;

      if (!isDashed) {
        canvas.drawLine(
          Offset(ends.startX, ends.startY),
          Offset(tipX, tipY),
          strokePaint,
        );
      } else {
        final sideLen = _hypot(
          ends.endX - ends.startX,
          ends.endY - ends.startY,
        );
        if (sideLen < 1.0) continue;
        final ux = (ends.endX - ends.startX) / sideLen;
        final uy = (ends.endY - ends.startY) / sideLen;
        final dash = (geometry.pad * 0.5).clamp(5.0, 8.0);
        final gap = dash * 0.7;
        final traced = sideLen * sideProgress;

        for (var offset = 0.0; offset + dash <= traced + 0.001; offset += dash + gap) {
          canvas.drawLine(
            Offset(ends.startX + ux * offset, ends.startY + uy * offset),
            Offset(ends.startX + ux * (offset + dash), ends.startY + uy * (offset + dash)),
            strokePaint,
          );
        }
      }
    }

    double ornamentProgress(double e, int cornerIdx) =>
        easeSonnetElasticOut(clamp01((e - 0.35 - cornerIdx * 0.14) / 0.3));

    if (variant == 0) {
      final arm = (geometry.pad * 0.8).clamp(5.0, 12.0);
      const offset = 3.0;
      for (var idx = 0; idx < corners.length; idx++) {
        final corner = corners[idx];
        final op = ornamentProgress(eased, idx);
        if (op <= 0.02) continue;
        final innerX = corner.x + corner.sx * offset;
        final innerY = corner.y + corner.sy * offset;

        final path = Path()
          ..moveTo(innerX + corner.sx * arm * op, innerY)
          ..lineTo(innerX, innerY)
          ..lineTo(innerX, innerY + corner.sy * arm * op);
        canvas.drawPath(
          path,
          strokePaint
            ..color = color.withValues(alpha: (0.9 * math.min(1.0, op)).clamp(0.0, 1.0)),
        );
      }
    } else if (variant == 1) {
      final radius = (geometry.pad * 0.55).clamp(4.0, 9.0);
      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.8);
      for (var idx = 0; idx < corners.length; idx++) {
        final corner = corners[idx];
        final op = ornamentProgress(eased, idx);
        if (op <= 0.02) continue;
        final petal = radius * 0.44 * op;
        canvas.drawCircle(Offset(corner.x - radius, corner.y), petal, fillPaint);
        canvas.drawCircle(Offset(corner.x + radius, corner.y), petal, fillPaint);
        canvas.drawCircle(Offset(corner.x, corner.y - radius), petal, fillPaint);
        canvas.drawCircle(Offset(corner.x, corner.y + radius), petal, fillPaint);
        canvas.drawCircle(
          Offset(corner.x, corner.y),
          radius * 0.3 * op,
          fillPaint..color = Colors.white.withValues(alpha: 0.5),
        );
      }
    } else if (variant == 2) {
      final arm = geometry.pad.clamp(6.0, 14.0);
      const offset = 2.5;
      for (var idx = 0; idx < corners.length; idx++) {
        final corner = corners[idx];
        final op = ornamentProgress(eased, idx);
        if (op <= 0.02) continue;
        final innerX = corner.x + corner.sx * offset;
        final innerY = corner.y + corner.sy * offset;

        final p1 = Path()
          ..moveTo(innerX + corner.sx * arm * op, innerY)
          ..lineTo(innerX, innerY)
          ..lineTo(innerX, innerY + corner.sy * arm * op);
        canvas.drawPath(
          p1,
          strokePaint
            ..strokeWidth = strokeWidth * 1.4
            ..color = color.withValues(alpha: 0.9),
        );

        final p2 = Path()
          ..moveTo(innerX + corner.sx * (arm * op + 4.0), innerY + corner.sy * 4.0)
          ..lineTo(innerX + corner.sx * 4.0, innerY + corner.sy * 4.0)
          ..lineTo(innerX + corner.sx * 4.0, innerY + corner.sy * (arm * op + 4.0));
        canvas.drawPath(
          p2,
          strokePaint
            ..strokeWidth = strokeWidth * 0.8
            ..color = color.withValues(alpha: 0.5),
        );
      }

      final diamond = (geometry.pad * 0.45).clamp(3.5, 7.0);
      for (var side = 0; side < 4; side++) {
        final op = ornamentProgress(eased, side);
        if (op <= 0.02) continue;
        final ends = _resolveSideEnds(geometry, corners, side);
        final midX = (ends.startX + ends.endX) / 2.0;
        final midY = (ends.startY + ends.endY) / 2.0;
        final size = diamond * op;

        final dPath = Path()
          ..moveTo(midX, midY - size)
          ..lineTo(midX + size, midY)
          ..lineTo(midX, midY + size)
          ..lineTo(midX - size, midY)
          ..close();
        canvas.drawPath(
          dPath,
          Paint()
            ..style = PaintingStyle.fill
            ..color = color.withValues(alpha: 0.85),
        );
      }
    } else {
      final size = (geometry.pad * 0.6).clamp(4.0, 9.0);
      const offset = 2.0;
      for (var idx = 0; idx < corners.length; idx++) {
        final corner = corners[idx];
        final op = ornamentProgress(eased, idx);
        if (op <= 0.02) continue;
        final diagX = corner.sx / math.sqrt2;
        final diagY = corner.sy / math.sqrt2;
        final perpX = corner.sy / math.sqrt2;
        final perpY = -corner.sx / math.sqrt2;
        final tipX = corner.x + diagX * (offset + size * op);
        final tipY = corner.y + diagY * (offset + size * op);
        final baseX = corner.x + diagX * offset;
        final baseY = corner.y + diagY * offset;
        final half = size * 0.7 * op;

        final triPath = Path()
          ..moveTo(tipX, tipY)
          ..lineTo(baseX + perpX * half, baseY + perpY * half)
          ..lineTo(baseX - perpX * half, baseY - perpY * half)
          ..close();
        canvas.drawPath(
          triPath,
          Paint()
            ..style = PaintingStyle.fill
            ..color = color.withValues(alpha: 0.85),
        );
        canvas.drawCircle(
          Offset(corner.x, corner.y),
          strokeWidth,
          Paint()
            ..style = PaintingStyle.fill
            ..color = color.withValues(alpha: 0.9),
        );
      }
    }

    canvas.restore();
  }
}

SonnetFrameDecorView? buildSonnetFrameDecor({
  required SonnetSemanticSegment segment,
  required SonnetTypographyPlacement placement,
  required Color primaryColor,
  required double fontSize,
  required double shotStartTime,
  required double shotEndTime,
  required double firstGlyphStartTime,
}) {
  if (placement.role == SonnetSegmentRole.decoration) return null;
  final spec = resolveSonnetFrameDecorSpec(segment);
  if (!spec.applied) return null;

  final pad = (fontSize * 0.22).clamp(8.0, 20.0);
  final dims = resolveSonnetFrameLocalDimensions(placement);
  final geometry = SonnetFrameGeometry(
    halfW: dims.width / 2.0 + pad,
    halfH: dims.height / 2.0 + pad,
    cornerGap: 0.0,
    pad: pad,
  );
  final gap = (math.min(geometry.halfW, geometry.halfH) *
          (spec.variant == 1 ? 0.42 : 0.3))
      .clamp(6.0, 30.0);

  final resolvedGeom = SonnetFrameGeometry(
    halfW: geometry.halfW,
    halfH: geometry.halfH,
    cornerGap: gap,
    pad: pad,
  );

  final color = primaryColor.withValues(alpha: 0.55);
  final corners = _resolveCorners(resolvedGeom);
  final strokeWidth = (fontSize * 0.03).clamp(1.2, 2.2);

  final growDuration =
      resolveSonnetGlyphMotionDuration(shotStartTime, shotEndTime) * 1.25;

  return SonnetFrameDecorView(
    placement: placement,
    startTime: firstGlyphStartTime,
    endTime: firstGlyphStartTime + growDuration,
    variant: spec.variant,
    color: color,
    geometry: resolvedGeom,
    corners: corners,
    strokeWidth: strokeWidth,
  );
}
