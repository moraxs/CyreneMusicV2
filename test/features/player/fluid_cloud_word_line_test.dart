/// 流体云歌词「点亮前后排版一致」的回归测试。
///
/// 防住的问题：活跃行走 AMLL 逐字绘制管线（逐词测量 + 只在词边界折行），
/// 而未点亮行曾用 Flutter `Text` 自己断行。两套断行规则不同，同一句歌词
/// 在点亮前后折行位置/高度会变，滚到该行时整句突兀重排。
library;

import 'package:cyrene_music_reborn/features/player/mobile/components/fluid_cloud_word_line.dart';
import 'package:cyrene_music_reborn/features/player/mobile/compat/lyric_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LyricWord _w(String text, int startMs, int durMs) => LyricWord(
  startTime: Duration(milliseconds: startMs),
  duration: Duration(milliseconds: durMs),
  text: text,
);

/// 一句必然要折行的英文逐字歌词
LyricLine _wrappingLine() => LyricLine(
  startTime: Duration.zero,
  text: 'Never gonna give you up never gonna let you down',
  words: <LyricWord>[
    _w('Never ', 0, 400),
    _w('gonna ', 400, 400),
    _w('give ', 800, 400),
    _w('you ', 1200, 300),
    _w('up ', 1500, 300),
    _w('never ', 1800, 400),
    _w('gonna ', 2200, 400),
    _w('let ', 2600, 300),
    _w('you ', 2900, 300),
    _w('down', 3200, 500),
  ],
);

/// 中文逐字歌词（按单字拆分，折行点更密）
LyricLine _cjkLine() {
  const text = '我曾经跨过山和大海也穿过人山人海我曾经拥有着的一切转眼都飘散如烟';
  final words = <LyricWord>[];
  for (var i = 0; i < text.length; i++) {
    words.add(_w(text[i], i * 200, 200));
  }
  return LyricLine(startTime: Duration.zero, text: text, words: words);
}

const TextStyle _style = TextStyle(
  fontSize: 22,
  fontWeight: FontWeight.w800,
  height: 1.3,
  color: Color(0xFFFFFFFF),
);

void main() {
  group('fluidCloudLineLayout', () {
    test('同一行在同宽同样式下复用同一份排版（点亮前后必然一致）', () {
      final lyric = _wrappingLine();
      final a = fluidCloudLineLayout(
        lyric: lyric,
        textStyle: _style,
        maxWidth: 300,
      );
      final b = fluidCloudLineLayout(
        lyric: lyric,
        textStyle: _style,
        maxWidth: 300,
      );
      // 同一个实例：排版只算一次，测高与两种绘制状态共用
      expect(identical(a, b), isTrue);
    });

    test('亚像素宽度抖动不会算出不同的折行', () {
      final lyric = _wrappingLine();
      final a = fluidCloudLineLayout(
        lyric: lyric,
        textStyle: _style,
        maxWidth: 300.0,
      );
      final b = fluidCloudLineLayout(
        lyric: lyric,
        textStyle: _style,
        maxWidth: 300.16,
      );
      expect(a.layout.lineCount, b.layout.lineCount);
      expect(a.height, b.height);
    });

    test('宽度收窄时确实会折更多行（测试用例本身有效）', () {
      final lyric = _wrappingLine();
      // 测试字体每个字形约 1em 宽，这句 48 字符需要 >1050px 才不折行
      final wide = fluidCloudLineLayout(
        lyric: lyric,
        textStyle: _style,
        maxWidth: 4000,
      );
      final narrow = fluidCloudLineLayout(
        lyric: lyric,
        textStyle: _style,
        maxWidth: 220,
      );
      expect(wide.layout.lineCount, 1);
      expect(narrow.layout.lineCount, greaterThan(1));
      expect(narrow.height, greaterThan(wide.height));
    });

    test('居中不改变折行结果，只平移每个视觉行', () {
      final lyric = _wrappingLine();
      final left = fluidCloudLineLayout(
        lyric: lyric,
        textStyle: _style,
        maxWidth: 260,
      );
      final centered = fluidCloudLineLayout(
        lyric: lyric,
        textStyle: _style,
        maxWidth: 260,
        centered: true,
      );

      expect(centered.layout.lineCount, left.layout.lineCount);
      expect(centered.height, left.height);
      // 每个词仍在原来的视觉行上
      for (var i = 0; i < left.layout.words.length; i++) {
        expect(
          centered.layout.words[i].lineIndex,
          left.layout.words[i].lineIndex,
        );
      }
    });
  });

  group('FluidCloudWordLine 点亮前后几何一致', () {
    /// 渲染一行并返回它实际占据的尺寸
    Future<Size> renderedSize(
      WidgetTester tester, {
      required LyricLine lyric,
      required bool active,
      required bool centered,
      double width = 280,
    }) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: FluidCloudWordLine(
                key: key,
                lyric: lyric,
                active: active,
                centered: centered,
                textStyle: _style,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      return tester.getSize(find.byKey(key));
    }

    for (final centered in <bool>[false, true]) {
      final label = centered ? '居中(全屏页)' : '左对齐(主面板)';

      testWidgets('$label 英文长句：点亮与未点亮渲染高度相同', (tester) async {
        final lyric = _wrappingLine();
        final inactive = await renderedSize(
          tester,
          lyric: lyric,
          active: false,
          centered: centered,
        );
        final active = await renderedSize(
          tester,
          lyric: lyric,
          active: true,
          centered: centered,
        );
        expect(active.height, inactive.height);
      });

      testWidgets('$label 中文长句：点亮与未点亮渲染高度相同', (tester) async {
        final lyric = _cjkLine();
        final inactive = await renderedSize(
          tester,
          lyric: lyric,
          active: false,
          centered: centered,
        );
        final active = await renderedSize(
          tester,
          lyric: lyric,
          active: true,
          centered: centered,
        );
        expect(active.height, inactive.height);
      });
    }

    testWidgets('逐字上浮不改变行占位高度（整个播放过程中高度恒定）', (tester) async {
      final lyric = _wrappingLine();
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 280,
              child: FluidCloudWordLine(
                key: key,
                lyric: lyric,
                active: true,
                textStyle: _style,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      final baseline = tester.getSize(find.byKey(key)).height;

      // 推进到词级浮动动画中段，高度不应变化
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.getSize(find.byKey(key)).height, baseline);
      }
    });

    testWidgets('未点亮行不订阅逐帧时间（不留下待处理的动画帧）', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 280,
              child: FluidCloudWordLine(
                lyric: _wrappingLine(),
                active: false,
                textStyle: _style,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      // 起了 ticker 的话这里会因为「仍有帧待处理」而失败
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
