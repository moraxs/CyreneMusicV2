import 'dart:math' as math;

import 'default_types.dart';

double resolveDefaultVisualProgressWithCutoff(
  double startedAt,
  double duration,
  double currentTime,
  double cutoffTime,
) {
  final nominalEndTime = startedAt + math.max(duration, .001);
  final effectiveEndTime = math.max(
    startedAt + .001,
    math.min(nominalEndTime, cutoffTime),
  );
  return defaultClamp(
    (currentTime - startedAt) / math.max(effectiveEndTime - startedAt, .001),
    0,
    1,
  );
}

double resolveDefaultDelayedGlowEnvelope(double progress, [double peak = .8]) {
  final normalized = defaultClamp(progress, 0, 1);
  final clampedPeak = defaultClamp(peak, .05, .95);
  return normalized <= clampedPeak
      ? defaultEaseOutCubic(normalized / clampedPeak)
      : 1 - defaultEaseInCubic((normalized - clampedPeak) / (1 - clampedPeak));
}

double _wordProgress(DefaultWordRange range, double currentTime) {
  if (range.word.endTime <= range.word.startTime) {
    return currentTime >= range.word.endTime ? 1 : 0;
  }
  final duration = math.max(range.word.endTime - range.word.startTime, .08);
  return defaultClamp((currentTime - range.word.startTime) / duration, 0, 1);
}

int resolveDefaultPrintedCount(DefaultBlock block, double currentTime) {
  final count = block.graphemes.length;
  if (count == 0 || currentTime < block.line.startTime) return 0;
  if (currentTime >= block.line.endTime) return count;
  if (block.wordRanges.isEmpty) {
    final duration = math.max(block.line.endTime - block.line.startTime, .12);
    final progress = defaultClamp(
      (currentTime - block.line.startTime) / duration,
      0,
      1,
    );
    return (progress * count + (progress > 0 ? 1 : 0)).floor().clamp(0, count);
  }
  var printed = 0;
  for (final range in block.wordRanges) {
    final length = math.max(range.end - range.start, 0);
    final progress = _wordProgress(range, currentTime);
    final partial = (progress * length + .2).floor().clamp(
      progress > 0 ? 1 : 0,
      length,
    );
    printed = range.start + partial;
    if (partial < length) return printed.clamp(0, count);
  }
  return printed.clamp(0, count);
}

double resolveDefaultPrintedProgress(DefaultBlock block, double currentTime) {
  final count = block.graphemes.length;
  if (count == 0 || currentTime < block.line.startTime) return 0;
  if (currentTime >= block.line.endTime) return count.toDouble();
  if (block.wordRanges.isEmpty) {
    final duration = math.max(block.line.endTime - block.line.startTime, .12);
    return defaultClamp(
      (currentTime - block.line.startTime) / duration * count,
      0,
      count,
    );
  }
  var printed = 0.0;
  for (final range in block.wordRanges) {
    if (currentTime < range.word.startTime) {
      return defaultClamp(printed, 0, count);
    }
    final progress = _wordProgress(range, currentTime);
    printed = range.start + progress * math.max(range.end - range.start, 0);
    if (progress < 1) return defaultClamp(printed, 0, count);
  }
  return defaultClamp(printed, 0, count);
}

DefaultWordRange? defaultRangeAt(DefaultBlock block, int offset) {
  for (final range in block.wordRanges) {
    if (offset >= range.start && offset < range.end) return range;
  }
  return null;
}
