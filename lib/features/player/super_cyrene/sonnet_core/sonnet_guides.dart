import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'sonnet_types.dart';
import 'sonnet_typography_layout.dart';
import 'sonnet_typography_roles.dart';

class SonnetGuideTrail {
  SonnetGuideTrail({
    required this.p0,
    required this.p1,
    required this.p2,
    required this.p3,
    required this.delay,
  });

  final Offset p0;
  final Offset p1;
  final Offset p2;
  final Offset p3;
  final double delay;
}

class SonnetRectSpline {
  SonnetRectSpline({
    required this.p0,
    required this.p1,
    required this.thickness,
    required this.delay,
    required this.duration,
  });

  final Offset p0;
  final Offset p1;
  final double thickness;
  final double delay;
  final double duration;
}

class SonnetBurstShape {
  SonnetBurstShape({
    required this.type,
    required this.size,
    required this.angle,
    required this.speed,
    required this.rotSpeed,
  });

  final int type;
  final double size;
  final double angle;
  final double speed;
  final double rotSpeed;
}

({double startTime, double endTime}) resolveSonnetGuideCue(
  SonnetSemanticSegment segment, [
  double? textStartTime,
]) {
  final start = textStartTime ?? segment.startTime;
  final leadDuration = math.min(
    0.38,
    math.max(0.2, 0.18 + (segment.endTime - segment.startTime) * 0.1),
  );
  return (
    startTime: start - leadDuration,
    endTime: start + 0.65,
  );
}

class SonnetGuideView {
  SonnetGuideView({
    required this.placement,
    required this.startTime,
    required this.endTime,
    required this.maxAlpha,
    required this.isHero,
    required this.color,
    required this.p0,
    required this.p1,
    required this.p2,
    required this.p3,
    required this.burstShapes,
    required this.trackingTrails,
    this.rectSpline,
  });

  final SonnetTypographyPlacement placement;
  final double startTime;
  final double endTime;
  final double maxAlpha;
  final bool isHero;
  final Color color;
  final Offset p0;
  final Offset p1;
  final Offset p2;
  final Offset p3;
  final List<SonnetBurstShape> burstShapes;
  final List<SonnetGuideTrail> trackingTrails;
  final SonnetRectSpline? rectSpline;

  static Offset _bezier(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final mt = 1.0 - t;
    return Offset(
      mt * mt * mt * p0.dx +
          3.0 * mt * mt * t * p1.dx +
          3.0 * mt * t * t * p2.dx +
          t * t * t * p3.dx,
      mt * mt * mt * p0.dy +
          3.0 * mt * mt * t * p1.dy +
          3.0 * mt * t * t * p2.dy +
          t * t * t * p3.dy,
    );
  }

  void paint(Canvas canvas, double progress) {
    final drawProgress = (progress / 0.35).clamp(0.0, 1.0);
    final fadeOut = (1.0 - ((progress - 0.4) / 0.3).clamp(0.0, 1.0)).clamp(0.0, 1.0);

    canvas.save();
    canvas.translate(placement.x, placement.y);

    if (drawProgress > 0 && fadeOut > 0) {
      const steps = 20;
      var prevP = p0;
      for (var i = 1; i <= steps; i++) {
        final t = (i / steps) * drawProgress;
        final p = _bezier(p0, p1, p2, p3, t);
        final intensity = math.pow(i / steps, 2.0).toDouble();
        final segAlpha = math.min(
          1.0,
          intensity * (isHero ? 0.82 : 0.55) * fadeOut * 1.6,
        );
        final segWidth =
            (isHero ? 2.5 : 1.5) + intensity * (isHero ? 5.0 : 3.0);

        canvas.drawLine(
          prevP,
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = segWidth
            ..color = color.withValues(alpha: segAlpha),
        );
        prevP = p;
      }

      final head = _bezier(p0, p1, p2, p3, drawProgress);
      canvas.drawCircle(
        head,
        isHero ? 14.0 : 9.0,
        Paint()
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: (0.5 * fadeOut).clamp(0.0, 1.0)),
      );
      canvas.drawCircle(
        head,
        isHero ? 4.5 : 3.0,
        Paint()
          ..style = PaintingStyle.fill
          ..color = Colors.white.withValues(alpha: fadeOut),
      );
    }

    for (final trail in trackingTrails) {
      final localProg = (progress - trail.delay) / 0.55;
      if (localProg > -0.15 && fadeOut > 0) {
        if (localProg > 0 && localProg < 1.3) {
          final headT = math.min(1.0, localProg);
          final tailT = math.max(0.0, localProg - 0.35);

          if (headT > tailT) {
            const steps = 25;
            var prevP = _bezier(trail.p0, trail.p1, trail.p2, trail.p3, tailT);

            for (var i = 1; i <= steps; i++) {
              final stepT = tailT + (i / steps) * (headT - tailT);
              final pos = _bezier(trail.p0, trail.p1, trail.p2, trail.p3, stepT);
              final intensity = math.pow(i / steps, 2.0).toDouble();
              final alpha = (intensity * (isHero ? 0.82 : 0.55) * fadeOut * 0.9)
                  .clamp(0.0, 1.0);
              final width =
                  (isHero ? 2.0 : 1.0) + intensity * (isHero ? 5.0 : 2.5);

              canvas.drawLine(
                prevP,
                pos,
                Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = width
                  ..color = color.withValues(alpha: alpha),
              );
              prevP = pos;
            }
          }

          if (headT > 0 && headT < 1.0) {
            final headPos =
                _bezier(trail.p0, trail.p1, trail.p2, trail.p3, headT);
            canvas.drawCircle(
              headPos,
              isHero ? 7.0 : 4.0,
              Paint()
                ..style = PaintingStyle.fill
                ..color =
                    color.withValues(alpha: (0.9 * fadeOut).clamp(0.0, 1.0)),
            );
            canvas.drawCircle(
              headPos,
              isHero ? 2.5 : 1.5,
              Paint()
                ..style = PaintingStyle.fill
                ..color = Colors.white
                    .withValues(alpha: fadeOut.clamp(0.0, 1.0)),
            );
            canvas.drawCircle(
              headPos,
              isHero ? 20.0 : 12.0,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = isHero ? 2.0 : 1.0
                ..color =
                    color.withValues(alpha: (0.4 * fadeOut).clamp(0.0, 1.0)),
            );
          }
        }
      }
    }

    if (rectSpline != null) {
      final r = rectSpline!;
      final localProg = (progress - r.delay) / r.duration;
      if (localProg > 0 && localProg < 1.3 && fadeOut > 0) {
        final headT = (localProg * 1.5).clamp(0.0, 1.0);
        final tailT = ((localProg - 0.3) * 1.5).clamp(0.0, 1.0);

        if (headT > tailT) {
          final hx = r.p0.dx + (r.p1.dx - r.p0.dx) * headT;
          final hy = r.p0.dy + (r.p1.dy - r.p0.dy) * headT;
          final tx = r.p0.dx + (r.p1.dx - r.p0.dx) * tailT;
          final ty = r.p0.dy + (r.p1.dy - r.p0.dy) * tailT;

          canvas.drawLine(
            Offset(tx, ty),
            Offset(hx, hy),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = r.thickness
              ..color = color.withValues(
                alpha: ((isHero ? 0.82 : 0.55) * fadeOut * 0.7)
                    .clamp(0.0, 1.0),
              ),
          );
          canvas.drawLine(
            Offset(tx, ty),
            Offset(hx, hy),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = r.thickness * 0.3
              ..color = Colors.white
                  .withValues(alpha: (fadeOut * 0.9).clamp(0.0, 1.0)),
          );
        }
      }
    }

    final burstProgress = ((progress - 0.3) / 0.7).clamp(0.0, 1.0);
    for (final s in burstShapes) {
      final ease = 1.0 - math.pow(1.0 - burstProgress, 3.0);
      final sx = p3.dx + math.cos(s.angle) * s.speed * ease;
      final sy = p3.dy + math.sin(s.angle) * s.speed * ease;
      final sAlpha = ((1.0 - burstProgress) * (isHero ? 1.0 : 0.8))
          .clamp(0.0, 1.0);
      final scale = 1.0 - burstProgress * 0.4;
      final size = s.size * scale;

      canvas.save();
      canvas.translate(sx, sy);
      canvas.rotate(s.rotSpeed * burstProgress);

      final shapePaint = Paint()
        ..color = color.withValues(alpha: sAlpha);

      if (s.type == 0) {
        canvas.drawCircle(Offset.zero, size, shapePaint);
      } else if (s.type == 1) {
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: size * 2, height: size * 2),
          shapePaint,
        );
      } else if (s.type == 2) {
        canvas.drawLine(
          Offset(-size, 0),
          Offset(size, 0),
          shapePaint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        canvas.drawLine(
          Offset(0, -size),
          Offset(0, size),
          shapePaint,
        );
      } else {
        final path = Path()
          ..moveTo(0, -size)
          ..lineTo(size, 0)
          ..lineTo(0, size)
          ..lineTo(-size, 0)
          ..close();
        canvas.drawPath(path, shapePaint);
      }
      canvas.restore();
    }

    canvas.restore();
  }
}

SonnetGuideView createSonnetGuide({
  required SonnetSemanticSegment segment,
  required SonnetTypographyPlacement placement,
  required Color accentColor,
  required Color secondaryColor,
  required double fontSize,
  double? textStartTime,
}) {
  final isHero = isSonnetEmphasisRole(placement.role);
  final fallbackDir = placement.timingPhase < 0.5 ? -1.0 : 1.0;
  final startX = placement.enterX != 0.0
      ? placement.enterX
      : fallbackDir * fontSize * 1.8;
  final startY =
      placement.enterY != 0.0 ? placement.enterY : -fontSize * 0.9;
  final color = isHero ? accentColor : secondaryColor;

  final p0 = Offset(startX, startY);
  final p1 = Offset(startX * 0.6, startY * 0.4);
  final p2 = Offset(startX * 0.2, startY * 0.1);
  const p3 = Offset.zero;

  final numShapes = isHero ? 6 : 3;
  final burstShapes = <SonnetBurstShape>[];
  final rng = math.Random(segment.text.hashCode);

  for (var i = 0; i < numShapes; i++) {
    burstShapes.add(SonnetBurstShape(
      type: rng.nextInt(4),
      size: (isHero ? 3.0 : 1.5) + rng.nextDouble() * 3.5,
      angle: rng.nextDouble() * math.pi * 2.0,
      speed: (15.0 + rng.nextDouble() * 45.0) * (isHero ? 1.0 : 0.7),
      rotSpeed: (rng.nextDouble() - 0.5) * 8.0,
    ));
  }

  final trackingTrails = <SonnetGuideTrail>[];
  if (isHero || rng.nextDouble() > 0.4) {
    final d = rng.nextBool() ? 1.0 : -1.0;
    final yOffset = (rng.nextDouble() - 0.5) * fontSize * 0.8;
    trackingTrails.add(SonnetGuideTrail(
      p0: Offset(-d * fontSize * 2.5, yOffset + fontSize * 1.5),
      p1: Offset(-d * fontSize * 0.8, yOffset - fontSize * 2.0),
      p2: Offset(d * fontSize * 0.8, yOffset + fontSize * 2.0),
      p3: Offset(d * fontSize * 2.5, yOffset - fontSize * 1.5),
      delay: rng.nextDouble() * 0.15,
    ));
  }
  if (isHero || rng.nextDouble() > 0.6) {
    final d = rng.nextBool() ? 1.0 : -1.0;
    trackingTrails.add(SonnetGuideTrail(
      p0: Offset(-fontSize * 2.0, -d * fontSize * 1.8),
      p1: Offset(fontSize * 2.0, d * fontSize * 1.8),
      p2: Offset(-fontSize * 2.0, d * fontSize * 1.8),
      p3: Offset(fontSize * 2.0, -d * fontSize * 1.8),
      delay: rng.nextDouble() * 0.1,
    ));
  }

  SonnetRectSpline? rectSpline;
  if (rng.nextDouble() > 0.4) {
    final length = fontSize * (1.2 + rng.nextDouble() * 1.5);
    final thickness = (isHero ? 6.0 : 3.0) + rng.nextDouble() * 8.0;
    final angle = (rng.nextDouble() - 0.5) * math.pi;
    final rx = (rng.nextDouble() - 0.5) * fontSize * 1.2;
    final ry = (rng.nextDouble() - 0.5) * fontSize * 1.2;
    rectSpline = SonnetRectSpline(
      p0: Offset(rx, ry),
      p1: Offset(rx + math.cos(angle) * length, ry + math.sin(angle) * length),
      thickness: thickness,
      delay: rng.nextDouble() * 0.15,
      duration: 0.25 + rng.nextDouble() * 0.2,
    );
  }

  final cue = resolveSonnetGuideCue(segment, textStartTime);

  return SonnetGuideView(
    placement: placement,
    startTime: cue.startTime,
    endTime: cue.endTime,
    maxAlpha: isHero ? 0.95 : 0.7,
    isHero: isHero,
    color: color,
    p0: p0,
    p1: p1,
    p2: p2,
    p3: p3,
    burstShapes: burstShapes,
    trackingTrails: trackingTrails,
    rectSpline: rectSpline,
  );
}
