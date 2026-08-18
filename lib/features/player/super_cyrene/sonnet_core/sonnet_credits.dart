import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'sonnet_motion.dart';

class SonnetCreditsFrame {
  const SonnetCreditsFrame({
    required this.active,
    required this.lyricAlpha,
    required this.lyricBlur,
    required this.posterAlpha,
    required this.posterOffsetY,
    required this.posterScale,
  });

  final bool active;
  final double lyricAlpha;
  final double lyricBlur;
  final double posterAlpha;
  final double posterOffsetY;
  final double posterScale;

  static const inactive = SonnetCreditsFrame(
    active: false,
    lyricAlpha: 1.0,
    lyricBlur: 0.0,
    posterAlpha: 0.0,
    posterOffsetY: 0.04,
    posterScale: 0.965,
  );
}

class SonnetCreditsMetadata {
  const SonnetCreditsMetadata({
    this.title,
    this.artist,
    this.album,
  });

  final String? title;
  final String? artist;
  final String? album;
}

String _normalizeMetadata(String? value) => value?.trim() ?? '';

SonnetCreditsFrame resolveSonnetCreditsFrame(
  double time,
  double finalLyricEndTime,
) {
  final elapsed = time - finalLyricEndTime;
  if (elapsed <= 0) return SonnetCreditsFrame.inactive;

  final lyricExit = easeSonnetInOut(clamp01(elapsed / 1.25));
  final posterEnter = easeSonnetInOut(clamp01((elapsed - 0.38) / 1.55));
  return SonnetCreditsFrame(
    active: true,
    lyricAlpha: 1.0 - lyricExit,
    lyricBlur: lyricExit * 18.0,
    posterAlpha: posterEnter,
    posterOffsetY: (1.0 - posterEnter) * 0.04,
    posterScale: 0.965 + posterEnter * 0.035,
  );
}

bool hasSonnetCreditsMetadata(SonnetCreditsMetadata metadata) =>
    _normalizeMetadata(metadata.title).isNotEmpty ||
    _normalizeMetadata(metadata.artist).isNotEmpty ||
    _normalizeMetadata(metadata.album).isNotEmpty;

void paintSonnetCreditsPoster({
  required Canvas canvas,
  required SonnetCreditsMetadata metadata,
  required double width,
  required double height,
  required Color primaryColor,
  required Color secondaryColor,
  required Color accentColor,
  required String? fontFamily,
  required double alpha,
  required double offsetYRatio,
  required double scale,
  double lyricsFontScale = 1.0,
}) {
  if (alpha <= 0.001) return;

  final title = _normalizeMetadata(metadata.title);
  final artist = _normalizeMetadata(metadata.artist);
  final album = _normalizeMetadata(metadata.album);

  final left = math.max(38.0, width * 0.105);
  final right = math.max(38.0, width * 0.09);
  final contentWidth = math.max(220.0, width - left - right);
  final titleSize =
      math.max(36.0, math.min(96.0, width * 0.088 * lyricsFontScale));
  final detailSize =
      math.max(12.0, math.min(22.0, width * 0.018 * lyricsFontScale));

  canvas.save();
  canvas.translate(width / 2.0, height / 2.0 + height * offsetYRatio);
  canvas.scale(scale, scale);
  canvas.translate(-width / 2.0, -height / 2.0);

  final geomPaint = Paint()..style = PaintingStyle.fill;
  canvas.drawRect(
    Rect.fromLTWH(
      left,
      height * 0.155,
      math.max(42.0, width * 0.075),
      5.0,
    ),
    geomPaint..color = accentColor.withValues(alpha: (0.95 * alpha).clamp(0.0, 1.0)),
  );
  canvas.drawRect(
    Rect.fromLTWH(left, height * 0.155, 2.0, height * 0.57),
    geomPaint..color = primaryColor.withValues(alpha: (0.22 * alpha).clamp(0.0, 1.0)),
  );
  canvas.drawRect(
    Rect.fromLTWH(width - right - 8.0, height * 0.225, 8.0, height * 0.34),
    geomPaint..color = secondaryColor.withValues(alpha: (0.32 * alpha).clamp(0.0, 1.0)),
  );
  canvas.drawLine(
    Offset(left, height * 0.79),
    Offset(width - right, height * 0.79),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = primaryColor.withValues(alpha: (0.36 * alpha).clamp(0.0, 1.0)),
  );

  if (artist.isNotEmpty) {
    final tp = TextPainter(
      text: TextSpan(
        text: artist.toUpperCase(),
        style: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: detailSize,
          letterSpacing: math.max(2.0, detailSize * 0.18),
          color: accentColor.withValues(alpha: alpha.clamp(0.0, 1.0)),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentWidth * 0.72);
    tp.paint(canvas, Offset(left + 20.0, height * 0.205));
    tp.dispose();
  }

  if (title.isNotEmpty) {
    final tp = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w800,
          fontSize: titleSize,
          letterSpacing: -math.max(0.5, titleSize * 0.018),
          color: primaryColor.withValues(alpha: alpha.clamp(0.0, 1.0)),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentWidth * 0.88);
    tp.paint(canvas, Offset(left + 16.0, height * 0.285));
    tp.dispose();
  }

  if (album.isNotEmpty) {
    final tp = TextPainter(
      text: TextSpan(
        text: '— $album',
        style: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w500,
          fontSize: detailSize * 0.92,
          letterSpacing: math.max(1.0, detailSize * 0.1),
          color: secondaryColor.withValues(alpha: alpha.clamp(0.0, 1.0)),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentWidth * 0.72);
    tp.paint(canvas, Offset(left + 18.0, height * 0.825));
    tp.dispose();
  }

  canvas.restore();
}

class SonnetIntroFrame {
  const SonnetIntroFrame({
    required this.active,
    required this.posterAlpha,
    required this.posterOffsetY,
    required this.posterScale,
  });

  final bool active;
  final double posterAlpha;
  final double posterOffsetY;
  final double posterScale;

  static const inactive = SonnetIntroFrame(
    active: false,
    posterAlpha: 0.0,
    posterOffsetY: 0.0,
    posterScale: 1.0,
  );
}

SonnetIntroFrame resolveSonnetIntroFrame(
  double time,
  double firstLyricStartTime,
) {
  if (time >= firstLyricStartTime || firstLyricStartTime <= 0.3) {
    return SonnetIntroFrame.inactive;
  }

  // Entrance during first 1.0s
  final enterProgress = clamp01(time / 1.0);
  final enterAlpha = easeSonnetInOut(enterProgress);

  // Exit during last 0.8s before first lyric starts
  final remaining = firstLyricStartTime - time;
  final exitProgress = remaining < 0.8 ? clamp01(remaining / 0.8) : 1.0;
  final exitAlpha = easeSonnetInOut(exitProgress);

  final alpha = (enterAlpha * exitAlpha).clamp(0.0, 1.0);
  final scale = 0.96 + 0.04 * enterAlpha - (1.0 - exitAlpha) * 0.04;
  final offsetY = (1.0 - enterAlpha) * 0.03 - (1.0 - exitAlpha) * 0.03;

  return SonnetIntroFrame(
    active: true,
    posterAlpha: alpha,
    posterOffsetY: offsetY,
    posterScale: scale,
  );
}

void paintSonnetIntroPoster({
  required Canvas canvas,
  required SonnetCreditsMetadata metadata,
  required double width,
  required double height,
  required Color primaryColor,
  required Color secondaryColor,
  required Color accentColor,
  required String? fontFamily,
  required double alpha,
  required double offsetYRatio,
  required double scale,
  double lyricsFontScale = 1.0,
}) {
  if (alpha <= 0.001) return;

  final title = _normalizeMetadata(metadata.title);
  final artist = _normalizeMetadata(metadata.artist);
  final album = _normalizeMetadata(metadata.album);

  final left = math.max(38.0, width * 0.11);
  final right = math.max(38.0, width * 0.11);
  final contentWidth = math.max(220.0, width - left - right);
  final titleSize =
      math.max(30.0, math.min(76.0, width * 0.068 * lyricsFontScale));
  final detailSize =
      math.max(12.0, math.min(18.0, width * 0.015 * lyricsFontScale));

  canvas.save();
  canvas.translate(width / 2.0, height / 2.0 + height * offsetYRatio);
  canvas.scale(scale, scale);
  canvas.translate(-width / 2.0, -height / 2.0);

  // Song Title
  if (title.isNotEmpty) {
    final titleTp = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w800,
          fontSize: titleSize,
          letterSpacing: -math.max(0.5, titleSize * 0.018),
          color: primaryColor.withValues(alpha: (0.95 * alpha).clamp(0.0, 1.0)),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentWidth);
    titleTp.paint(canvas, Offset(left, height * 0.32));
    titleTp.dispose();
  }

  // Artist & Album
  final subtitleParts = [
    if (artist.isNotEmpty) artist,
    if (album.isNotEmpty) album,
  ];
  if (subtitleParts.isNotEmpty) {
    final subTp = TextPainter(
      text: TextSpan(
        text: subtitleParts.join('   —   '),
        style: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: detailSize,
          letterSpacing: math.max(1.2, detailSize * 0.12),
          color: secondaryColor.withValues(alpha: (0.85 * alpha).clamp(0.0, 1.0)),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentWidth);
    subTp.paint(canvas, Offset(left, height * 0.32 + titleSize * 1.35));
    subTp.dispose();
  }

  canvas.restore();
}
