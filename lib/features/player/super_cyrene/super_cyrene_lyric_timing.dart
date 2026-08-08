import 'package:characters/characters.dart';

import '../mobile/compat/lyric_line.dart';
import 'default_core/default_types.dart';

/// Adapts backend lyric words to the timeline consumed by SuperCyrene.
///
/// Some backends represent a plain LRC line as one zero-duration (or one
/// whole-line) word. That is not usable word-by-word timing, so SuperCyrene
/// synthesizes one evenly timed entry per visible grapheme instead.
List<DefaultWord> buildSuperCyreneWordTimeline({
  required LyricLine line,
  required Duration lineEnd,
}) {
  final sourceWords = line.words;
  final hasUsableWordTiming =
      sourceWords != null &&
      sourceWords.length > 1 &&
      sourceWords.every((word) => word.duration > Duration.zero);

  if (hasUsableWordTiming) {
    return sourceWords
        .map(
          (word) => DefaultWord(
            text: word.text,
            startTime: word.startTime.inMicroseconds / 1000000,
            endTime: word.endTime.inMicroseconds / 1000000,
          ),
        )
        .toList(growable: false);
  }

  final tokens = <String>[];
  for (final grapheme in line.text.characters) {
    if (grapheme.trim().isEmpty && tokens.isNotEmpty) {
      tokens[tokens.length - 1] += grapheme;
    } else {
      tokens.add(grapheme);
    }
  }
  if (tokens.isEmpty) return const [];

  final startUs = line.startTime.inMicroseconds;
  final requestedEndUs = lineEnd.inMicroseconds;
  final endUs = requestedEndUs > startUs
      ? requestedEndUs
      : startUs + const Duration(seconds: 4).inMicroseconds;
  final durationUs = endUs - startUs;

  return List<DefaultWord>.generate(tokens.length, (index) {
    final wordStartUs = startUs + (durationUs * index / tokens.length).round();
    final wordEndUs =
        startUs + (durationUs * (index + 1) / tokens.length).round();
    return DefaultWord(
      text: tokens[index],
      startTime: wordStartUs / 1000000,
      endTime: wordEndUs / 1000000,
    );
  }, growable: false);
}
