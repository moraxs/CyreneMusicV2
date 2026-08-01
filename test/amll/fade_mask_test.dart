import 'package:cyrene_music_reborn/features/player/amll/core/fade_mask.dart';
import 'package:flutter_test/flutter_test.dart';

FadeMaskWord fw(int start, int end, double width) =>
    FadeMaskWord(startTime: start, endTime: end, width: width);

void main() {
  group('computeFadeGradient', () {
    test('总宽为 2 + 比值 + padding 倍词宽', () {
      final g = computeFadeGradient(0.5);
      expect(g.totalAspect, 2.5);
    });

    test('过渡带居中', () {
      final g = computeFadeGradient(0.5);
      final mid = (g.brightStop + g.darkStop) / 2;
      expect(mid, closeTo(0.5, 1e-9));
    });

    test('过渡带占比等于比值除以总宽', () {
      final g = computeFadeGradient(1.0);
      expect(g.darkStop - g.brightStop, closeTo(1.0 / 3.0, 1e-9));
    });
  });

  group('solveLineFadeMask', () {
    test('空词表返回空解', () {
      expect(
        solveLineFadeMask(
          words: const [],
          lineStartTime: 0,
          lineEndTime: 1000,
          wordHeight: 40,
          wordFadeWidth: 1,
        ),
        isEmpty,
      );
    });

    test('每个词都得到一份解', () {
      final solutions = solveLineFadeMask(
        words: [fw(0, 500, 60), fw(500, 1000, 80)],
        lineStartTime: 0,
        lineEndTime: 1000,
        wordHeight: 40,
        wordFadeWidth: 1,
      );
      expect(solutions, hasLength(2));
    });

    test('fadeWidth = 词高 × wordFadeWidth', () {
      final solutions = solveLineFadeMask(
        words: [fw(0, 1000, 60)],
        lineStartTime: 0,
        lineEndTime: 1000,
        wordHeight: 40,
        wordFadeWidth: 0.5,
      );
      expect(solutions[0].fadeWidth, 20);
    });

    test('开始时遮罩完全未点亮，结束时完全点亮', () {
      final solutions = solveLineFadeMask(
        words: [fw(0, 1000, 60)],
        lineStartTime: 0,
        lineEndTime: 1000,
        wordHeight: 40,
        wordFadeWidth: 1,
      );
      final s = solutions[0];
      expect(s.offsetAt(0), s.minOffset);
      expect(s.offsetAt(1), 0);
    });

    test('遮罩偏移随进度单调不减', () {
      final solutions = solveLineFadeMask(
        words: [fw(0, 400, 50), fw(400, 900, 70), fw(900, 1400, 40)],
        lineStartTime: 0,
        lineEndTime: 1400,
        wordHeight: 40,
        wordFadeWidth: 1,
      );

      for (final s in solutions) {
        var prev = double.negativeInfinity;
        for (var i = 0; i <= 100; i++) {
          final v = s.offsetAt(i / 100);
          expect(v, greaterThanOrEqualTo(prev - 1e-9));
          prev = v;
        }
      }
    });

    test('遮罩偏移始终落在 [minOffset, 0] 内', () {
      final solutions = solveLineFadeMask(
        words: [fw(0, 400, 50), fw(600, 1000, 70)],
        lineStartTime: 0,
        lineEndTime: 1000,
        wordHeight: 40,
        wordFadeWidth: 1,
      );
      for (final s in solutions) {
        for (var i = 0; i <= 100; i++) {
          final v = s.offsetAt(i / 100);
          expect(v, greaterThanOrEqualTo(s.minOffset - 1e-9));
          expect(v, lessThanOrEqualTo(1e-9));
        }
      }
    });

    test('靠后的词点亮得更晚', () {
      final solutions = solveLineFadeMask(
        words: [fw(0, 500, 60), fw(500, 1000, 60)],
        lineStartTime: 0,
        lineEndTime: 1000,
        wordHeight: 40,
        wordFadeWidth: 1,
      );

      // 用「已点亮的比例」比较：同一时刻靠前的词一定亮得更多。
      // 注意首词不会在自己时间结束的瞬间就全亮 —— fadeWidth 比词宽大时
      // 渐变带会拖尾，这是原算法的行为（首词额外 +1.5×fadeWidth 补偿）。
      double litRatio(FadeMaskSolution s, double p) =>
          (s.offsetAt(p) - s.minOffset) / -s.minOffset;

      expect(litRatio(solutions[0], 0.5), greaterThan(litRatio(solutions[1], 0.5)));
      expect(litRatio(solutions[1], 0.5), lessThanOrEqualTo(0.2));
      expect(litRatio(solutions[0], 0.5), greaterThan(0.7));
    });

    test('首词在整行结束前就已完全点亮', () {
      final solutions = solveLineFadeMask(
        words: [fw(0, 500, 60), fw(500, 1000, 60)],
        lineStartTime: 0,
        lineEndTime: 1000,
        wordHeight: 40,
        wordFadeWidth: 1,
      );
      expect(solutions[0].offsetAt(0.7), 0);
    });

    test('词间停顿会让遮罩静止', () {
      // 第一个词 0..300 结束，第二个词 700 才开始，中间 400ms 停顿
      final solutions = solveLineFadeMask(
        words: [fw(0, 300, 50), fw(700, 1000, 50)],
        lineStartTime: 0,
        lineEndTime: 1000,
        wordHeight: 40,
        wordFadeWidth: 1,
      );

      final second = solutions[1];
      // 停顿区间（0.3..0.7）内偏移不应变化
      final at40 = second.offsetAt(0.4);
      final at65 = second.offsetAt(0.65);
      expect(at65, closeTo(at40, 1e-6));
    });

    test('行结束时间晚于所有词时按行结束时间归一', () {
      // 词 0..500，行到 1000：半程时词应已点亮完毕
      final solutions = solveLineFadeMask(
        words: [fw(0, 500, 60)],
        lineStartTime: 0,
        lineEndTime: 1000,
        wordHeight: 40,
        wordFadeWidth: 1,
      );
      expect(solutions[0].offsetAt(0.5), closeTo(0, 1e-6));
    });

    test('词结束时间晚于行时以词为准，不提前收尾', () {
      final solutions = solveLineFadeMask(
        words: [fw(0, 2000, 60)],
        lineStartTime: 0,
        lineEndTime: 1000,
        wordHeight: 40,
        wordFadeWidth: 1,
      );
      // 半程（=1000ms）时还没点亮完
      expect(solutions[0].offsetAt(0.5), lessThan(0));
      expect(solutions[0].offsetAt(1.0), closeTo(0, 1e-6));
    });

    test('零时长的行不会除零', () {
      final solutions = solveLineFadeMask(
        words: [fw(500, 500, 60)],
        lineStartTime: 500,
        lineEndTime: 500,
        wordHeight: 40,
        wordFadeWidth: 1,
      );
      expect(solutions, hasLength(1));
      expect(solutions[0].offsetAt(0.5).isFinite, isTrue);
    });

    test('亮区边界随进度从词左侧扫到右侧', () {
      final solutions = solveLineFadeMask(
        words: [fw(0, 1000, 100)],
        lineStartTime: 0,
        lineEndTime: 1000,
        wordHeight: 40,
        wordFadeWidth: 1,
      );
      final s = solutions[0];
      final startEdge = s.brightEdgeAt(0);
      final endEdge = s.brightEdgeAt(1);

      expect(startEdge, lessThan(0), reason: '开始时亮区还在词左侧之外');
      expect(endEdge, greaterThanOrEqualTo(100 - 1e-6), reason: '结束时亮区已扫过词右侧');
      expect(s.darkEdgeAt(0.5), greaterThan(s.brightEdgeAt(0.5)));
    });
  });

  group('lineFadeDuration', () {
    test('取词最晚结束与行结束的较大者', () {
      expect(
        lineFadeDuration(
          words: [fw(0, 2000, 10)],
          lineStartTime: 0,
          lineEndTime: 1000,
        ),
        2000,
      );
      expect(
        lineFadeDuration(
          words: [fw(0, 500, 10)],
          lineStartTime: 0,
          lineEndTime: 1000,
        ),
        1000,
      );
    });
  });
}
