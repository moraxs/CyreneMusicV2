import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyrene_music_reborn/features/player/amll_v2/amll_v2_lyric_view.dart';
import 'package:cyrene_music_reborn/features/player/amll_v2/core/interfaces.dart';
import 'package:cyrene_music_reborn/features/player/amll_v2/core/lyric_split_words.dart';
import 'package:cyrene_music_reborn/features/player/amll_v2/player/lyric_player.dart';
import 'package:cyrene_music_reborn/features/player/amll_v2/render/metrics.dart';
import 'package:cyrene_music_reborn/features/player/amll_v2/render/word_animations.dart';

V2LyricWord _w(String word, int start, int end) =>
    V2LyricWord(word: word, startTime: start, endTime: end);

List<V2LyricLine> _lines() => <V2LyricLine>[
  V2LyricLine(
    words: [_w('Life ', 0, 500), _w('is ', 500, 1000), _w('sweet', 1000, 2000)],
    startTime: 0,
    endTime: 2000,
    translatedLyric: '生活是甜的',
  ),
  V2LyricLine(
    words: [_w('So ', 3000, 3400), _w('long', 3400, 5000)],
    startTime: 3000,
    endTime: 5000,
  ),
];

void main() {
  group('chunkAndSplitLyricWords', () {
    test('按空格分组，连写词并成一组', () {
      // 对应 lyric-split-words.ts 文档注释里的例子
      final chunks = chunkAndSplitLyricWords([
        _w('Life', 0, 100),
        _w(' ', 100, 100),
        _w('is', 100, 200),
        _w(' a', 200, 300),
        _w(' su', 300, 400),
        _w('gar so', 400, 500),
        _w('sweet', 500, 600),
      ]);
      // 分组只重排不丢词：拼回去的可见字符必须与原文一致
      expect(chunks, isNotEmpty);
      final texts = chunks
          .map(
            (c) => c.isGroup ? c.words.map((w) => w.word).join() : c.word!.word,
          )
          .join();
      expect(texts.replaceAll(' ', ''), 'Lifeisasugarsosweet');
      // 「su」「gar」之间没有空格，必须并成一个连写组
      expect(chunks.any((c) => c.isGroup && c.words.length > 1), isTrue);
    });

    test('CJK 逐字成组', () {
      final chunks = chunkAndSplitLyricWords([
        _w('你', 0, 100),
        _w('好', 100, 200),
      ]);
      expect(chunks.length, 2);
      expect(isCJK('你'), isTrue);
      expect(isCJK('a'), isFalse);
    });
  });

  group('遮罩关键帧', () {
    test('起点全暗、终点全亮，且单调不回退', () {
      final words = <V2MaskWordMetric>[
        const V2MaskWordMetric(
          width: 100,
          padding: 20,
          startTime: 0,
          endTime: 1000,
        ),
        const V2MaskWordMetric(
          width: 80,
          padding: 20,
          startTime: 1000,
          endTime: 2000,
        ),
      ];
      final frames = buildMaskFrames(
        words: words,
        index: 0,
        lineStartTime: 0,
        totalFadeDuration: 2000,
        fadeWidth: 30,
      );
      expect(frames, isNotEmpty);
      final minOffset = -(100 + 20 * 2 + 30);
      expect(evalMaskFrames(frames, 0), closeTo(minOffset, 0.001));
      expect(evalMaskFrames(frames, 1), closeTo(0, 0.001));
      var last = double.negativeInfinity;
      for (var i = 0; i <= 100; i++) {
        final v = evalMaskFrames(frames, i / 100);
        expect(v, greaterThanOrEqualTo(last - 1e-9));
        last = v;
      }
    });
  });

  group('V2CssMetrics', () {
    test('字号照抄 index.css 的 max() 公式', () {
      // 窄屏：max(8vw, 12px)
      final narrow = V2CssMetrics(
        playerSize: const Size(400, 800),
        windowSize: const Size(400, 800),
        hasDuetLine: false,
      );
      expect(narrow.fontSize, 32); // 8vw = 8 * 4
      // 宽屏：max(max(5vh, 2.5vw), 12px)
      final wide = V2CssMetrics(
        playerSize: const Size(1600, 900),
        windowSize: const Size(1600, 900),
        hasDuetLine: false,
      );
      expect(wide.fontSize, 45); // 5vh = 45, 2.5vw = 40

      // .lyricBgLine { font-size: max(1em * 0.7, 10px) }
      expect(narrow.bgFontSize, closeTo(32 * 0.7, 1e-9));
      // 窄屏（<=500px）主行左右内边距是 20px
      expect(narrow.linePaddingX(false), 20);
      // 宽屏是 1em
      expect(wide.linePaddingX(false), 45);
    });
  });

  group('V2LyricPlayer', () {
    test('setLyricLines 会把行开始时间提早最多一秒', () {
      final player = V2LyricPlayer()
        ..size = const Size(400, 800)
        ..windowHeight = 800
        ..windowWidth = 400;
      player.setLyricLines(_lines());
      // 第一行没有上一行，直接 max(0, start - 1000)
      expect(player.processedLines[0].startTime, 0);
      // 第二行被上一行的 endTime 兜住
      expect(player.processedLines[1].startTime, 2000);
      // 原始数组不受影响
      expect(player.currentLyricLines[1].startTime, 3000);
      expect(player.isNonDynamic, isFalse);
    });

    test('从未播到的行，遮罩时钟不得推进（暂停时整屏高亮的根因）', () {
      final player = V2LyricPlayer()
        ..size = const Size(400, 800)
        ..windowHeight = 800
        ..windowWidth = 400;
      player.setLyricLines(_lines());

      // setLyricLines 内部会 setCurrentTime(0, true)，第一行区间含 0 故已被
      // enable；第二行（处理后 [2000, 5000]）没有。
      expect(player.currentLyricLineObjects[0].isEnabled, isTrue);
      expect(player.currentLyricLineObjects[1].isEnabled, isFalse);

      // 空跑 10 秒，期间不喂进度
      for (var i = 0; i < 600; i++) {
        player.update(16.6);
      }
      final future = player.currentLyricLineObjects[1];
      expect(
        future.maskTime,
        0,
        reason: '未 enable 的行对应上游 `ani.pause()`，播放头必须停在 0',
      );
      expect(future.elementTime, 0);
      // 已 enable 的行则应正常推进
      expect(player.currentLyricLineObjects[0].maskTime, greaterThan(0));

      // 播到第二行后，它的时钟才开始走
      player.setCurrentTime(3000, true);
      for (var i = 0; i < 30; i++) {
        player.update(16.6);
      }
      expect(future.isEnabled, isTrue);
      expect(future.maskTime, greaterThan(0));
    });

    test('setCurrentTime 推进缓冲行与 scrollToIndex', () {
      final player = V2LyricPlayer()
        ..size = const Size(400, 800)
        ..windowHeight = 800
        ..windowWidth = 400;
      player.setLyricLines(_lines());
      player.setCurrentTime(1000);
      expect(player.bufferedLines, contains(0));
      expect(player.scrollToIndex, 0);
      player.setCurrentTime(4000);
      expect(player.bufferedLines, contains(1));
      expect(player.scrollToIndex, 1);
    });
  });

  testWidgets('AmllV2LyricView 能布局、逐帧推进并响应点击跳转', (tester) async {
    final position = ValueNotifier<Duration>(Duration.zero);
    Duration? seeked;
    var blankTapped = false;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: SizedBox(
            width: 400,
            height: 800,
            child: AmllV2LyricView(
              lines: _lines(),
              positionListenable: position,
              isPlaying: true,
              onSeek: (d) => seeked = d,
              onTapBlank: () => blankTapped = true,
            ),
          ),
        ),
      ),
    );

    // 首帧完成布局
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);

    // 推进播放进度若干帧，弹簧与时钟都应正常推进而不抛错
    for (var ms = 0; ms <= 4000; ms += 200) {
      position.value = Duration(milliseconds: ms);
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(tester.takeException(), isNull);

    // 点在组件上：命中歌词行则跳转，否则回调空白点击
    await tester.tapAt(const Offset(200, 400));
    await tester.pump();
    expect(
      seeked != null || blankTapped,
      isTrue,
      reason: '点击必须落到 seek 或空白回调之一',
    );

    position.dispose();
  });
}
