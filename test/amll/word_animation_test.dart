import 'package:cyrene_music_reborn/features/player/amll/core/bezier_easing.dart';
import 'package:cyrene_music_reborn/features/player/amll/core/lyric_types.dart';
import 'package:cyrene_music_reborn/features/player/amll/core/word_animation.dart';
import 'package:cyrene_music_reborn/features/player/amll/render/mask_alpha.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BezierEasing', () {
    test('端点精确', () {
      final e = BezierEasing(0.2, 0.4, 0.58, 1.0);
      expect(e.transform(0), 0);
      expect(e.transform(1), 1);
    });

    test('线性曲线原样返回', () {
      final e = BezierEasing(0.25, 0.25, 0.75, 0.75);
      expect(e.transform(0.3), closeTo(0.3, 1e-6));
      expect(e.transform(0.7), closeTo(0.7, 1e-6));
    });

    test('单调递增', () {
      final e = BezierEasing(0.2, 0.4, 0.58, 1.0);
      var prev = -1.0;
      for (var i = 0; i <= 100; i++) {
        final v = e.transform(i / 100);
        expect(v, greaterThanOrEqualTo(prev - 1e-9));
        prev = v;
      }
    });

    test('ease-out 前段快于线性', () {
      final e = BezierEasing(0, 0, 0.58, 1.0);
      expect(e.transform(0.25), greaterThan(0.25));
    });
  });

  group('empEasing', () {
    test('两端为 0，中点为 1', () {
      expect(empEasing(0), closeTo(0, 1e-6));
      expect(empEasing(kEmpEasingMid), closeTo(1, 1e-6));
      expect(empEasing(1), closeTo(0, 1e-6));
    });

    test('先升后降', () {
      expect(empEasing(0.25), greaterThan(empEasing(0.1)));
      expect(empEasing(0.75), lessThan(empEasing(0.6)));
    });

    test('全程落在 [0,1]', () {
      for (var i = 0; i <= 100; i++) {
        final v = empEasing(i / 100);
        expect(v, inInclusiveRange(0, 1));
      }
    });
  });

  group('WordFloatAnimation', () {
    test('延迟前不浮动', () {
      final a = WordFloatAnimation.forWord(
        AmllLyricWord(word: 'x', startTime: 1000, endTime: 2000),
        0,
        isBG: false,
      );
      expect(a.offsetEmAt(500), 0);
    });

    test('时长下限为 1000ms', () {
      final a = WordFloatAnimation.forWord(
        AmllLyricWord(word: 'x', startTime: 0, endTime: 200),
        0,
        isBG: false,
      );
      expect(a.durationMs, 1000);
    });

    test('最终上浮 0.05em（向上为负）', () {
      final a = WordFloatAnimation.forWord(
        AmllLyricWord(word: 'x', startTime: 0, endTime: 1000),
        0,
        isBG: false,
      );
      expect(a.offsetEmAt(1000), closeTo(-0.05, 1e-6));
      expect(a.offsetEmAt(99999), closeTo(-0.05, 1e-6));
    });

    test('背景人声行浮动幅度加倍', () {
      final bg = WordFloatAnimation.forWord(
        AmllLyricWord(word: 'x', startTime: 0, endTime: 1000),
        0,
        isBG: true,
      );
      expect(bg.offsetEmAt(1000), closeTo(-0.1, 1e-6));
    });

    test('单调向上', () {
      final a = WordFloatAnimation.forWord(
        AmllLyricWord(word: 'x', startTime: 0, endTime: 1000),
        0,
        isBG: false,
      );
      var prev = 1.0;
      for (var t = 0; t <= 1000; t += 50) {
        final v = a.offsetEmAt(t.toDouble());
        expect(v, lessThanOrEqualTo(prev + 1e-9));
        prev = v;
      }
    });
  });

  group('EmphasisAnimation', () {
    EmphasisAnimation make({
      int duration = 2000,
      int delay = 0,
      int chars = 4,
      bool isLast = false,
      bool isBG = false,
    }) => EmphasisAnimation.forWord(
      durationMs: duration,
      delayMs: delay,
      charCount: chars,
      rubyCharCount: 0,
      isLastWordOfLine: isLast,
      isBG: isBG,
    );

    test('起始前保持无强调的缩放', () {
      final a = make(delay: 1000);
      expect(a.stateAt(0, 0).scale, 1);
      expect(a.stateAt(0, 0).glowAlpha, 0);
    });

    test('中途会放大并发光', () {
      final a = make();
      final s = a.stateAt(1000, 0);
      expect(s.scale, greaterThan(1));
      expect(s.glowAlpha, greaterThan(0));
    });

    test('末词的幅度与辉光更强、时长更长', () {
      final normal = make();
      final last = make(isLast: true);
      expect(last.amount, greaterThan(normal.amount));
      expect(last.blur, greaterThan(normal.blur));
      expect(last.durationMs, greaterThan(normal.durationMs));
    });

    test('幅度与辉光有上限', () {
      final huge = make(duration: 100000, isLast: true);
      expect(huge.amount, lessThanOrEqualTo(1.2));
      expect(huge.blur, lessThanOrEqualTo(0.8));
    });

    test('逐字错峰：后面的字更晚达到峰值', () {
      final a = make(chars: 4);
      // 在同一时刻，第 0 个字比第 3 个字进展更多
      final s0 = a.stateAt(600, 0);
      final s3 = a.stateAt(600, 3);
      expect(s0.scale, greaterThan(s3.scale));
    });

    test('横向位移左右对称发散', () {
      final a = make(chars: 4);
      final left = a.stateAt(1000, 0);
      final right = a.stateAt(1000, 3);
      // 左侧字向左推（正号），右侧字向右推（负号）
      expect(left.offsetXEm * right.offsetXEm, lessThan(0));
    });

    test('辉光半径不超过 0.3em', () {
      final a = make(duration: 100000, isLast: true);
      expect(a.stateAt(5000, 0).glowRadiusEm, lessThanOrEqualTo(0.3));
    });

    test('零字数不报错', () {
      final a = make(chars: 0);
      expect(a.stateAt(500, 0).scale, 1);
    });
  });

  group('MaskAlphaSmoother', () {
    test('活跃行渐变模式下亮态趋近 1', () {
      final s = MaskAlphaSmoother()
        ..updateTargets(1.0, LyricLineRenderMode.gradient);
      for (var i = 0; i < 120; i++) {
        s.update(1 / 60);
      }
      expect(s.brightAlpha, closeTo(1.0, 0.01));
      expect(s.darkAlpha, closeTo(0.4, 0.01));
    });

    test('纯色模式下亮暗一致', () {
      final s = MaskAlphaSmoother()
        ..updateTargets(1.0, LyricLineRenderMode.solid);
      for (var i = 0; i < 200; i++) {
        s.update(1 / 60);
      }
      expect(s.brightAlpha, closeTo(s.darkAlpha, 1e-6));
    });

    test('非活跃行（缩放 0.97）压到最低亮度', () {
      final s = MaskAlphaSmoother()
        ..updateTargets(0.97, LyricLineRenderMode.gradient);
      for (var i = 0; i < 300; i++) {
        s.update(1 / 60);
      }
      expect(s.brightAlpha, closeTo(0.2, 0.01));
    });

    test('变亮明显快于变暗', () {
      final rising = MaskAlphaSmoother()
        ..updateTargets(0.97, LyricLineRenderMode.gradient);
      for (var i = 0; i < 300; i++) {
        rising.update(1 / 60);
      }
      // 现在切到全亮，量一帧的增量
      rising.updateTargets(1.0, LyricLineRenderMode.gradient);
      final beforeUp = rising.brightAlpha;
      rising.update(1 / 60);
      final riseStep = rising.brightAlpha - beforeUp;

      final falling = MaskAlphaSmoother()
        ..updateTargets(1.0, LyricLineRenderMode.gradient);
      for (var i = 0; i < 300; i++) {
        falling.update(1 / 60);
      }
      falling.updateTargets(0.97, LyricLineRenderMode.gradient);
      final beforeDown = falling.brightAlpha;
      falling.update(1 / 60);
      final fallStep = beforeDown - falling.brightAlpha;

      expect(riseStep, greaterThan(fallStep * 2));
    });

    test('snapToTarget 立即到位', () {
      final s = MaskAlphaSmoother()
        ..updateTargets(1.0, LyricLineRenderMode.gradient)
        ..snapToTarget();
      expect(s.brightAlpha, 1.0);
      expect(s.darkAlpha, closeTo(0.4, 1e-9));
    });
  });
}
