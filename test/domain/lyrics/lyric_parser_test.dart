import 'package:cyrene_music_reborn/domain/lyrics/lyric_parser.dart';
import 'package:cyrene_music_reborn/domain/lyrics/lyric_timeline.dart';
import 'package:cyrene_music_reborn/domain/lyrics/lyric_timing.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = LyricParser(introDelay: Duration.zero);

  group('LyricParser', () {
    test('解析 LRC、多时间标签、偏移和翻译', () {
      final lines = parser.parse(
        source: MusicSource.netease,
        lyric: '[offset:100]\n[00:01.20][00:03.00]第一句\n[00:05]第二句',
        translation: '[00:01.25]first\n[00:05.10]second',
      );

      expect(lines.map((line) => line.text), ['第一句', '第一句', '第二句']);
      expect(lines.first.start, const Duration(milliseconds: 1300));
      expect(lines.first.end, const Duration(milliseconds: 3100));
      expect(lines.first.translation, 'first');
      expect(lines.last.translation, 'second');
    });

    test('解析网易云 YRC 逐字歌词与逐字翻译', () {
      final lines = parser.parse(
        source: MusicSource.netease,
        yrc: '[1000,500](1000,200,0)你(1200,300,0)好',
        verbatimTranslation: '[00:01.00]hello',
      );

      expect(lines, hasLength(1));
      expect(lines.single.isVerbatim, isTrue);
      expect(lines.single.text, '你好');
      expect(lines.single.words.first.start, const Duration(seconds: 1));
      expect(lines.single.words.last.end, const Duration(milliseconds: 1500));
      expect(lines.single.translation, 'hello');
    });

    test('解析 QQ QRC 与汽水逐字格式', () {
      final qqLines = parser.parse(
        source: MusicSource.qq,
        yrc: '[1000,500]你(1000,200)好(1200,300)',
      );
      final qishuiLines = parser.parse(
        source: MusicSource.qishui,
        yrc: '[1000,500]<0,200,0>你<200,300,0>好',
      );

      expect(qqLines.single.text, '你好');
      expect(
        qqLines.single.words.last.start,
        const Duration(milliseconds: 1200),
      );
      expect(qishuiLines.single.words.first.start, const Duration(seconds: 1));
      expect(
        qishuiLines.single.words.last.end,
        const Duration(milliseconds: 1500),
      );
    });
  });

  group('4 秒歌词时序约束', () {
    test('默认解析时间前移 4 秒，查询和 seek 对称补偿', () {
      final lines = const LyricParser().parse(
        source: MusicSource.netease,
        lyric: '[00:01.00]第一句',
      );

      expect(lyricIntroDelay, const Duration(seconds: 4));
      expect(lines.single.start, const Duration(seconds: 5));
      expect(
        lyricLookupPosition(const Duration(seconds: 1)),
        lines.single.start,
      );
      expect(
        playbackPositionForLyric(lines.single.start),
        const Duration(seconds: 1),
      );
    });

    test('seek 到前奏偏移之前时限制为零', () {
      expect(
        playbackPositionForLyric(const Duration(seconds: 2)),
        Duration.zero,
      );
    });

    test('YRC、QRC 与汽水逐字时间统一前移 4 秒', () {
      final netease = const LyricParser().parse(
        source: MusicSource.netease,
        yrc: '[1000,500](1000,500,0)你',
      );
      final qq = const LyricParser().parse(
        source: MusicSource.qq,
        yrc: '[1000,500]你(1000,500)',
      );
      final qishui = const LyricParser().parse(
        source: MusicSource.qishui,
        yrc: '[1000,500]<0,500,0>你',
      );

      for (final lines in [netease, qq, qishui]) {
        expect(lines.single.start, const Duration(seconds: 5));
        expect(lines.single.words.single.start, const Duration(seconds: 5));
      }
    });
  });

  test('LyricTimeline 二分定位当前行和逐字索引', () {
    final lines = parser.parse(
      source: MusicSource.netease,
      yrc: '[1000,500](1000,200,0)你(1200,300,0)好\n[2000,400](2000,400,0)呀',
    );
    final timeline = LyricTimeline(lines);

    expect(timeline.activeLineIndexAt(const Duration(milliseconds: 1100)), 0);
    expect(timeline.activeWordIndexAt(const Duration(milliseconds: 1100)), 0);
    expect(timeline.activeWordIndexAt(const Duration(milliseconds: 1300)), 1);
    expect(timeline.activeLineIndexAt(const Duration(milliseconds: 1600)), -1);
    expect(timeline.activeLineIndexAt(const Duration(milliseconds: 2100)), 1);
  });
}
