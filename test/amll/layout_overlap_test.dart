import 'package:cyrene_music_reborn/features/player/amll/amll_lyric_controller.dart';
import 'package:cyrene_music_reborn/features/player/amll/core/lyric_types.dart';
import 'package:cyrene_music_reborn/features/player/amll/core/spring.dart';
import 'package:cyrene_music_reborn/features/player/amll/render/lyric_group.dart';
import 'package:cyrene_music_reborn/features/player/amll/render/lyric_line_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AmllLyricWord w(String text, int start, int end) =>
    AmllLyricWord(word: text, startTime: start, endTime: end);

/// 造带中文翻译的逐字歌词。
List<AmllLyricLine> linesWithTranslation(int count, {String? translation}) {
  return List<AmllLyricLine>.generate(count, (i) {
    final base = i * 3000;
    return AmllLyricLine(
      words: <AmllLyricWord>[
        w('Never ', base, base + 600),
        w('gonna ', base + 600, base + 1200),
        w('give you up', base + 1200, base + 2400),
      ],
      startTime: base,
      endTime: base + 2400,
      translatedLyric: translation ?? '永远不会放弃你 第$i行',
    );
  });
}

const TextStyle kStyle = TextStyle(fontSize: 32, height: 1.2);

AmllLyricController buildController(
  List<AmllLyricLine> lines, {
  Size size = const Size(400, 700),
  double contentWidth = 360,
}) {
  final controller = AmllLyricController()
    ..setViewport(size: size, textStyle: kStyle, contentMaxWidth: contentWidth);
  controller.setLyricLines(lines);
  controller.primeVisibleGroups();
  // 推进几帧让弹簧就位
  for (var i = 0; i < 5; i++) {
    controller.update(16);
  }
  return controller;
}

void main() {
  group('整行歌词高亮时序', () {
    test('新活跃行移动到目标位置后才进入渐变高亮', () {
      final line = AmllLyricLine(
        words: <AmllLyricWord>[w('整行歌词', 0, 2000)],
        startTime: 0,
        endTime: 2000,
      );
      final lineView = AmllLyricLineView(line: line, isBG: false);
      final group = AmllLyricGroup(mainLine: lineView, initialPosY: 300)
        ..updatePosYSpringParams(
          const SpringParams(mass: 0.9, damping: 15, stiffness: 90),
        )
        ..setTransform(
          top: 100,
          force: false,
          delay: 0,
          isActive: true,
          opacity: 0.85,
          blur: 0,
          enableSpring: true,
          enableScale: true,
          isPlaying: true,
          isNonDynamic: true,
          alwaysPostpositionBackground: false,
        );

      expect(lineView.renderMode, LyricLineRenderMode.solid);

      for (var i = 0; i < 300; i++) {
        group.update(1 / 60, enableSpring: true);
        if (lineView.renderMode == LyricLineRenderMode.gradient) break;
      }

      expect(group.currentTop, closeTo(100, 1));
      expect(lineView.renderMode, LyricLineRenderMode.gradient);
    });

    test('逐字歌词保持即时渐变，不等待纵向移动', () {
      final line = AmllLyricLine(
        words: <AmllLyricWord>[w('逐字', 0, 1000), w('歌词', 1000, 2000)],
        startTime: 0,
        endTime: 2000,
      );
      final lineView = AmllLyricLineView(line: line, isBG: false);
      final group = AmllLyricGroup(mainLine: lineView, initialPosY: 300)
        ..setTransform(
          top: 100,
          force: false,
          delay: 0,
          isActive: true,
          opacity: 0.85,
          blur: 0,
          enableSpring: true,
          enableScale: true,
          isPlaying: true,
          isNonDynamic: false,
          alwaysPostpositionBackground: false,
        );

      expect(lineView.renderMode, LyricLineRenderMode.gradient);
    });
  });

  group('组高度与重叠', () {
    test('有翻译时相邻歌词行不重叠', () {
      final controller = buildController(linesWithTranslation(8));
      addTearDown(controller.dispose);

      final groups = controller.groups;
      for (var i = 0; i < groups.length - 1; i++) {
        final top = groups[i].top;
        final height = controller.heightOf(groups[i]);
        final nextTop = groups[i + 1].top;

        expect(
          nextTop,
          greaterThanOrEqualTo(top + height - 0.5),
          reason: '第 $i 行（含翻译）底部不应越过第 ${i + 1} 行的顶部',
        );
      }
    });

    test('组高度包含翻译行的高度', () {
      final withTrans = buildController(linesWithTranslation(4));
      addTearDown(withTrans.dispose);

      final noTrans = buildController(
        List<AmllLyricLine>.generate(4, (i) {
          final base = i * 3000;
          return AmllLyricLine(
            words: <AmllLyricWord>[
              w('Never gonna give you up', base, base + 2400),
            ],
            startTime: base,
            endTime: base + 2400,
          );
        }),
      );
      addTearDown(noTrans.dispose);

      expect(
        withTrans.heightOf(withTrans.groups.first),
        greaterThan(noTrans.heightOf(noTrans.groups.first)),
        reason: '带翻译的行必须更高',
      );
    });

    test('多行翻译（长文本折行）也不重叠', () {
      final controller = buildController(
        linesWithTranslation(
          6,
          translation: '这是一段很长的中文翻译文本，长到一定会在窄屏上折成两行甚至三行来显示',
        ),
        size: const Size(360, 640),
        contentWidth: 320,
      );
      addTearDown(controller.dispose);

      final groups = controller.groups;
      for (var i = 0; i < groups.length - 1; i++) {
        expect(
          groups[i + 1].top,
          greaterThanOrEqualTo(
            groups[i].top + controller.heightOf(groups[i]) - 0.5,
          ),
          reason: '第 $i 行的长翻译不应压住下一行',
        );
      }
    });

    test('关闭翻译后行高回落', () {
      final controller = buildController(linesWithTranslation(4));
      addTearDown(controller.dispose);

      final withTrans = controller.heightOf(controller.groups.first);

      controller
        ..setSubLineVisibility(showTranslation: false, showRoman: false)
        ..primeVisibleGroups();
      for (var i = 0; i < 5; i++) {
        controller.update(16);
      }

      expect(
        controller.heightOf(controller.groups.first),
        lessThan(withTrans),
        reason: '关闭翻译后该行应变矮',
      );
    });

    test('主歌词折行时高度随之增加', () {
      AmllLyricController make(String text, double width) =>
          buildController(<AmllLyricLine>[
            AmllLyricLine(
              words: <AmllLyricWord>[w(text, 0, 2000)],
              startTime: 0,
              endTime: 2000,
            ),
          ], contentWidth: width);

      final narrow = make(
        'this is a fairly long lyric line that will certainly wrap',
        200,
      );
      addTearDown(narrow.dispose);
      final wide = make('short', 200);
      addTearDown(wide.dispose);

      expect(
        narrow.heightOf(narrow.groups.first),
        greaterThan(wide.heightOf(wide.groups.first)),
      );
    });

    test('滚出视区的行不会塌陷高度', () {
      final controller = buildController(linesWithTranslation(30));
      addTearDown(controller.dispose);

      final firstHeight = controller.heightOf(controller.groups.first);
      expect(firstHeight, greaterThan(0));

      // 跳到很后面，首行会被拆除内容
      controller.setCurrentTime(60000, isSeek: true);
      for (var i = 0; i < 10; i++) {
        controller.update(16);
      }

      expect(
        controller.heightOf(controller.groups.first),
        closeTo(firstHeight, 0.5),
        reason: '内容拆除后高度应保留，否则后续行会被往上拽',
      );
    });
  });
}
