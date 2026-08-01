import 'package:cyrene_music_reborn/features/player/amll/core/lyric_types.dart';
import 'package:cyrene_music_reborn/features/player/amll/core/optimize_lyric.dart';
import 'package:flutter_test/flutter_test.dart';

AmllLyricWord w(String text, int start, int end) =>
    AmllLyricWord(word: text, startTime: start, endTime: end);

AmllLyricLine line(
  List<AmllLyricWord> words, {
  int? start,
  int? end,
  bool isBG = false,
  bool isDuet = false,
}) => AmllLyricLine(
  words: words,
  startTime: start ?? (words.isEmpty ? 0 : words.first.startTime),
  endTime: end ?? (words.isEmpty ? 0 : words.last.endTime),
  isBG: isBG,
  isDuet: isDuet,
);

void main() {
  group('normalizeSpaces', () {
    test('把连续空格压成一个', () {
      final lines = [line([w('hello   world', 0, 1000)])];
      optimizeLyricLines(lines, const OptimizeLyricOptions(
        normalizeSpaces: true,
        resetLineTimestamps: false,
        convertExcessiveBackgroundLines: false,
        syncMainAndBackgroundLines: false,
        cleanUnintentionalOverlaps: false,
        tryAdvanceStartTime: false,
      ));
      expect(lines[0].words[0].word, 'hello world');
    });
  });

  group('resetLineTimestamps', () {
    const opts = OptimizeLyricOptions(
      normalizeSpaces: false,
      resetLineTimestamps: true,
      convertExcessiveBackgroundLines: false,
      syncMainAndBackgroundLines: false,
      cleanUnintentionalOverlaps: false,
      tryAdvanceStartTime: false,
    );

    test('单个零时间戳的词从行时间戳取值（TTML 逐行补丁）', () {
      final lines = [
        line([w('整行歌词', 0, 0)], start: 5000, end: 8000),
      ];
      optimizeLyricLines(lines, opts);
      expect(lines[0].words[0].startTime, 5000);
      expect(lines[0].words[0].endTime, 8000);
    });

    test('有字级时间戳时，行时间戳向字级对齐', () {
      final lines = [
        line([w('a', 1200, 1500), w('b', 1500, 2200)], start: 0, end: 9999),
      ];
      optimizeLyricLines(lines, opts);
      expect(lines[0].startTime, 1200);
      expect(lines[0].endTime, 2200);
    });
  });

  group('convertExcessiveBackgroundLines', () {
    test('连续多行背景人声只保留第一行', () {
      final lines = [
        line([w('main', 0, 1000)]),
        line([w('bg1', 0, 1000)], isBG: true),
        line([w('bg2', 1000, 2000)], isBG: true),
        line([w('bg3', 2000, 3000)], isBG: true),
      ];
      optimizeLyricLines(lines, const OptimizeLyricOptions(
        normalizeSpaces: false,
        resetLineTimestamps: false,
        convertExcessiveBackgroundLines: true,
        syncMainAndBackgroundLines: false,
        cleanUnintentionalOverlaps: false,
        tryAdvanceStartTime: false,
      ));
      expect(lines[1].isBG, isTrue);
      expect(lines[2].isBG, isFalse);
      expect(lines[3].isBG, isFalse);
    });
  });

  group('syncMainAndBackgroundLines', () {
    test('主歌词与背景人声取并集时间', () {
      final lines = [
        line([w('main', 1000, 3000)]),
        line([w('bg', 800, 3500)], isBG: true),
      ];
      optimizeLyricLines(lines, const OptimizeLyricOptions(
        normalizeSpaces: false,
        resetLineTimestamps: false,
        convertExcessiveBackgroundLines: false,
        syncMainAndBackgroundLines: true,
        cleanUnintentionalOverlaps: false,
        tryAdvanceStartTime: false,
      ));
      expect(lines[0].startTime, 800);
      expect(lines[0].endTime, 3500);
      expect(lines[1].startTime, 800);
      expect(lines[1].endTime, 3500);
    });
  });

  group('cleanUnintentionalOverlaps', () {
    const opts = OptimizeLyricOptions(
      normalizeSpaces: false,
      resetLineTimestamps: false,
      convertExcessiveBackgroundLines: false,
      syncMainAndBackgroundLines: false,
      cleanUnintentionalOverlaps: true,
      tryAdvanceStartTime: false,
    );

    test('微小重叠被截断到下一行开始', () {
      final lines = [
        line([w('a', 0, 2050)]),
        line([w('b', 2000, 5000)]),
      ];
      optimizeLyricLines(lines, opts);
      expect(lines[0].endTime, 2000);
    });

    test('刻意的大幅重叠被保留', () {
      // 重叠 1000ms > 100ms，且 > 下一行时长 3000 的 10%
      final lines = [
        line([w('a', 0, 3000)]),
        line([w('b', 2000, 5000)]),
      ];
      optimizeLyricLines(lines, opts);
      expect(lines[0].endTime, 3000);
    });

    test('截断会同步应用到附属的背景人声行', () {
      final lines = [
        line([w('a', 0, 2050)]),
        line([w('a-bg', 0, 2050)], isBG: true),
        line([w('b', 2000, 5000)]),
      ];
      optimizeLyricLines(lines, opts);
      expect(lines[0].endTime, 2000);
      expect(lines[1].endTime, 2000);
    });
  });

  group('tryAdvanceStartTime', () {
    const opts = OptimizeLyricOptions(
      normalizeSpaces: false,
      resetLineTimestamps: false,
      convertExcessiveBackgroundLines: false,
      syncMainAndBackgroundLines: false,
      cleanUnintentionalOverlaps: false,
      tryAdvanceStartTime: true,
    );

    test('有充足空档时提前 600ms', () {
      final lines = [
        line([w('a', 0, 2000)]),
        line([w('b', 10000, 12000)]),
      ];
      optimizeLyricLines(lines, opts);
      expect(lines[1].startTime, 9400);
    });

    test('首行也会提前，但不会早于 0', () {
      final lines = [line([w('a', 300, 2000)])];
      optimizeLyricLines(lines, opts);
      expect(lines[0].startTime, 0);
    });

    test('提前量不会越过上一行的安全边界', () {
      // 上一行 0..2000，本行 2100 开始，提前 600 会到 1500，
      // 但安全边界是上一组结束 2000，所以只能到 2000
      final lines = [
        line([w('a', 0, 2000)]),
        line([w('b', 2100, 4000)]),
      ];
      optimizeLyricLines(lines, opts);
      expect(lines[1].startTime, 2000);
    });

    test('原本就重叠时退化为上一行时长的 30% 边界', () {
      // 上一行 0..3000（时长 3000），本行 2000 开始已重叠，
      // 退化边界 = 0 + 3000*0.3 = 900，目标 2000-400 = 1600 > 900，取 1600
      final lines = [
        line([w('a', 0, 3000)]),
        line([w('b', 2000, 5000)]),
      ];
      optimizeLyricLines(lines, opts);
      expect(lines[1].startTime, 1600);
    });

    test('背景人声行跟随主歌词行提前', () {
      final lines = [
        line([w('a', 0, 2000)]),
        line([w('b', 10000, 12000)]),
        line([w('b-bg', 10000, 12000)], isBG: true),
      ];
      optimizeLyricLines(lines, opts);
      expect(lines[1].startTime, 9400);
      expect(lines[2].startTime, 9400);
    });
  });

  group('cloneLyricLines', () {
    test('深拷贝后优化不污染原数据', () {
      final original = [line([w('hello   world', 500, 2000)])];
      final copy = cloneLyricLines(original);
      optimizeLyricLines(copy);

      expect(original[0].words[0].word, 'hello   world');
      expect(original[0].startTime, 500);
      expect(copy[0].words[0].word, 'hello world');
    });
  });
}
