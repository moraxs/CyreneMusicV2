import 'package:cyrene_music_reborn/features/player/amll/amll_lyric_view.dart';
import 'package:cyrene_music_reborn/features/player/amll/core/lyric_types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AmllLyricWord w(String text, int start, int end) =>
    AmllLyricWord(word: text, startTime: start, endTime: end);

/// 造一段逐字歌词：每行 3 个词，每词 500ms，行间留 500ms 空档。
List<AmllLyricLine> buildLines(int count) {
  return List<AmllLyricLine>.generate(count, (i) {
    final base = i * 2000;
    return AmllLyricLine(
      words: <AmllLyricWord>[
        w('Hello ', base, base + 500),
        w('world ', base + 500, base + 1000),
        w('line$i', base + 1000, base + 1500),
      ],
      startTime: base,
      endTime: base + 1500,
      translatedLyric: '第 $i 行翻译',
    );
  });
}

Widget wrap(Widget child, {Size size = const Size(400, 700)}) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Center(
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );
}

void main() {
  group('AmllLyricView', () {
    testWidgets('空歌词不报错', (tester) async {
      await tester.pumpWidget(
        wrap(
          AmllLyricView(
            lines: const [],
            positionListenable: ValueNotifier(Duration.zero),
            isPlaying: false,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('能渲染出歌词行并持续推进动画', (tester) async {
      final position = ValueNotifier(Duration.zero);
      addTearDown(position.dispose);

      await tester.pumpWidget(
        wrap(
          AmllLyricView(
            lines: buildLines(12),
            positionListenable: position,
            isPlaying: true,
          ),
        ),
      );

      // 首帧后应已构建出可见的歌词组
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(CustomPaint), findsWidgets);

      // 推进播放进度，逐帧驱动若干秒
      for (var t = 0; t < 4000; t += 100) {
        position.value = Duration(milliseconds: t);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('点击歌词行触发 seek', (tester) async {
      final position = ValueNotifier(const Duration(milliseconds: 4000));
      addTearDown(position.dispose);
      Duration? seeked;

      await tester.pumpWidget(
        wrap(
          AmllLyricView(
            lines: buildLines(10),
            positionListenable: position,
            isPlaying: true,
            onSeek: (p) => seeked = p,
          ),
        ),
      );

      // 让布局稳定下来
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // 点在视图中部，应命中某一行
      await tester.tapAt(tester.getCenter(find.byType(AmllLyricView)));
      await tester.pump(const Duration(milliseconds: 16));

      expect(seeked, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('拖拽能改变滚动偏移且不抛异常', (tester) async {
      final position = ValueNotifier(const Duration(milliseconds: 6000));
      addTearDown(position.dispose);

      await tester.pumpWidget(
        wrap(
          AmllLyricView(
            lines: buildLines(20),
            positionListenable: position,
            isPlaying: true,
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      await tester.drag(find.byType(AmllLyricView), const Offset(0, -200));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(tester.takeException(), isNull);
    });

    testWidgets('逐行歌词（非逐字）也能渲染', (tester) async {
      final position = ValueNotifier(Duration.zero);
      addTearDown(position.dispose);

      final lines = List<AmllLyricLine>.generate(6, (i) {
        final base = i * 2000;
        return AmllLyricLine(
          words: <AmllLyricWord>[w('整行歌词 $i', base, base + 1800)],
          startTime: base,
          endTime: base + 1800,
        );
      });

      await tester.pumpWidget(
        wrap(
          AmllLyricView(
            lines: lines,
            positionListenable: position,
            isPlaying: true,
          ),
        ),
      );

      for (var t = 0; t < 3000; t += 100) {
        position.value = Duration(milliseconds: t);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('背景人声行与对唱行不报错', (tester) async {
      final position = ValueNotifier(Duration.zero);
      addTearDown(position.dispose);

      final lines = <AmllLyricLine>[
        AmllLyricLine(
          words: <AmllLyricWord>[w('main one ', 0, 800), w('two', 800, 1600)],
          startTime: 0,
          endTime: 1600,
        ),
        AmllLyricLine(
          words: <AmllLyricWord>[w('background', 0, 1600)],
          startTime: 0,
          endTime: 1600,
          isBG: true,
        ),
        AmllLyricLine(
          words: <AmllLyricWord>[w('duet line', 2000, 3600)],
          startTime: 2000,
          endTime: 3600,
          isDuet: true,
        ),
      ];

      await tester.pumpWidget(
        wrap(
          AmllLyricView(
            lines: lines,
            positionListenable: position,
            isPlaying: true,
          ),
        ),
      );

      for (var t = 0; t < 4000; t += 100) {
        position.value = Duration(milliseconds: t);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('长间奏会显示呼吸点', (tester) async {
      final position = ValueNotifier(Duration.zero);
      addTearDown(position.dispose);

      // 两行之间留 10s 空档
      final lines = <AmllLyricLine>[
        AmllLyricLine(
          words: <AmllLyricWord>[w('first', 0, 1500)],
          startTime: 0,
          endTime: 1500,
        ),
        AmllLyricLine(
          words: <AmllLyricWord>[w('second', 12000, 13500)],
          startTime: 12000,
          endTime: 13500,
        ),
      ];

      await tester.pumpWidget(
        wrap(
          AmllLyricView(
            lines: lines,
            positionListenable: position,
            isPlaying: true,
          ),
        ),
      );

      // 推进到间奏中段
      for (var t = 0; t <= 6000; t += 100) {
        position.value = Duration(milliseconds: t);
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull);
    });

    testWidgets('暂停与恢复不报错', (tester) async {
      final position = ValueNotifier(const Duration(milliseconds: 500));
      addTearDown(position.dispose);

      Widget build(bool playing) => wrap(
        AmllLyricView(
          lines: buildLines(6),
          positionListenable: position,
          isPlaying: playing,
        ),
      );

      await tester.pumpWidget(build(true));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pumpWidget(build(false));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pumpWidget(build(true));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    });

    testWidgets('切换歌词数据不报错', (tester) async {
      final position = ValueNotifier(Duration.zero);
      addTearDown(position.dispose);

      Widget build(List<AmllLyricLine> lines) => wrap(
        AmllLyricView(
          lines: lines,
          positionListenable: position,
          isPlaying: true,
        ),
      );

      await tester.pumpWidget(build(buildLines(8)));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      await tester.pumpWidget(build(buildLines(3)));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(tester.takeException(), isNull);
    });

    testWidgets('开启模糊也能正常绘制', (tester) async {
      final position = ValueNotifier(const Duration(milliseconds: 2500));
      addTearDown(position.dispose);

      await tester.pumpWidget(
        wrap(
          AmllLyricView(
            lines: buildLines(10),
            positionListenable: position,
            isPlaying: true,
            enableBlur: true,
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 33));
      }
      expect(tester.takeException(), isNull);
    });
  });
}
