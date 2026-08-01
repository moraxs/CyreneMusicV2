/// 项目歌词模型 → AMLL 引擎歌词模型的转换。
///
/// 对应 tauri 端的 `toAmllLyricLines.ts`。
library;

import '../mobile/compat/lyric_line.dart' as app;
import 'core/lyric_types.dart';

/// 行尾兜底时长：最后一行没有下一行可推导结束时间时使用。
const Duration kFallbackLineDuration = Duration(seconds: 5);

/// 把项目内部的歌词行转换为 AMLL 引擎所需的结构。
///
/// 时间单位从 [Duration] 转为毫秒。行的结束时间按以下优先级推导：
/// 1. 逐字歌词最后一个词的结束时间
/// 2. 显式的 `lineDuration`
/// 3. 下一行的开始时间
/// 4. [kFallbackLineDuration]
List<AmllLyricLine> toAmllLyricLines(
  List<app.LyricLine> lines, {
  bool showTranslation = true,
  bool showRomanization = true,
}) {
  final result = <AmllLyricLine>[];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final startMs = line.startTime.inMilliseconds;
    final endMs = _resolveLineEnd(lines, i);

    final words = <AmllLyricWord>[];
    if (line.hasWordByWord) {
      for (final word in line.words!) {
        words.add(
          AmllLyricWord(
            word: word.text,
            startTime: word.startTime.inMilliseconds,
            endTime: word.endTime.inMilliseconds,
            romanWord: word.romanWord,
            obscene: word.obscene,
          ),
        );
      }
    } else {
      // 逐行歌词：整行作为一个词，始末时间与行一致
      words.add(
        AmllLyricWord(word: line.text, startTime: startMs, endTime: endMs),
      );
    }

    result.add(
      AmllLyricLine(
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

  // 逐字歌词以最后一个词的结束时间为准
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

  // 退回到下一行的开始时间
  for (var i = index + 1; i < lines.length; i++) {
    final nextStart = lines[i].startTime.inMilliseconds;
    if (nextStart > startMs) return nextStart;
  }

  return startMs + kFallbackLineDuration.inMilliseconds;
}
