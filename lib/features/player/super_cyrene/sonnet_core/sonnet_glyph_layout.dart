import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'sonnet_types.dart';
import 'sonnet_typography_layout.dart';
import 'sonnet_typography_roles.dart';

class SonnetGlyphPlacement {
  const SonnetGlyphPlacement({
    required this.char,
    required this.baseX,
    required this.baseY,
    required this.enterX,
    required this.enterY,
    required this.entryRotation,
    required this.startTime,
    required this.settleTime,
  });

  final String char;
  final double baseX;
  final double baseY;
  final double enterX;
  final double enterY;
  final double entryRotation;
  final double startTime;
  final double settleTime;
}

double resolveSonnetGlyphMotionDuration(double startTime, double endTime) {
  final shotDuration = math.max(0.001, endTime - startTime);
  final preferred = math.min(1.8, math.max(0.65, shotDuration * 0.42));
  return math.min(preferred, shotDuration * 0.72);
}

List<SonnetGlyphPlacement> buildSonnetGlyphLayout({
  required SonnetSemanticSegment segment,
  required SonnetTypographyPlacement placement,
  required double fontSize,
  required double Function(String char) measureGlyph,
  required double shotStartTime,
  required double shotEndTime,
}) {
  final fallbackChars = segment.text.characters.toList();
  final graphemes = segment.graphemes.isNotEmpty
      ? segment.graphemes
      : List.generate(fallbackChars.length, (index) {
          final segDur = segment.endTime - segment.startTime;
          return GraphemeTiming(
            char: fallbackChars[index],
            startTime: segment.startTime +
                segDur * index / math.max(1, fallbackChars.length),
            endTime: segment.startTime +
                segDur * (index + 1) / math.max(1, fallbackChars.length),
          );
        });

  final advances = graphemes.map((item) {
    return placement.vertical
        ? fontSize * 0.9
        : math.max(fontSize * 0.2, measureGlyph(item.char));
  }).toList();

  final totalAdvance =
      advances.fold<double>(0.0, (sum, advance) => sum + advance);
  final motionDuration =
      resolveSonnetGlyphMotionDuration(shotStartTime, shotEndTime);

  var cursor = -totalAdvance / 2;
  return List.generate(graphemes.length, (index) {
    final grapheme = graphemes[index];
    final advance = advances[index];
    final localX = placement.vertical ? 0.0 : cursor + advance / 2;
    final localY = placement.vertical ? cursor + advance / 2 : 0.0;
    cursor += advance;

    final cosine = math.cos(placement.rotation);
    final sine = math.sin(placement.rotation);
    final stagger = index % 2 == 0 ? -1.0 : 1.0;
    final startTime = grapheme.startTime;
    final settleTime = startTime + motionDuration;

    return SonnetGlyphPlacement(
      char: grapheme.char,
      baseX: placement.x + localX * cosine - localY * sine,
      baseY: placement.y + localX * sine + localY * cosine,
      enterX: placement.enterX +
          (placement.vertical ? stagger * fontSize * 0.28 : 0.0),
      enterY: placement.enterY +
          (placement.vertical ? 0.0 : stagger * fontSize * 0.24),
      entryRotation: stagger *
          (isSonnetEmphasisRole(placement.role) ? 0.055 : 0.035),
      startTime: startTime,
      settleTime: math.max(startTime, settleTime),
    );
  });
}
