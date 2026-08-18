import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'sonnet_staff_notation.dart';
import 'sonnet_typography_layout.dart';

class TimedSonnetStaffNote {
  const TimedSonnetStaffNote({
    required this.note,
    required this.startBeat,
  });

  final SonnetStaffNote note;
  final double startBeat;
}

class SonnetStaffView {
  SonnetStaffView({
    required this.placement,
    required this.primaryColor,
    required this.accentColor,
    required this.baseFontSize,
    required this.shotStartTime,
    required this.width,
  }) {
    var beatCursor = 0.0;
    for (final note in laFoliaStaffNotes) {
      timedNotes.add(TimedSonnetStaffNote(note: note, startBeat: beatCursor));
      beatCursor += note.beats;
    }
  }

  final SonnetTypographyPlacement placement;
  final Color primaryColor;
  final Color accentColor;
  final double baseFontSize;
  final double shotStartTime;
  final double width;
  final List<TimedSonnetStaffNote> timedNotes = [];

  void paint(Canvas canvas, double time, double alpha) {
    if (alpha <= 0) return;

    final staffWidth = math.max(300.0, width * 0.6);
    final lineSpacing = baseFontSize * 0.25;
    final totalHeight = lineSpacing * 4.0;
    final halfWidth = staffWidth / 2.0;
    final halfHeight = totalHeight / 2.0;
    final playableWidth = staffWidth * 0.92;
    final beatWidth = playableWidth / laFoliaTotalBeats;

    canvas.save();
    canvas.translate(placement.x, placement.y);
    canvas.rotate(placement.rotation);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = primaryColor.withValues(alpha: (0.3 * alpha).clamp(0.0, 1.0));

    // Draw 5 staff lines
    for (var i = 0; i < 5; i++) {
      final y = -halfHeight + i * lineSpacing;
      canvas.drawLine(Offset(-halfWidth, y), Offset(halfWidth, y), linePaint);
    }

    // Bar lines
    final barPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = primaryColor.withValues(alpha: (0.16 * alpha).clamp(0.0, 1.0));

    for (var bar = 1; bar < 8; bar++) {
      final x = -playableWidth / 2.0 + beatWidth * bar * 3.0;
      canvas.drawLine(Offset(x, -halfHeight), Offset(x, halfHeight), barPaint);
    }

    // Clef / side bars
    final thickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = primaryColor.withValues(alpha: (0.5 * alpha).clamp(0.0, 1.0));

    canvas.drawLine(
      Offset(-halfWidth + 10.0, -halfHeight),
      Offset(-halfWidth + 10.0, halfHeight),
      thickPaint..strokeWidth = 4.0,
    );
    canvas.drawLine(
      Offset(halfWidth - 10.0, -halfHeight),
      Offset(halfWidth - 10.0, halfHeight),
      thickPaint..strokeWidth = 2.0,
    );
    canvas.drawLine(
      Offset(halfWidth - 4.0, -halfHeight),
      Offset(halfWidth - 4.0, halfHeight),
      thickPaint..strokeWidth = 6.0,
    );

    // Playback loop
    final cycleElapsed =
        ((time - shotStartTime) % laFoliaCycleSeconds + laFoliaCycleSeconds) %
            laFoliaCycleSeconds;
    final beatPosition =
        (cycleElapsed / laFoliaCycleSeconds) * laFoliaTotalBeats;
    final cursorX = -playableWidth / 2.0 + beatWidth * beatPosition;

    // Cursor line
    canvas.drawLine(
      Offset(cursorX, -halfHeight - lineSpacing * 0.8),
      Offset(cursorX, halfHeight + lineSpacing * 0.8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accentColor.withValues(alpha: (0.34 * alpha).clamp(0.0, 1.0)),
    );

    for (var index = 0; index < timedNotes.length; index++) {
      final timed = timedNotes[index];
      final note = timed.note;
      final isActive = beatPosition >= timed.startBeat &&
          beatPosition < timed.startBeat + note.beats;
      final pulse = isActive
          ? (math.sin(cycleElapsed * math.pi * 5.0 + index * 0.4) + 1.0) * 0.5
          : 0.0;
      final noteScale = isActive ? 1.0 + pulse * 0.12 : 1.0;
      final noteRadiusX = lineSpacing * 0.42 * noteScale;
      final noteRadiusY = lineSpacing * 0.29 * noteScale;
      final x = -playableWidth / 2.0 +
          beatWidth * (timed.startBeat + note.beats * 0.5);
      final y = halfHeight - note.staffStep * lineSpacing * 0.5;
      final noteAlpha =
          ((isActive ? 0.78 + pulse * 0.16 : 0.28 + (index % 3) * 0.03) *
                  alpha)
              .clamp(0.0, 1.0);
      final stemDown = note.staffStep >= 6;
      final stemX = x + (stemDown ? -noteRadiusX : noteRadiusX);
      final stemEndY =
          y + (stemDown ? lineSpacing * 3.1 : -lineSpacing * 3.1);

      // Note oval
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, y),
          width: noteRadiusX * 2.0,
          height: noteRadiusY * 2.0,
        ),
        Paint()
          ..style = PaintingStyle.fill
          ..color = accentColor.withValues(alpha: noteAlpha),
      );

      // Stem
      canvas.drawLine(
        Offset(stemX, y),
        Offset(stemX, stemEndY),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = primaryColor.withValues(
            alpha: math.min(0.9, noteAlpha + 0.08 * alpha).clamp(0.0, 1.0),
          ),
      );

      // Flag if 0.5 beat
      if (note.beats <= 0.5) {
        final flagY = stemEndY;
        final flagDirection = stemDown ? -1.0 : 1.0;
        final flagPath = Path()
          ..moveTo(stemX, flagY)
          ..quadraticBezierTo(
            stemX + lineSpacing * 1.1,
            flagY + lineSpacing * 0.55 * flagDirection,
            stemX + lineSpacing * 0.1,
            flagY + lineSpacing * flagDirection,
          );
        canvas.drawPath(
          flagPath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = primaryColor.withValues(
              alpha: math.min(0.9, noteAlpha + 0.08 * alpha).clamp(0.0, 1.0),
            ),
        );
      }

      // Accidental sharp
      if (note.accidental == 'sharp') {
        final sharpX = x - noteRadiusX * 2.3;
        final sharpHeight = lineSpacing * 1.15;
        final sharpPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = primaryColor.withValues(
            alpha: math.min(0.86, noteAlpha + 0.08 * alpha).clamp(0.0, 1.0),
          );

        canvas.drawLine(
          Offset(sharpX - lineSpacing * 0.16, y - sharpHeight * 0.5),
          Offset(sharpX - lineSpacing * 0.16, y + sharpHeight * 0.5),
          sharpPaint,
        );
        canvas.drawLine(
          Offset(sharpX + lineSpacing * 0.16, y - sharpHeight * 0.5),
          Offset(sharpX + lineSpacing * 0.16, y + sharpHeight * 0.5),
          sharpPaint,
        );
        canvas.drawLine(
          Offset(sharpX - lineSpacing * 0.34, y - lineSpacing * 0.12),
          Offset(sharpX + lineSpacing * 0.34, y - lineSpacing * 0.28),
          sharpPaint,
        );
        canvas.drawLine(
          Offset(sharpX - lineSpacing * 0.34, y + lineSpacing * 0.28),
          Offset(sharpX + lineSpacing * 0.34, y + lineSpacing * 0.12),
          sharpPaint,
        );
      }
    }

    canvas.restore();
  }
}
