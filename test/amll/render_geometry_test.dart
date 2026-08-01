/// 渲染几何测试。
///
/// 这组测试是为了防住一类回归：单测只断言"不抛异常"时，歌词行被全部挤到
/// 左上角一小块区域这种严重问题也能"通过"。这里直接量实际渲染出的位置。
library;

import 'package:cyrene_music_reborn/features/player/amll/amll_lyric_view.dart';
import 'package:cyrene_music_reborn/features/player/amll/core/lyric_types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AmllLyricWord w(String text, int start, int end) =>
    AmllLyricWord(word: text, startTime: start, endTime: end);

List<AmllLyricLine> buildLines(int count, {bool withTranslation = true}) {
  return List<AmllLyricLine>.generate(count, (i) {
    final base = i * 3000;
    return AmllLyricLine(
      words: <AmllLyricWord>[
        w('Never ', base, base + 700),
        w('gonna ', base + 700, base + 1400),
        w('give you up', base + 1400, base + 2400),
      ],
      startTime: base,
      endTime: base + 2400,
      translatedLyric: withTranslation ? '永远不会放弃你 第$i行' : '',
    );
  });
}

/// 测试环境默认屏幕为 800×600，视口高度必须留在其内，
/// 否则会被外层约束压缩、导致几何断言对不上。
const Size kViewport = Size(400, 560);

Future<void> pumpView(
  WidgetTester tester, {
  required List<AmllLyricLine> lines,
  required ValueNotifier<Duration> position,
  Size size = kViewport,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: AmllLyricView(
              lines: lines,
              positionListenable: position,
              isPlaying: true,
            ),
          ),
        ),
      ),
    ),
  );
  // 让弹簧与布局稳定
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// 取出所有歌词行的实际渲染矩形（相对歌词视图）。
List<Rect> lineRects(WidgetTester tester) {
  final viewRect = tester.getRect(find.byType(AmllLyricView));
  final painters = find.descendant(
    of: find.byType(AmllLyricView),
    matching: find.byType(CustomPaint),
  );

  final rects = <Rect>[];
  for (final element in painters.evaluate()) {
    final box = element.renderObject as RenderBox?;
    if (box == null || !box.hasSize) continue;
    if (box.size.height <= 1 || box.size.width <= 1) continue;
    final topLeft = box.localToGlobal(Offset.zero);
    rects.add(
      Rect.fromLTWH(
        topLeft.dx - viewRect.left,
        topLeft.dy - viewRect.top,
        box.size.width,
        box.size.height,
      ),
    );
  }
  rects.sort((a, b) => a.top.compareTo(b.top));
  return rects;
}

void main() {
  group('渲染几何', () {
    testWidgets('歌词纵向铺开，而不是全挤在一小块区域', (tester) async {
      final position = ValueNotifier(const Duration(milliseconds: 3500));
      addTearDown(position.dispose);

      await pumpView(tester, lines: buildLines(12), position: position);

      final rects = lineRects(tester);
      expect(rects.length, greaterThan(2), reason: '应渲染出多行');

      final spread = rects.last.bottom - rects.first.top;
      expect(
        spread,
        greaterThan(kViewport.height * 0.5),
        reason: '多行歌词的纵向跨度应占视口相当比例，'
            '若全部挤在一处说明定位失效（如误用 Transform 替代 Positioned）',
      );
    });

    testWidgets('相邻歌词行的实际渲染矩形不重叠', (tester) async {
      final position = ValueNotifier(const Duration(milliseconds: 3500));
      addTearDown(position.dispose);

      await pumpView(tester, lines: buildLines(10), position: position);

      final rects = lineRects(tester);
      // 只比较主歌词行：取纵向间距最大的一组相邻矩形做检查
      for (var i = 0; i < rects.length - 1; i++) {
        final gap = rects[i + 1].top - rects[i].top;
        expect(
          gap,
          greaterThan(0),
          reason: '第 $i 与第 ${i + 1} 个绘制区域的顶部不应重合',
        );
      }
    });

    testWidgets('有翻译时行间距明显大于无翻译时', (tester) async {
      double measureSpacing(List<Rect> rects) {
        // 取相邻行顶部间距的中位数，避开背景行等特殊项
        final gaps = <double>[
          for (var i = 0; i < rects.length - 1; i++)
            rects[i + 1].top - rects[i].top,
        ]..sort();
        return gaps.isEmpty ? 0 : gaps[gaps.length ~/ 2];
      }

      final p1 = ValueNotifier(const Duration(milliseconds: 3500));
      addTearDown(p1.dispose);
      await pumpView(
        tester,
        lines: buildLines(10, withTranslation: true),
        position: p1,
      );
      final withTrans = measureSpacing(lineRects(tester));

      final p2 = ValueNotifier(const Duration(milliseconds: 3500));
      addTearDown(p2.dispose);
      await pumpView(
        tester,
        lines: buildLines(10, withTranslation: false),
        position: p2,
      );
      final noTrans = measureSpacing(lineRects(tester));

      expect(withTrans, greaterThan(noTrans), reason: '翻译行必须占据额外的纵向空间');
    });

    testWidgets('歌词水平方向占据可用宽度而非缩在角落', (tester) async {
      final position = ValueNotifier(const Duration(milliseconds: 3500));
      addTearDown(position.dispose);

      await pumpView(tester, lines: buildLines(8), position: position);

      final rects = lineRects(tester);
      expect(rects, isNotEmpty);

      final widest = rects.map((r) => r.width).reduce((a, b) => a > b ? a : b);
      expect(
        widest,
        greaterThan(kViewport.width * 0.5),
        reason: '歌词绘制区域应有合理宽度',
      );
    });

    testWidgets('内部 Stack 撑满视口，不会塌缩', (tester) async {
      // 这条断言防的是：歌词行若不是 Stack 的定位子级（Positioned），
      // Stack 会按最大的非定位子级来定尺寸 —— 塌缩到约一行高，
      // 外层 ClipRect 再把其余歌词全部裁掉。
      final position = ValueNotifier(const Duration(milliseconds: 3500));
      addTearDown(position.dispose);

      await pumpView(tester, lines: buildLines(12), position: position);

      // 精确定位到歌词自己的 Stack（在 ClipRect 内），
      // 避免命中 Scaffold / MaterialApp 内部的其它 Stack
      final stack = find.descendant(
        of: find.descendant(
          of: find.byType(AmllLyricView),
          matching: find.byType(ClipRect),
        ),
        matching: find.byType(Stack),
      );
      expect(stack, findsOneWidget);

      final box = tester.renderObject<RenderBox>(stack);
      expect(
        box.size.height,
        closeTo(kViewport.height, 1),
        reason: 'Stack 高度应等于视口高度；塌缩说明歌词行不是 Positioned 子级',
      );
    });

    testWidgets('单行歌词的绘制高度远小于视口', (tester) async {
      // 防的是另一种失配：非定位子级在 StackFit.expand 下会被强制拉成
      // 整个视口高度，所有行叠在一起。
      final position = ValueNotifier(const Duration(milliseconds: 3500));
      addTearDown(position.dispose);

      await pumpView(tester, lines: buildLines(12), position: position);

      final rects = lineRects(tester);
      expect(rects, isNotEmpty);
      for (final r in rects) {
        expect(
          r.height,
          lessThan(kViewport.height * 0.4),
          reason: '单行歌词不应被拉伸到接近视口高度',
        );
      }
    });

    testWidgets('当前行落在对齐位置附近而非视口顶端', (tester) async {
      final position = ValueNotifier(const Duration(milliseconds: 3500));
      addTearDown(position.dispose);

      await pumpView(tester, lines: buildLines(14), position: position);

      final rects = lineRects(tester);
      expect(rects, isNotEmpty);
      // 视区内应同时存在对齐位置上方与下方的行
      final hasAbove = rects.any((r) => r.top < kViewport.height * 0.3);
      final hasBelow = rects.any((r) => r.top > kViewport.height * 0.3);
      expect(
        hasAbove && hasBelow,
        isTrue,
        reason: '对齐位置上下都应有歌词，说明滚动位置正常',
      );
    });
  });
}
