import 'dart:math' as math;
import 'sonnet_glyph_layout.dart';
import 'sonnet_types.dart';
import 'sonnet_typography_layout.dart';

class SonnetTrackingGlyph {
  const SonnetTrackingGlyph({
    required this.baseX,
    required this.baseY,
    required this.startTime,
    this.isBackgroundShape = false,
  });

  final double baseX;
  final double baseY;
  final double startTime;
  final bool isBackgroundShape;
}

List<SonnetTrackingGlyph> resolveSonnetCameraTrackingGlyphs(
  List<({
    SonnetSemanticSegment segment,
    SonnetTypographyPlacement placement,
    List<SonnetGlyphPlacement> glyphs
  })> segments,
) {
  final trackingGlyphs = <SonnetTrackingGlyph>[];
  for (final item in segments) {
    if (item.placement.role == SonnetSegmentRole.decoration) continue;
    for (final glyph in item.glyphs) {
      if (glyph.char.trim().isEmpty) continue;
      trackingGlyphs.add(SonnetTrackingGlyph(
        baseX: glyph.baseX,
        baseY: glyph.baseY,
        startTime: glyph.startTime,
      ));
    }
  }
  return trackingGlyphs;
}

({double x, double y}) resolveSonnetSegmentCameraFocus(
  List<SonnetTrackingGlyph> glyphs,
  double time, [
  double trackingFactor = 0.5,
]) {
  if (glyphs.isEmpty) return (x: 0.0, y: 0.0);
  final first = glyphs.first;
  final last = glyphs.last;
  final segCenterX = (first.baseX + last.baseX) / 2.0;
  final segCenterY = (first.baseY + last.baseY) / 2.0;

  ({double x, double y}) applyFactor(double exactX, double exactY) => (
        x: segCenterX + (exactX - segCenterX) * trackingFactor,
        y: segCenterY + (exactY - segCenterY) * trackingFactor,
      );

  if (time <= first.startTime) return applyFactor(first.baseX, first.baseY);
  if (time >= last.startTime) return applyFactor(last.baseX, last.baseY);

  for (var index = 0; index < glyphs.length - 1; index++) {
    final current = glyphs[index];
    final next = glyphs[index + 1];
    if (time < current.startTime || time > next.startTime) continue;
    final progress = (time - current.startTime) /
        math.max(0.001, next.startTime - current.startTime);
    return applyFactor(
      current.baseX + (next.baseX - current.baseX) * progress,
      current.baseY + (next.baseY - current.baseY) * progress,
    );
  }
  return applyFactor(first.baseX, first.baseY);
}
