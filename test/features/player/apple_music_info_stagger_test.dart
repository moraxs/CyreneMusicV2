import 'package:cyrene_music_reborn/features/player/mobile/widgets/apple_music/apple_music_info_stagger.dart';
import 'package:flutter_test/flutter_test.dart';

/// [AppleMusicInfoStagger] 的行为约束。
///
/// 这套算法只有几行，但方向和区间极易搞反 —— 搞反的后果是两块信息对着飞、
/// 或者中段两块一起半透明糊在一起，恰恰是 AMLL 的错位设计要避免的东西。
void main() {
  const h = 800.0; // 假想屏高，25vh = 200px

  group('两端状态', () {
    test('t=0（歌词模式）：小信息完全就位，大信息不在场', () {
      expect(AppleMusicInfoStagger.smallPresence(0), closeTo(1.0, 1e-6));
      expect(AppleMusicInfoStagger.bigPresence(0), closeTo(0.0, 1e-6));
      expect(AppleMusicInfoStagger.smallOffsetY(0, h), closeTo(0, 1e-6));
      expect(AppleMusicInfoStagger.bigOffsetY(0, h), closeTo(-200, 1e-6));
    });

    test('t=1（封面模式）：大信息完全就位，小信息已让位', () {
      expect(AppleMusicInfoStagger.smallPresence(1), closeTo(0.0, 1e-6));
      expect(AppleMusicInfoStagger.bigPresence(1), closeTo(1.0, 1e-6));
      expect(AppleMusicInfoStagger.smallOffsetY(1, h), closeTo(200, 1e-6));
      expect(AppleMusicInfoStagger.bigOffsetY(1, h), closeTo(0, 1e-6));
    });
  });

  group('位移方向', () {
    test('小信息一路向下（非负），大信息一路从上方落下（非正）', () {
      for (var i = 0; i <= 20; i++) {
        final t = i / 20;
        expect(AppleMusicInfoStagger.smallOffsetY(t, h), greaterThanOrEqualTo(0),
            reason: '小信息应向下让位，t=$t');
        expect(AppleMusicInfoStagger.bigOffsetY(t, h), lessThanOrEqualTo(0),
            reason: '大信息应自上方落下，t=$t');
      }
    });

    test('两块同向移动：t 增大时都朝 +y 走', () {
      // 小信息 offset 递增（往下），大信息 offset 也递增（由 -200 向 0，即往下）。
      var prevSmall = AppleMusicInfoStagger.smallOffsetY(0, h);
      var prevBig = AppleMusicInfoStagger.bigOffsetY(0, h);
      for (var i = 1; i <= 20; i++) {
        final t = i / 20;
        final small = AppleMusicInfoStagger.smallOffsetY(t, h);
        final big = AppleMusicInfoStagger.bigOffsetY(t, h);
        expect(small, greaterThanOrEqualTo(prevSmall - 1e-9),
            reason: '小信息不该回头，t=$t');
        expect(big, greaterThanOrEqualTo(prevBig - 1e-9),
            reason: '大信息不该回头，t=$t');
        prevSmall = small;
        prevBig = big;
      }
    });
  });

  group('错位', () {
    test('大信息在 t=0.35 之前完全不入场', () {
      expect(AppleMusicInfoStagger.bigPresence(0.0), closeTo(0, 1e-6));
      expect(AppleMusicInfoStagger.bigPresence(0.2), closeTo(0, 1e-6));
      expect(AppleMusicInfoStagger.bigPresence(0.34), closeTo(0, 1e-6));
      expect(AppleMusicInfoStagger.bigPresence(0.5), greaterThan(0));
    });

    test('小信息在 t=0.45 之后完全让位', () {
      expect(AppleMusicInfoStagger.smallPresence(0.45), closeTo(0, 1e-6));
      expect(AppleMusicInfoStagger.smallPresence(0.6), closeTo(0, 1e-6));
      expect(AppleMusicInfoStagger.smallPresence(1.0), closeTo(0, 1e-6));
    });

    test('中段不会两块都明显可见（避免糊在一起）', () {
      // 重叠区 [0.35, 0.45]，取重叠最严重的点，两者之和仍应远低于 2。
      for (var i = 0; i <= 10; i++) {
        final t = 0.35 + (0.10 * i / 10);
        final sum = AppleMusicInfoStagger.smallPresence(t) +
            AppleMusicInfoStagger.bigPresence(t);
        expect(sum, lessThan(0.6),
            reason: 't=$t 处两块信息同时可见的总量过高，会糊成一团');
      }
    });
  });

  group('越界保护', () {
    test('t 超出 [0,1]（弹簧过冲）不抛异常，且夹在端点值上', () {
      for (final t in [-0.2, -0.01, 1.01, 1.3]) {
        expect(() => AppleMusicInfoStagger.smallPresence(t), returnsNormally);
        expect(() => AppleMusicInfoStagger.bigPresence(t), returnsNormally);
      }
      expect(AppleMusicInfoStagger.smallPresence(-0.2), closeTo(1.0, 1e-6));
      expect(AppleMusicInfoStagger.bigPresence(1.3), closeTo(1.0, 1e-6));
    });
  });
}
