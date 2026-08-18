import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'sonnet_motion.dart';
import 'sonnet_types.dart';

class SonnetInterludeInterval {
  const SonnetInterludeInterval({
    required this.startTime,
    required this.endTime,
    required this.anchorParagraphIndex,
  });

  final double startTime;
  final double endTime;
  final int anchorParagraphIndex;

  double get duration => endTime - startTime;
}

SonnetInterludeInterval? findActiveSonnetInterlude(
  SonnetProgram program,
  double currentTime, {
  double minInterludeDuration = 2.0,
}) {
  if (program.paragraphs.isEmpty) return null;

  // 1. Song Intro Interlude
  final firstPara = program.paragraphs.first;
  if (firstPara.startTime >= minInterludeDuration) {
    if (currentTime < firstPara.startTime) {
      return SonnetInterludeInterval(
        startTime: 0.0,
        endTime: firstPara.startTime,
        anchorParagraphIndex: -1,
      );
    }
  }

  // 2. Interludes between Paragraphs
  for (var i = 0; i < program.paragraphs.length; i++) {
    final current = program.paragraphs[i];
    final next = (i + 1 < program.paragraphs.length)
        ? program.paragraphs[i + 1]
        : null;
    if (next != null) {
      final gap = next.startTime - current.endTime;
      if (gap >= minInterludeDuration) {
        if (currentTime >= current.endTime && currentTime <= next.startTime) {
          return SonnetInterludeInterval(
            startTime: current.endTime,
            endTime: next.startTime,
            anchorParagraphIndex: i,
          );
        }
      }
    }
  }

  return null;
}

class SonnetInterludeDotsState {
  const SonnetInterludeDotsState({
    required this.scale,
    required this.globalAlpha,
    required this.dotOpacities,
    required this.isVisible,
  });

  final double scale;
  final double globalAlpha;
  final List<double> dotOpacities;
  final bool isVisible;

  static const hidden = SonnetInterludeDotsState(
    scale: 0.0,
    globalAlpha: 0.0,
    dotOpacities: [0.0, 0.0, 0.0],
    isVisible: false,
  );
}

SonnetInterludeDotsState resolveSonnetInterludeDotsState({
  required double currentTime,
  required double startTime,
  required double endTime,
}) {
  final interludeDuration = endTime - startTime;
  if (interludeDuration <= 0.5) return SonnetInterludeDotsState.hidden;

  final elapsed = currentTime - startTime;
  if (elapsed < 0.0 || elapsed > interludeDuration) {
    return SonnetInterludeDotsState.hidden;
  }

  // Breathe rhythm: target 1.5s per cycle
  const targetBreathe = 1.5;
  final breatheCount = math.max(1, (interludeDuration / targetBreathe).round());
  final breathePeriod = interludeDuration / breatheCount;

  var scale = 1.0;
  var globalAlpha = 1.0;

  // Gentle sine breathing
  scale += math.sin((elapsed / breathePeriod) * math.pi * 2.0) * 0.12;

  // Entrance scaling & fading (first 1.2s)
  if (elapsed < 1.2) {
    final enterProg = clamp01(elapsed / 1.2);
    scale *= easeSonnetExpoOut(enterProg);
    globalAlpha *= easeSonnetInOut(enterProg);
  }

  // Exit anticipation (last 0.75s before next lyric starts)
  final remaining = endTime - currentTime;
  if (remaining < 0.75) {
    final exitProg = clamp01(remaining / 0.75);
    scale *= exitProg * 0.9 + 0.1;
    globalAlpha *= exitProg;
  }

  // Progressive dot fill wave
  final activeDotsDuration = math.max(0.1, interludeDuration - 0.75);
  double rawDotOpacity(double t) {
    if (activeDotsDuration <= 0) return 0.35;
    return (clamp01(t / activeDotsDuration) * 0.65 + 0.35);
  }

  final dot1 = clamp01(globalAlpha * rawDotOpacity(elapsed));
  final dot2 = clamp01(
      globalAlpha * rawDotOpacity(elapsed - activeDotsDuration / 3.0));
  final dot3 = clamp01(
      globalAlpha * rawDotOpacity(elapsed - (activeDotsDuration / 3.0) * 2.0));

  return SonnetInterludeDotsState(
    scale: math.max(0.0, scale),
    globalAlpha: globalAlpha,
    dotOpacities: [dot1, dot2, dot3],
    isVisible: globalAlpha > 0.01 && scale > 0.01,
  );
}

void paintSonnetInterludeDots({
  required Canvas canvas,
  required SonnetInterludeDotsState state,
  required double width,
  required double height,
  required Color primaryColor,
  required Color accentColor,
  double dotRadius = 4.5,
  double dotSpacing = 16.0,
}) {
  if (!state.isVisible) return;

  final totalWidth = (dotRadius * 2.0) * 3 + dotSpacing * 2;
  final cx = width / 2.0;
  final cy = height * 0.85;

  canvas.save();
  canvas.translate(cx, cy);
  canvas.scale(state.scale, state.scale);

  // Subtle background technical frame: [ • • • ]
  final framePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0
    ..color = primaryColor.withValues(alpha: (0.18 * state.globalAlpha).clamp(0.0, 1.0));

  final frameHalfW = totalWidth / 2.0 + 20.0;
  // Left bracket
  canvas.drawLine(
    Offset(-frameHalfW, -6.0),
    Offset(-frameHalfW - 4.0, -6.0),
    framePaint,
  );
  canvas.drawLine(
    Offset(-frameHalfW - 4.0, -6.0),
    Offset(-frameHalfW - 4.0, 6.0),
    framePaint,
  );
  canvas.drawLine(
    Offset(-frameHalfW - 4.0, 6.0),
    Offset(-frameHalfW, 6.0),
    framePaint,
  );

  // Right bracket
  canvas.drawLine(
    Offset(frameHalfW, -6.0),
    Offset(frameHalfW + 4.0, -6.0),
    framePaint,
  );
  canvas.drawLine(
    Offset(frameHalfW + 4.0, -6.0),
    Offset(frameHalfW + 4.0, 6.0),
    framePaint,
  );
  canvas.drawLine(
    Offset(frameHalfW + 4.0, 6.0),
    Offset(frameHalfW, 6.0),
    framePaint,
  );

  // Draw the 3 dots with halo glow
  final dotPaint = Paint()..style = PaintingStyle.fill;
  final startX = -totalWidth / 2.0 + dotRadius;

  for (var i = 0; i < 3; i++) {
    final opacity = state.dotOpacities[i];
    if (opacity <= 0.001) continue;

    final dotX = startX + i * (dotRadius * 2.0 + dotSpacing);
    final dotCenter = Offset(dotX, 0.0);

    // Glowing halo
    canvas.drawCircle(
      dotCenter,
      dotRadius * 2.2,
      Paint()
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0)
        ..color = accentColor.withValues(
          alpha: (0.35 * opacity).clamp(0.0, 1.0),
        ),
    );

    // Core dot
    dotPaint.color = Color.lerp(
      primaryColor,
      accentColor,
      opacity,
    )!
        .withValues(alpha: opacity);
    canvas.drawCircle(dotCenter, dotRadius, dotPaint);
  }

  canvas.restore();
}
