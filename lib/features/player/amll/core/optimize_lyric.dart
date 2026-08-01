import 'lyric_types.dart';

/// 规范化歌词中的空格，将多个连续空格替换为一个空格。
void _normalizeSpaces(List<AmllLyricLine> lines) {
  final ws = RegExp(r'\s+');
  for (final line in lines) {
    for (final word in line.words) {
      word.word = word.word.replaceAll(ws, ' ');
    }
  }
}

/// 用字级时间戳校正行级时间戳。
void _resetLineTimestamps(List<AmllLyricLine> lines) {
  for (final line in lines) {
    // 主要是给 TTML 解析器打补丁，其解析逐行歌词时获得的词时间戳均为 0。
    // 如果只有一个词，且该词起止时间均为 0，且行时间戳不全为 0，
    // 则把行时间戳同步给词时间戳。
    if (line.words.length == 1 &&
        line.words[0].startTime == 0 &&
        line.words[0].endTime == 0 &&
        (line.startTime != 0 || line.endTime != 0)) {
      line.words[0].startTime = line.startTime;
      line.words[0].endTime = line.endTime;
    } else if (line.words.isNotEmpty) {
      line.startTime = line.words.first.startTime;
      line.endTime = line.words.last.endTime;
    }
  }
}

/// 把连续的多行背景人声压缩为「单行背景人声 + 主歌词行」的形式。
void _convertExcessiveBackgroundLines(List<AmllLyricLine> lines) {
  var consecutiveBgCount = 0;
  for (final line in lines) {
    if (line.isBG) {
      consecutiveBgCount++;
      if (consecutiveBgCount > 1) {
        line.isBG = false;
      }
    } else {
      consecutiveBgCount = 0;
    }
  }
}

/// 同步主歌词与背景人声的时间：取两者中最早的开始与最晚的结束，应用给双方。
void _syncMainAndBackgroundLines(List<AmllLyricLine> lines) {
  for (var i = lines.length - 1; i >= 0; i--) {
    final line = lines[i];
    if (line.isBG) continue;

    final nextLine = i + 1 < lines.length ? lines[i + 1] : null;
    if (nextLine != null && nextLine.isBG) {
      final allWords = <AmllLyricWord>[
        ...line.words,
        ...nextLine.words,
      ].where((w) => w.word.trim().isNotEmpty).toList();

      if (allWords.isNotEmpty) {
        var minStart = allWords.first.startTime;
        var maxEnd = allWords.first.endTime;
        for (final w in allWords) {
          if (w.startTime < minStart) minStart = w.startTime;
          if (w.endTime > maxEnd) maxEnd = w.endTime;
        }

        final finalStart = [
          minStart,
          line.startTime,
          nextLine.startTime,
        ].reduce((a, b) => a < b ? a : b);
        final finalEnd = [
          maxEnd,
          line.endTime,
          nextLine.endTime,
        ].reduce((a, b) => a > b ? a : b);

        line.startTime = finalStart;
        line.endTime = finalEnd;
        nextLine.startTime = finalStart;
        nextLine.endTime = finalEnd;
      }
    }
  }
}

/// 清洗非刻意的重叠。
///
/// 重叠 > 100ms 且超过下一行时长的 10% 视为刻意重叠而保留，
/// 否则把本行结束时间截断到下一行的开始时间。
void _cleanUnintentionalOverlaps(List<AmllLyricLine> lines) {
  for (var i = 0; i < lines.length - 1; i++) {
    final line = lines[i];
    if (line.isBG) continue;

    var nextMainIndex = i + 1;
    while (nextMainIndex < lines.length && lines[nextMainIndex].isBG) {
      nextMainIndex++;
    }
    if (nextMainIndex >= lines.length) continue;

    final nextLine = lines[nextMainIndex];
    final overlap = line.endTime - nextLine.startTime;
    if (overlap <= 0) continue;

    final nextDuration = nextLine.endTime - nextLine.startTime;
    final percentageThreshold = nextDuration * 0.1;
    final isIntentionalOverlap = overlap > 100 && overlap > percentageThreshold;

    if (!isIntentionalOverlap) {
      line.endTime = nextLine.startTime;
      final attachedBgLine = i + 1 < lines.length ? lines[i + 1] : null;
      if (attachedBgLine != null && attachedBgLine.isBG) {
        attachedBgLine.endTime = nextLine.startTime;
      }
    }
  }
}

/// 尝试让歌词提前最多 600ms 开始；若与上一行重叠，则退化为最多提前 400ms
/// 或上一行时长的 30%。这决定了歌词滚动的「提前量」手感。
void _tryAdvanceStartTime(List<AmllLyricLine> lines) {
  const defaultAdvanceAmount = 600;
  const fallbackAdvanceAmount = 400;
  const fallbackAdvanceRatio = 0.3;

  var prevLineStartTime = 0;
  var prevLineEndTime = 0;
  var prevMainGroupStartTime = 0;
  var prevMainGroupEndTime = 0;
  var hasPrevLine = false;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.isBG) continue;

    final originalStartTime = line.startTime;
    final originalEndTime = line.endTime;

    int targetAdvanceAmount;
    num safeBoundary;

    if (hasPrevLine) {
      final originallyHadGap = originalStartTime >= prevLineEndTime;
      if (originallyHadGap) {
        targetAdvanceAmount = defaultAdvanceAmount;
        safeBoundary = prevMainGroupEndTime;
      } else {
        targetAdvanceAmount = fallbackAdvanceAmount;
        final prevDuration = prevLineEndTime - prevLineStartTime;
        safeBoundary = prevLineStartTime + prevDuration * fallbackAdvanceRatio;
      }
    } else {
      targetAdvanceAmount = defaultAdvanceAmount;
      safeBoundary = 0;
    }

    final targetTime = line.startTime - targetAdvanceAmount;
    final newStartTime = safeBoundary > targetTime
        ? safeBoundary.round()
        : targetTime;

    if (newStartTime < line.startTime) {
      line.startTime = newStartTime;
    }

    final nextLine = i + 1 < lines.length ? lines[i + 1] : null;
    if (nextLine != null && nextLine.isBG) {
      nextLine.startTime = line.startTime;
    }

    if (hasPrevLine) {
      final overlapsPrevGroup =
          originalStartTime < prevMainGroupEndTime &&
          originalEndTime > prevMainGroupStartTime;
      if (overlapsPrevGroup) {
        if (originalStartTime < prevMainGroupStartTime) {
          prevMainGroupStartTime = originalStartTime;
        }
        if (originalEndTime > prevMainGroupEndTime) {
          prevMainGroupEndTime = originalEndTime;
        }
      } else {
        prevMainGroupStartTime = originalStartTime;
        prevMainGroupEndTime = originalEndTime;
      }
    } else {
      prevMainGroupStartTime = originalStartTime;
      prevMainGroupEndTime = originalEndTime;
    }

    prevLineStartTime = originalStartTime;
    prevLineEndTime = originalEndTime;
    hasPrevLine = true;
  }
}

/// 优化歌词行的展示效果。
///
/// 注意会**原地修改**入参，调用前请确保已经深拷贝
/// （见 [cloneLyricLines]）。
void optimizeLyricLines(
  List<AmllLyricLine> lines, [
  OptimizeLyricOptions options = const OptimizeLyricOptions(),
]) {
  if (options.normalizeSpaces) _normalizeSpaces(lines);
  if (options.resetLineTimestamps) _resetLineTimestamps(lines);
  if (options.convertExcessiveBackgroundLines) {
    _convertExcessiveBackgroundLines(lines);
  }
  if (options.syncMainAndBackgroundLines) _syncMainAndBackgroundLines(lines);
  if (options.cleanUnintentionalOverlaps) _cleanUnintentionalOverlaps(lines);
  if (options.tryAdvanceStartTime) _tryAdvanceStartTime(lines);
}
