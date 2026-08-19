import 'package:flutter/foundation.dart';

import 'lyric_line.dart';

/// 歌词解析器
class LyricParser {
  /// 解析网易云音乐 YRC 格式逐字歌词
  /// YRC格式示例: [22310,4300](22310,2880,0)都 (25190,310,0)是(25500,290,0)勇
  /// 后端原样透传网易 YRC；行与字的起始时间、持续时间均为毫秒。
  static List<LyricLine> parseNeteaseYrcLyric(
    String yrcLyric, {
    String? translation,
    String? romaji,
  }) {
    if (yrcLyric.isEmpty) return [];

    final lines = <LyricLine>[];
    final yrcLines = yrcLyric.split('\n');

    // 解析翻译歌词（如果有）
    final Map<Duration, String> translationMap = {};
    if (translation != null && translation.isNotEmpty) {
      final translationLines = translation.split('\n');
      for (final line in translationLines) {
        final time = LyricLine.parseTime(line);
        if (time != null) {
          final text = line
              .replaceAll(RegExp(r'\[\d+:\d+\.\d+\]'), '')
              .replaceAll(RegExp(r'\[\d+:\d+:\d+\]'), '')
              .replaceAll(RegExp(r'\[\d+:\d+\]'), '')
              .trim();
          if (text.isNotEmpty) {
            translationMap[time] = text;
          }
        }
      }
    }

    // 解析罗马音歌词（如果有，与翻译同构按时间戳匹配）
    final Map<Duration, String> romajiMap = {};
    if (romaji != null && romaji.isNotEmpty) {
      final romajiLines = romaji.split('\n');
      for (final line in romajiLines) {
        final time = LyricLine.parseTime(line);
        if (time != null) {
          final text = line
              .replaceAll(RegExp(r'\[\d+:\d+\.\d+\]'), '')
              .replaceAll(RegExp(r'\[\d+:\d+:\d+\]'), '')
              .replaceAll(RegExp(r'\[\d+:\d+\]'), '')
              .trim();
          if (text.isNotEmpty) {
            romajiMap[time] = text;
          }
        }
      }
    }

    // 解析YRC格式歌词
    for (final line in yrcLines) {
      if (line.trim().isEmpty) continue;

      try {
        // 跳过元数据行（JSON格式）
        if (line.startsWith('[{')) {
          continue;
        }

        // YRC格式: [startTime,duration](word1Time,word1Duration,0)word1 (word2Time,word2Duration,0)word2
        final lineTimeMatch = RegExp(r'^\[(\d+),(\d+)\]').firstMatch(line);
        if (lineTimeMatch == null) continue;

        final lineStartMs = int.parse(lineTimeMatch.group(1)!);
        final lineDurationMs = int.parse(lineTimeMatch.group(2)!);
        final lineStartTime = Duration(milliseconds: lineStartMs);
        final lineDuration = Duration(milliseconds: lineDurationMs);

        // 提取逐字歌词
        final words = <LyricWord>[];
        final textBuffer = StringBuffer();

        // 匹配所有 (time,duration,0)word 格式
        final wordPattern = RegExp(r'\((\d+),(\d+),\d+\)([^\(]+)');
        final wordMatches = wordPattern.allMatches(line);

        for (final match in wordMatches) {
          final wordStartMs = int.parse(match.group(1)!);
          final wordDurationMs = int.parse(match.group(2)!); // 持续时间，单位毫秒
          final wordText = match.group(3)!; // 保留空格，不使用 trim()

          if (wordText.isNotEmpty) {
            // YRC 格式中，word startTime 和 duration 都是毫秒
            words.add(
              LyricWord(
                startTime: Duration(milliseconds: wordStartMs),
                duration: Duration(milliseconds: wordDurationMs),
                text: wordText,
              ),
            );
            textBuffer.write(wordText);
          }
        }

        final fullText = textBuffer.toString().trim();
        if (fullText.isNotEmpty) {
          lines.add(
            LyricLine(
              startTime: lineStartTime,
              text: fullText,
              translation: translationMap[lineStartTime],
              words: words.isNotEmpty ? words : null,
              lineDuration: lineDuration,
              romanization: romajiMap[lineStartTime],
            ),
          );
        }
      } catch (e) {
        // 解析失败，跳过该行
        debugPrint('YRC解析失败: $line, 错误: $e');
        continue;
      }
    }

    // 按时间排序
    lines.sort((a, b) => a.startTime.compareTo(b.startTime));

    // 调试日志：确认解析了多少行逐字歌词
    final wordsCount = lines.where((l) => l.hasWordByWord).length;
    debugPrint('[YRC解析] 总行数: ${lines.length}, 包含逐字数据: $wordsCount行');

    return lines;
  }

  /// 解析网易云音乐 LRC 格式歌词
  /// [translation] - 普通翻译歌词 (tlyric)
  /// [yrcLyric] - YRC 逐字歌词
  /// [yrcTranslation] - YRC 对应的翻译歌词 (ytlrc)，时间戳与 YRC 匹配
  /// [romaji] - 行级罗马音歌词 (romalrc)
  static List<LyricLine> parseNeteaseLyric(
    String lyric, {
    String? translation,
    String? yrcLyric,
    String? yrcTranslation,
    String? romaji,
  }) {
    // 如果有YRC逐字歌词，优先使用
    if (yrcLyric != null && yrcLyric.isNotEmpty) {
      // 优先使用 ytlrc（时间戳与 YRC 匹配），否则回退到 tlyric
      final effectiveTranslation =
          (yrcTranslation != null && yrcTranslation.isNotEmpty)
          ? yrcTranslation
          : translation;
      final yrcLines = parseNeteaseYrcLyric(
        yrcLyric,
        translation: effectiveTranslation,
        romaji: romaji,
      );
      if (yrcLines.isNotEmpty) {
        return yrcLines;
      }
    }

    // 否则使用普通LRC格式
    if (lyric.isEmpty) return [];

    final lines = <LyricLine>[];
    final lyricLines = lyric.split('\n');

    // 解析翻译歌词（如果有）
    final Map<Duration, String> translationMap = {};
    if (translation != null && translation.isNotEmpty) {
      final translationLines = translation.split('\n');
      for (final line in translationLines) {
        final time = LyricLine.parseTime(line);
        if (time != null) {
          // 去除时间戳，兼容 [mm:ss.xx] / [mm:ss.xxx] / [mm:ss:SS]
          final text = line
              .replaceAll(RegExp(r'\[\d+:\d+\.\d+\]'), '')
              .replaceAll(RegExp(r'\[\d+:\d+:\d+\]'), '')
              .replaceAll(RegExp(r'\[\d+:\d+\]'), '')
              .trim();
          if (text.isNotEmpty) {
            translationMap[time] = text;
          }
        }
      }
    }

    // 解析罗马音歌词（如果有，与翻译同构按时间戳匹配）
    final Map<Duration, String> romajiMap = {};
    if (romaji != null && romaji.isNotEmpty) {
      final romajiLines = romaji.split('\n');
      for (final line in romajiLines) {
        final time = LyricLine.parseTime(line);
        if (time != null) {
          final text = line
              .replaceAll(RegExp(r'\[\d+:\d+\.\d+\]'), '')
              .replaceAll(RegExp(r'\[\d+:\d+:\d+\]'), '')
              .replaceAll(RegExp(r'\[\d+:\d+\]'), '')
              .trim();
          if (text.isNotEmpty) {
            romajiMap[time] = text;
          }
        }
      }
    }

    // 解析原歌词
    for (final line in lyricLines) {
      final time = LyricLine.parseTime(line);
      if (time != null) {
        // 去除时间戳，兼容多种格式
        final text = line
            .replaceAll(RegExp(r'\[\d+:\d+\.\d+\]'), '')
            .replaceAll(RegExp(r'\[\d+:\d+:\d+\]'), '')
            .replaceAll(RegExp(r'\[\d+:\d+\]'), '')
            .trim();
        if (text.isNotEmpty) {
          lines.add(
            LyricLine(
              startTime: time,
              text: text,
              translation: translationMap[time],
              romanization: romajiMap[time],
            ),
          );
        }
      }
    }

    // 按时间排序
    lines.sort((a, b) => a.startTime.compareTo(b.startTime));

    return lines;
  }

  /// 解析 QQ 音乐 QRC 格式逐字歌词
  /// QRC格式示例: [0,354]Tiny (0,27)Giant (27,27)小(55,27)巨(82,27)星
  /// 格式与网易云 YRC 相同: [lineStart,lineDuration]word (wordStart,wordDur,0)text
  static List<LyricLine> parseQQQrcLyric(
    String qrcLyric, {
    String? translation,
    String? romaji,
  }) {
    if (qrcLyric.isEmpty) return [];

    final lines = <LyricLine>[];
    final qrcLines = qrcLyric.split('\n');

    // 解析翻译歌词（如果有）
    final Map<Duration, String> translationMap = {};
    if (translation != null && translation.isNotEmpty) {
      final translationLines = translation.split('\n');
      for (final line in translationLines) {
        final time = LyricLine.parseTime(line);
        if (time != null) {
          final text = line
              .replaceAll(RegExp(r'\[\d+:\d+\.\d+\]'), '')
              .replaceAll(RegExp(r'\[\d+:\d+:\d+\]'), '')
              .replaceAll(RegExp(r'\[\d+:\d+\]'), '')
              .trim();
          if (text.isNotEmpty) {
            translationMap[time] = text;
          }
        }
      }
    }

    // 解析罗马音歌词（如果有，与翻译同构按时间戳匹配）
    final Map<Duration, String> romajiMap = {};
    if (romaji != null && romaji.isNotEmpty) {
      final romajiLines = romaji.split('\n');
      for (final line in romajiLines) {
        final time = LyricLine.parseTime(line);
        if (time != null) {
          final text = line
              .replaceAll(RegExp(r'\[\d+:\d+\.\d+\]'), '')
              .replaceAll(RegExp(r'\[\d+:\d+:\d+\]'), '')
              .replaceAll(RegExp(r'\[\d+:\d+\]'), '')
              .trim();
          if (text.isNotEmpty) {
            romajiMap[time] = text;
          }
        }
      }
    }

    // 解析 QRC 格式歌词
    for (final line in qrcLines) {
      if (line.trim().isEmpty) continue;

      try {
        // 跳过元数据行（如 [ti:xxx], [ar:xxx] 等）
        if (line.startsWith('[ti:') ||
            line.startsWith('[ar:') ||
            line.startsWith('[al:') ||
            line.startsWith('[by:') ||
            line.startsWith('[offset:')) {
          continue;
        }

        // QRC格式: [startTime,duration]word1 (wordStart,wordDur,0)word2
        final lineTimeMatch = RegExp(r'^\[(\d+),(\d+)\]').firstMatch(line);
        if (lineTimeMatch == null) continue;

        final lineStartMs = int.parse(lineTimeMatch.group(1)!);
        final lineDurationMs = int.parse(lineTimeMatch.group(2)!);
        final lineStartTime = Duration(milliseconds: lineStartMs);
        final lineDuration = Duration(milliseconds: lineDurationMs);

        // 提取逐字歌词
        final words = <LyricWord>[];
        final textBuffer = StringBuffer();

        // 获取时间戳之后的内容
        final contentAfterTimestamp = line.substring(lineTimeMatch.end);

        // QRC 格式修正：字词在前，时间在后
        // 示例: Tiny (0,27)Giant (27,27)小(55,27)巨(82,27)星(109,27)
        // QQ QRC 是「文字(开始,持续)」。少数来源会额外带第三个字段，
        // 因此同时兼容 (start,duration) 与 (start,duration,flag)。
        final wordPattern = RegExp(r'([^\(]+)\((\d+),(\d+)(?:,\d+)?\)');
        final wordMatches = wordPattern.allMatches(contentAfterTimestamp);

        for (final match in wordMatches) {
          final wordText = match.group(1)!;
          final timeValue1 = int.parse(match.group(2)!);
          final wordDurationMs = int.parse(match.group(3)!);

          // 后端解密后的 QQ QRC 与网易 YRC 一样使用绝对毫秒。
          // 不能根据数值大小猜成行内偏移，否则歌曲开头的前几行会被重复
          // 加上 lineStartMs，导致填充动画整体滞后。
          final wordStartTime = Duration(milliseconds: timeValue1);

          if (wordText.isNotEmpty) {
            words.add(
              LyricWord(
                startTime: wordStartTime,
                duration: Duration(milliseconds: wordDurationMs),
                text: wordText,
              ),
            );
            textBuffer.write(wordText);
          }
        }

        // 如果正则没匹配到任何逐字（可能是只有文本），保留整行文本
        if (words.isEmpty) {
          textBuffer.write(
            contentAfterTimestamp.replaceAll(
              RegExp(r'\(\d+,\d+(?:,\d+)?\)'),
              '',
            ),
          );
        }

        final fullText = textBuffer.toString().trim();
        if (fullText.isNotEmpty) {
          lines.add(
            LyricLine(
              startTime: lineStartTime,
              text: fullText,
              translation: translationMap[lineStartTime],
              words: words.isNotEmpty ? words : null,
              lineDuration: lineDuration,
              romanization: romajiMap[lineStartTime],
            ),
          );
        }
      } catch (e) {
        // 解析失败，跳过该行
        debugPrint('QRC解析失败: $line, 错误: $e');
        continue;
      }
    }

    // 按时间排序
    lines.sort((a, b) => a.startTime.compareTo(b.startTime));

    // 调试日志
    final wordsCount = lines.where((l) => l.hasWordByWord).length;
    debugPrint('[QRC解析] 总行数: ${lines.length}, 包含逐字数据: $wordsCount行');

    return lines;
  }

  /// 解析 QQ 音乐歌词
  /// [translation] - 普通翻译歌词
  /// [qrcLyric] - QRC 逐字歌词
  /// [qrcTranslation] - QRC 对应的翻译歌词
  /// [romaji] - 行级罗马音歌词（由后端从 qrcRoma 降级而来）
  static List<LyricLine> parseQQLyric(
    String lyric, {
    String? translation,
    String? qrcLyric,
    String? qrcTranslation,
    String? romaji,
  }) {
    // 如果有 QRC 逐字歌词，优先使用
    if (qrcLyric != null && qrcLyric.isNotEmpty) {
      // 优先使用 qrcTranslation（时间戳与 QRC 匹配），否则回退到 translation
      final effectiveTranslation =
          (qrcTranslation != null && qrcTranslation.isNotEmpty)
          ? qrcTranslation
          : translation;
      final qrcLines = parseQQQrcLyric(
        qrcLyric,
        translation: effectiveTranslation,
        romaji: romaji,
      );
      if (qrcLines.isNotEmpty) {
        return qrcLines;
      }
    }

    // 否则使用普通 LRC 格式
    return parseNeteaseLyric(lyric, translation: translation, romaji: romaji);
  }

  /// 解析酷狗音乐歌词（可能需要特殊处理）
  static List<LyricLine> parseKugouLyric(String lyric, {String? translation, String? romaji}) {
    // 酷狗音乐格式可能有所不同，预留接口
    // 暂时使用相同解析方式
    return parseNeteaseLyric(lyric, translation: translation, romaji: romaji);
  }

  /// 根据当前播放时间查找当前歌词行索引
  static int findCurrentLineIndex(
    List<LyricLine> lyrics,
    Duration currentTime,
  ) {
    if (lyrics.isEmpty) return -1;

    for (int i = lyrics.length - 1; i >= 0; i--) {
      if (currentTime >= lyrics[i].startTime) {
        return i;
      }
    }

    return -1;
  }

  /// 获取当前显示的歌词（带前后几行）
  static List<LyricLine> getCurrentDisplayLines(
    List<LyricLine> lyrics,
    int currentIndex, {
    int beforeCount = 3,
    int afterCount = 5,
  }) {
    if (lyrics.isEmpty || currentIndex < 0) return [];

    final startIndex = (currentIndex - beforeCount).clamp(0, lyrics.length);
    final endIndex = (currentIndex + afterCount + 1).clamp(0, lyrics.length);

    return lyrics.sublist(startIndex, endIndex);
  }
}
