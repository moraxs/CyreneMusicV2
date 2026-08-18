import 'package:characters/characters.dart';

import '../../mobile/compat/lyric_line.dart';
import 'sonnet_types.dart';

final _punctuationOnly = RegExp(
  r'^[\s\p{P}\p{S}]+$',
  unicode: true,
);

final _whitespaceOnly = RegExp(r'^\s+$');

List<String> splitLyricGraphemes(String text) {
  if (text.isEmpty) return const [];
  return text.characters.toList();
}

List<GraphemeTiming> _buildEvenGraphemeTimings(
  String text,
  double startTime,
  double endTime, [
  int? wordIndex,
]) {
  final graphemes = splitLyricGraphemes(text);
  if (graphemes.isEmpty) return const [];
  final duration = (endTime - startTime).clamp(0.0, double.infinity);
  final unitDuration = duration / graphemes.length;

  return List.generate(graphemes.length, (index) {
    return GraphemeTiming(
      char: graphemes[index],
      startTime: startTime + unitDuration * index,
      endTime: index == graphemes.length - 1
          ? endTime
          : startTime + unitDuration * (index + 1),
      wordIndex: wordIndex,
    );
  });
}

List<GraphemeTiming> _buildWordGraphemeTimings(
  LyricWord word, [
  int? wordIndex,
]) {
  final startSec = word.startTime.inMicroseconds / 1000000.0;
  final endSec =
      (word.startTime + word.duration).inMicroseconds / 1000000.0;
  return _buildEvenGraphemeTimings(word.text, startSec, endSec, wordIndex);
}

int _findGraphemeSequence(
  List<String> source,
  List<String> target,
  int fromIndex,
) {
  if (target.isEmpty) return fromIndex;
  for (var index = fromIndex; index <= source.length - target.length; index++) {
    var matched = true;
    for (var targetIndex = 0; targetIndex < target.length; targetIndex++) {
      if (source[index + targetIndex] != target[targetIndex]) {
        matched = false;
        break;
      }
    }
    if (matched) return index;
  }
  return -1;
}

List<GraphemeTiming> buildLineGraphemeTimeline(LyricLine line) {
  final lineGraphemes = splitLyricGraphemes(line.text);
  if (lineGraphemes.isEmpty) return const [];

  final lineStartSec = line.startTime.inMicroseconds / 1000000.0;
  final lineDurationSec = (line.lineDuration ?? const Duration(seconds: 4))
          .inMicroseconds /
      1000000.0;
  final lineEndSec = lineStartSec + lineDurationSec;

  if (line.words == null || line.words!.isEmpty) {
    return _buildEvenGraphemeTimings(line.text, lineStartSec, lineEndSec);
  }

  final timeline = List<GraphemeTiming?>.filled(lineGraphemes.length, null);
  var cursor = 0;
  var lastResolvedTime = lineStartSec;
  final words = line.words!;

  for (var wordIndex = 0; wordIndex < words.length; wordIndex++) {
    final word = words[wordIndex];
    final wordGraphemes = splitLyricGraphemes(word.text);
    if (wordGraphemes.isEmpty) continue;

    final wordStartSec = word.startTime.inMicroseconds / 1000000.0;
    final wordEndSec =
        (word.startTime + word.duration).inMicroseconds / 1000000.0;

    final matchedStart =
        _findGraphemeSequence(lineGraphemes, wordGraphemes, cursor);
    final start = matchedStart >= 0 ? matchedStart : cursor;
    final end = (start + wordGraphemes.length).clamp(0, lineGraphemes.length);

    for (var gapIndex = cursor; gapIndex < start; gapIndex++) {
      timeline[gapIndex] = GraphemeTiming(
        char: lineGraphemes[gapIndex],
        startTime: wordStartSec,
        endTime: wordStartSec,
      );
    }

    final wordTimings = _buildWordGraphemeTimings(word, wordIndex);
    for (var localIndex = 0; localIndex < end - start; localIndex++) {
      final timing = localIndex < wordTimings.length
          ? wordTimings[localIndex]
          : GraphemeTiming(
              char: wordGraphemes[localIndex],
              startTime: wordStartSec,
              endTime: wordEndSec,
              wordIndex: wordIndex,
            );

      timeline[start + localIndex] = GraphemeTiming(
        char: lineGraphemes[start + localIndex],
        startTime: timing.startTime,
        endTime: timing.endTime,
        wordIndex: timing.wordIndex,
      );
      lastResolvedTime = lastResolvedTime > timing.endTime
          ? lastResolvedTime
          : timing.endTime;
    }

    cursor = cursor > end ? cursor : end;
  }

  for (var index = 0; index < lineGraphemes.length; index++) {
    if (timeline[index] != null) continue;
    timeline[index] = GraphemeTiming(
      char: lineGraphemes[index],
      startTime: lastResolvedTime,
      endTime: lastResolvedTime,
    );
  }

  return timeline.cast<GraphemeTiming>();
}

class _SegmentPart {
  _SegmentPart({
    required this.segment,
    required this.index,
    required this.isWordLike,
  });
  final String segment;
  final int index;
  final bool isWordLike;
}

List<_SegmentPart> _getSegmenterParts(String text) {
  // Use regex word tokenizer supporting CJK characters, Latin words, whitespace, and punctuation.
  final parts = <_SegmentPart>[];
  final regex = RegExp(
    r'[\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]|[a-zA-Z0-9_\u00C0-\u024F]+|[^\s\w\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]+|\s+',
    unicode: true,
  );

  var cursor = 0;
  for (final match in regex.allMatches(text)) {
    final s = match.group(0)!;
    final isWord = !_punctuationOnly.hasMatch(s);
    parts.add(_SegmentPart(segment: s, index: cursor, isWordLike: isWord));
    cursor += s.length;
  }

  if (parts.isEmpty && text.isNotEmpty) {
    parts.add(_SegmentPart(
      segment: text,
      index: 0,
      isWordLike: !_punctuationOnly.hasMatch(text),
    ));
  }
  return parts;
}

List<({int start, int end})> _getGraphemeRanges(String text) {
  var cursor = 0;
  final result = <({int start, int end})>[];
  for (final g in splitLyricGraphemes(text)) {
    final end = cursor + g.length;
    result.add((start: cursor, end: end));
    cursor = end;
  }
  return result;
}

List<SonnetSemanticSegment> buildSonnetSemanticSegments(LyricLine line) {
  if (line.text.isEmpty) return const [];
  final timeline = buildLineGraphemeTimeline(line);
  final ranges = _getGraphemeRanges(line.text);
  final parts = _getSegmenterParts(line.text);

  final segments = List.generate(parts.length, (index) {
    final part = parts[index];
    final startOffset = part.index;
    final endOffset =
        index + 1 < parts.length ? parts[index + 1].index : line.text.length;
    final subText = line.text.substring(startOffset, endOffset);

    final indices = <int>[];
    for (var rIdx = 0; rIdx < ranges.length; rIdx++) {
      final range = ranges[rIdx];
      if (range.end > startOffset && range.start < endOffset) {
        indices.add(rIdx);
      }
    }

    final graphemes = <GraphemeTiming>[];
    for (final idx in indices) {
      if (idx < timeline.length) graphemes.add(timeline[idx]);
    }

    final wordIndices = <int>{};
    for (final g in graphemes) {
      if (g.wordIndex != null) wordIndices.add(g.wordIndex!);
    }

    final lineStartSec = line.startTime.inMicroseconds / 1000000.0;
    final lineDurationSec = (line.lineDuration ?? const Duration(seconds: 4))
            .inMicroseconds /
        1000000.0;
    final lineEndSec = lineStartSec + lineDurationSec;

    final segStart = graphemes.isNotEmpty ? graphemes.first.startTime : lineStartSec;
    final segEnd = graphemes.isNotEmpty ? graphemes.last.endTime : lineEndSec;

    return SonnetSemanticSegment(
      text: subText,
      startOffset: startOffset,
      endOffset: endOffset,
      startTime: segStart,
      endTime: segEnd,
      wordIndices: wordIndices.toList(),
      graphemes: graphemes,
      isWordLike: part.isWordLike,
    );
  });

  final sticky = <SonnetSemanticSegment>[];
  for (final segment in segments) {
    if (sticky.isNotEmpty &&
        !segment.isWordLike &&
        !_whitespaceOnly.hasMatch(segment.text)) {
      final previous = sticky.last;
      previous.text += segment.text;
      previous.endOffset = segment.endOffset;
      if (segment.endTime > previous.endTime) {
        previous.endTime = segment.endTime;
      }
      previous.graphemes.addAll(segment.graphemes);
      final set = previous.wordIndices.toSet()..addAll(segment.wordIndices);
      previous.wordIndices = set.toList();
    } else {
      sticky.add(SonnetSemanticSegment(
        text: segment.text,
        startOffset: segment.startOffset,
        endOffset: segment.endOffset,
        startTime: segment.startTime,
        endTime: segment.endTime,
        wordIndices: List.of(segment.wordIndices),
        graphemes: List.of(segment.graphemes),
        isWordLike: segment.isWordLike,
      ));
    }
  }
  return sticky;
}
