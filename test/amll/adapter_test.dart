import 'package:cyrene_music_reborn/features/player/amll/amll_adapter.dart';
import 'package:cyrene_music_reborn/features/player/mobile/compat/lyric_line.dart';
import 'package:flutter_test/flutter_test.dart';

LyricWord word(String text, int startMs, int durationMs) => LyricWord(
  text: text,
  startTime: Duration(milliseconds: startMs),
  duration: Duration(milliseconds: durationMs),
);

LyricLine line(
  String text, {
  required int startMs,
  List<LyricWord>? words,
  int? durationMs,
  String? translation,
  bool isBG = false,
  bool isDuet = false,
}) => LyricLine(
  text: text,
  startTime: Duration(milliseconds: startMs),
  words: words,
  lineDuration: durationMs == null
      ? null
      : Duration(milliseconds: durationMs),
  translation: translation,
  isBG: isBG,
  isDuet: isDuet,
);

void main() {
  group('toAmllLyricLines', () {
    test('空输入返回空', () {
      expect(toAmllLyricLines(const []), isEmpty);
    });

    test('逐字歌词保留每个词的时间', () {
      final result = toAmllLyricLines([
        line(
          'Hello world',
          startMs: 1000,
          words: [word('Hello ', 1000, 500), word('world', 1500, 700)],
        ),
      ]);

      expect(result, hasLength(1));
      expect(result[0].words, hasLength(2));
      expect(result[0].words[0].startTime, 1000);
      expect(result[0].words[0].endTime, 1500);
      expect(result[0].words[1].endTime, 2200);
    });

    test('逐字歌词的行结束时间取最后一个词的结束', () {
      final result = toAmllLyricLines([
        line(
          'a b',
          startMs: 0,
          words: [word('a ', 0, 400), word('b', 400, 600)],
        ),
      ]);
      expect(result[0].endTime, 1000);
    });

    test('逐行歌词合成为单个词', () {
      final result = toAmllLyricLines([
        line('整行歌词', startMs: 500, durationMs: 2000),
      ]);
      expect(result[0].words, hasLength(1));
      expect(result[0].words[0].word, '整行歌词');
      expect(result[0].words[0].startTime, 500);
      expect(result[0].words[0].endTime, 2500);
    });

    test('无时长时用下一行的开始时间兜底', () {
      final result = toAmllLyricLines([
        line('first', startMs: 0),
        line('second', startMs: 3000),
      ]);
      expect(result[0].endTime, 3000);
    });

    test('最后一行无时长时用兜底时长', () {
      final result = toAmllLyricLines([line('only', startMs: 1000)]);
      expect(
        result[0].endTime,
        1000 + kFallbackLineDuration.inMilliseconds,
      );
    });

    test('翻译按开关传递', () {
      final input = [line('text', startMs: 0, translation: '翻译')];

      expect(toAmllLyricLines(input)[0].translatedLyric, '翻译');
      expect(
        toAmllLyricLines(input, showTranslation: false)[0].translatedLyric,
        '',
      );
    });

    test('翻译为 null 时转成空串', () {
      final result = toAmllLyricLines([line('text', startMs: 0)]);
      expect(result[0].translatedLyric, '');
    });

    test('背景人声与对唱标记被保留', () {
      final result = toAmllLyricLines([
        line('main', startMs: 0, durationMs: 1000),
        line('bg', startMs: 0, durationMs: 1000, isBG: true),
        line('duet', startMs: 2000, durationMs: 1000, isDuet: true),
      ]);
      expect(result[0].isBG, isFalse);
      expect(result[1].isBG, isTrue);
      expect(result[2].isDuet, isTrue);
    });

    test('词级音译与不雅标记被保留', () {
      final result = toAmllLyricLines([
        LyricLine(
          text: '本気',
          startTime: Duration.zero,
          words: [
            LyricWord(
              text: '本気',
              startTime: Duration.zero,
              duration: const Duration(milliseconds: 1000),
              romanWord: 'honki',
              obscene: true,
            ),
          ],
        ),
      ]);
      expect(result[0].words[0].romanWord, 'honki');
      expect(result[0].words[0].obscene, isTrue);
    });

    test('行级音译按开关传递', () {
      final input = [
        LyricLine(
          text: 'text',
          startTime: Duration.zero,
          lineDuration: const Duration(seconds: 1),
          romanization: 'romaji',
        ),
      ];
      expect(toAmllLyricLines(input)[0].romanLyric, 'romaji');
      expect(
        toAmllLyricLines(input, showRomanization: false)[0].romanLyric,
        '',
      );
    });

    test('下一行开始时间早于本行时跳过，继续向后找', () {
      // 乱序/重复时间戳的脏数据不应导致 endTime < startTime
      final result = toAmllLyricLines([
        line('a', startMs: 5000),
        line('b', startMs: 5000),
        line('c', startMs: 8000),
      ]);
      expect(result[0].endTime, 8000);
      expect(result[0].endTime, greaterThan(result[0].startTime));
    });

    test('所有行的结束时间都不早于开始时间', () {
      final result = toAmllLyricLines([
        line('a', startMs: 0, words: [word('a', 0, 0)]),
        line('b', startMs: 1000, durationMs: 0),
        line('c', startMs: 2000),
      ]);
      for (final l in result) {
        expect(l.endTime, greaterThanOrEqualTo(l.startTime));
      }
    });
  });
}
