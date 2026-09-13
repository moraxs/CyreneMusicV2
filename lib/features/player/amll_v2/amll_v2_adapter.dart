/// 项目歌词模型 → AMLL v2 引擎模型（`interfaces.ts` 的 `LyricLine`）。
library;

import '../mobile/compat/lyric_line.dart' as app;
import 'core/interfaces.dart';

/// 行尾兜底时长：最后一行没有下一行可推导结束时间时使用。
const Duration kV2FallbackLineDuration = Duration(seconds: 5);

List<V2LyricLine> toV2LyricLines(
  List<app.LyricLine> lines, {
  bool showTranslation = true,
  bool showRomanization = true,
}) {
  final result = <V2LyricLine>[];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final startMs = line.startTime.inMilliseconds;
    final endMs = _resolveLineEnd(lines, i);

    final words = <V2LyricWord>[];
    if (line.hasWordByWord) {
      for (final word in line.words!) {
        words.add(
          V2LyricWord(
            word: word.text,
            startTime: word.startTime.inMilliseconds,
            endTime: word.endTime.inMilliseconds,
            romanWord: word.romanWord,
            obscene: word.obscene,
          ),
        );
      }
    } else {
      // 逐行歌词：整行作为一个词，始末时间与行一致。
      // 注意这会让 `isNonDynamic` 判定为真（每行只有一个词），
      // 与上游行为一致。
      words.add(
        V2LyricWord(word: line.text, startTime: startMs, endTime: endMs),
      );
    }

    result.add(
      V2LyricLine(
        words: words,
        startTime: startMs,
        endTime: endMs,
        translatedLyric: showTranslation ? (line.translation ?? '') : '',
        romanLyric: showRomanization ? (line.romanization ?? '') : '',
        isBG: line.isBG,
        isDuet: line.isDuet,
      ),
    );
  }

  return result;
}

int _resolveLineEnd(List<app.LyricLine> lines, int index) {
  final line = lines[index];
  final startMs = line.startTime.inMilliseconds;

  if (line.hasWordByWord) {
    var latest = startMs;
    for (final word in line.words!) {
      final end = word.endTime.inMilliseconds;
      if (end > latest) latest = end;
    }
    if (latest > startMs) return latest;
  }

  final lineDuration = line.lineDuration;
  if (lineDuration != null && lineDuration > Duration.zero) {
    return startMs + lineDuration.inMilliseconds;
  }

  for (var i = index + 1; i < lines.length; i++) {
    final nextStart = lines[i].startTime.inMilliseconds;
    if (nextStart > startMs) return nextStart;
  }

  return startMs + kV2FallbackLineDuration.inMilliseconds;
}
