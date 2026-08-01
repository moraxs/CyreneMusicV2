import 'package:cyrene_music_reborn/features/player/amll/render/interlude_dots.dart';
import 'package:flutter_test/flutter_test.dart';

InterludeDotsState stateAt(int t, {int start = 0, int end = 8000}) =>
    InterludeDotsAnimation.stateAt(
      currentTimeMs: t,
      startTime: start,
      endTime: end,
    );

void main() {
  group('InterludeDotsAnimation', () {
    test('区间之外完全隐藏', () {
      expect(stateAt(-100).isVisible, isFalse);
      expect(stateAt(9000).isVisible, isFalse);
    });

    test('零长度区间隐藏', () {
      expect(stateAt(0, start: 0, end: 0).isVisible, isFalse);
    });

    test('前 500ms 完全透明（缩放已开始但还看不到）', () {
      final s = stateAt(200);
      expect(s.dotOpacities.every((o) => o == 0), isTrue);
    });

    test('500..1000ms 渐显', () {
      final a = stateAt(600);
      final b = stateAt(900);
      expect(a.dotOpacities[0], greaterThan(0));
      expect(b.dotOpacities[0], greaterThan(a.dotOpacities[0]));
    });

    test('进场缩放从 0 增长', () {
      expect(stateAt(50).scale, lessThan(stateAt(500).scale));
      expect(stateAt(500).scale, lessThan(stateAt(1800).scale));
    });

    test('缩放上限约为 0.7 倍基准（退场回弹会略微过冲）', () {
      // 基准 0.7，呼吸最多 +5%，退场 easeInOutBack 前段还会反向过冲约 4%
      for (var t = 0; t <= 8000; t += 50) {
        expect(stateAt(t).scale, lessThanOrEqualTo(0.8));
      }
    });

    test('三个点瀑布式提亮：靠前的点更亮', () {
      final s = stateAt(2000);
      expect(s.dotOpacities[0], greaterThanOrEqualTo(s.dotOpacities[1]));
      expect(s.dotOpacities[1], greaterThanOrEqualTo(s.dotOpacities[2]));
    });

    test('点的不透明度不低于 0.25（渐显完成后）', () {
      final s = stateAt(2000);
      for (final o in s.dotOpacities) {
        expect(o, greaterThanOrEqualTo(0.25 - 1e-9));
      }
    });

    test('退场阶段整体收缩', () {
      // easeInOutBack 在退场刚开始会先反向轻微放大，所以取更靠后的采样点
      expect(stateAt(7950).scale, lessThan(stateAt(4000).scale));
    });

    test('最后 375ms 渐隐', () {
      final s = stateAt(7900);
      expect(s.dotOpacities[0], lessThan(0.3));
    });

    test('结束时缩到约一半，随后立刻隐藏', () {
      // easeInOutBack(0.5) = 0.5，所以末帧缩放约为基准的一半；
      // 越过区间末尾后由 isVisible 判定接管，不再绘制。
      expect(stateAt(8000).scale, lessThan(stateAt(4000).scale * 0.8));
      expect(stateAt(8001).isVisible, isFalse);
    });

    test('所有不透明度都在 [0,1] 内', () {
      for (var t = 0; t <= 8000; t += 25) {
        for (final o in stateAt(t).dotOpacities) {
          expect(o, inInclusiveRange(0, 1));
        }
      }
    });

    test('缩放始终非负', () {
      for (var t = 0; t <= 8000; t += 25) {
        expect(stateAt(t).scale, greaterThanOrEqualTo(0));
      }
    });

    test('呼吸：中段存在起伏而非恒定', () {
      final samples = <double>[
        for (var t = 2500; t <= 5500; t += 100) stateAt(t).scale,
      ];
      final minV = samples.reduce((a, b) => a < b ? a : b);
      final maxV = samples.reduce((a, b) => a > b ? a : b);
      expect(maxV - minV, greaterThan(0.01), reason: '应能观察到呼吸起伏');
    });

    test('短间奏（刚好 4s）也能正常演出', () {
      InterludeDotsState s(int t) => stateAt(t, end: 4000);
      expect(s(2000).isVisible, isTrue);
      expect(s(4000).scale, lessThan(s(2000).scale));
      expect(s(4001).isVisible, isFalse);
    });

    test('非零起始时间正确对齐', () {
      final s = InterludeDotsAnimation.stateAt(
        currentTimeMs: 12000,
        startTime: 10000,
        endTime: 18000,
      );
      final ref = stateAt(2000);
      expect(s.scale, closeTo(ref.scale, 1e-9));
    });
  });

  group('InterludeDotsPainter', () {
    test('宽度为三点加两间隙', () {
      expect(InterludeDotsPainter.widthFor(10, 5), 40);
    });
  });
}
