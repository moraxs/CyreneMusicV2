import 'package:cyrene_music_reborn/features/player/mobile/compat/lyric_line.dart';
import 'package:cyrene_music_reborn/features/player/super_cyrene/super_cyrene_lyric_timing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SuperCyrene evenly times a plain lyric line', () {
    final words = buildSuperCyreneWordTimeline(
      line: LyricLine(startTime: const Duration(seconds: 10), text: '你 好呀'),
      lineEnd: const Duration(seconds: 13),
    );

    expect(words.map((word) => word.text), ['你 ', '好', '呀']);
    expect(words.map((word) => word.startTime), [10.0, 11.0, 12.0]);
    expect(words.map((word) => word.endTime), [11.0, 12.0, 13.0]);
  });

  test('SuperCyrene replaces a whole-line backend placeholder', () {
    final words = buildSuperCyreneWordTimeline(
      line: LyricLine(
        startTime: const Duration(seconds: 20),
        text: '天地',
        words: [
          LyricWord(
            startTime: const Duration(seconds: 20),
            duration: const Duration(seconds: 4),
            text: '天地',
          ),
        ],
      ),
      lineEnd: const Duration(seconds: 24),
    );

    expect(words.map((word) => word.text), ['天', '地']);
    expect(words.map((word) => word.startTime), [20.0, 22.0]);
    expect(words.map((word) => word.endTime), [22.0, 24.0]);
  });

  test('SuperCyrene preserves genuine backend word timing', () {
    final words = buildSuperCyreneWordTimeline(
      line: LyricLine(
        startTime: const Duration(seconds: 30),
        text: '你好',
        words: [
          LyricWord(
            startTime: const Duration(seconds: 30),
            duration: const Duration(milliseconds: 700),
            text: '你',
          ),
          LyricWord(
            startTime: const Duration(milliseconds: 30700),
            duration: const Duration(milliseconds: 1300),
            text: '好',
          ),
        ],
      ),
      lineEnd: const Duration(seconds: 32),
    );

    expect(words.map((word) => word.startTime), [30.0, 30.7]);
    expect(words.map((word) => word.endTime), [30.7, 32.0]);
  });
}
