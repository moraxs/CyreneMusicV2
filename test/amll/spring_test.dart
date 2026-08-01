import 'package:cyrene_music_reborn/features/player/amll/core/spring.dart';
import 'package:flutter_test/flutter_test.dart';

/// 以固定步长推进弹簧若干秒。
void advance(Spring spring, double seconds, {double step = 1 / 60}) {
  var elapsed = 0.0;
  while (elapsed < seconds) {
    spring.update(step);
    elapsed += step;
  }
}

void main() {
  group('Spring', () {
    test('初始状态即已到达目标', () {
      final spring = Spring(10);
      expect(spring.getCurrentPosition(), 10);
      expect(spring.arrived(), isTrue);
    });

    test('setPosition 立即跳到目标且不产生动画', () {
      final spring = Spring()..setPosition(42);
      expect(spring.getCurrentPosition(), 42);
      expect(spring.arrived(), isTrue);
    });

    test('默认参数下会收敛到目标位置', () {
      final spring = Spring()..setTargetPosition(100);
      advance(spring, 5);
      expect(spring.getCurrentPosition(), closeTo(100, 0.01));
      expect(spring.arrived(), isTrue);
    });

    test('收敛后会吸附到精确目标值', () {
      final spring = Spring()..setTargetPosition(-250);
      advance(spring, 8);
      expect(spring.getCurrentPosition(), -250);
    });

    test('切换目标时保留当前速度，位移一阶连续', () {
      // 这是 AMLL 手感的核心：中途改目标不会像补间那样瞬间折返。
      final spring = Spring()..setTargetPosition(1000);
      advance(spring, 0.25);

      final posBefore = spring.getCurrentPosition();
      expect(posBefore, greaterThan(0));

      // 反向设一个目标，第一帧的位移方向应仍然延续原有正向速度
      spring.setTargetPosition(-1000);
      spring.update(1 / 60);
      final posAfter = spring.getCurrentPosition();

      expect(
        posAfter,
        greaterThan(posBefore),
        reason: '带速度求解时，反向后的第一帧仍应继续前进',
      );
    });

    test('过阻尼参数不产生过冲', () {
      final spring = Spring()
        ..updateParams(const SpringParams(stiffness: 100, damping: 30, mass: 1))
        ..setTargetPosition(100);

      var maxPos = 0.0;
      for (var i = 0; i < 600; i++) {
        spring.update(1 / 60);
        final p = spring.getCurrentPosition();
        if (p > maxPos) maxPos = p;
      }
      expect(maxPos, lessThanOrEqualTo(100.0001));
      expect(spring.getCurrentPosition(), closeTo(100, 0.01));
    });

    test('soft 强制走过阻尼解，同样不过冲', () {
      final spring = Spring()
        ..updateParams(
          const SpringParams(stiffness: 200, damping: 1, soft: true),
        )
        ..setTargetPosition(50);

      var maxPos = 0.0;
      for (var i = 0; i < 900; i++) {
        spring.update(1 / 60);
        maxPos = spring.getCurrentPosition() > maxPos
            ? spring.getCurrentPosition()
            : maxPos;
      }
      expect(maxPos, lessThanOrEqualTo(50.0001));
    });

    test('欠阻尼参数会过冲', () {
      final spring = Spring()
        ..updateParams(const SpringParams(stiffness: 300, damping: 4, mass: 1))
        ..setTargetPosition(100);

      var maxPos = 0.0;
      for (var i = 0; i < 60; i++) {
        spring.update(1 / 60);
        maxPos = spring.getCurrentPosition() > maxPos
            ? spring.getCurrentPosition()
            : maxPos;
      }
      expect(maxPos, greaterThan(100));
    });

    test('setTargetPosition 的 delay 会推迟目标生效', () {
      final spring = Spring()..setTargetPosition(100, 0.5);

      // 延迟窗口内不应开始移动
      advance(spring, 0.3);
      expect(spring.getCurrentPosition(), 0);
      expect(spring.arrived(), isFalse, reason: '有待生效的延迟目标时不算到达');

      advance(spring, 5);
      expect(spring.getCurrentPosition(), closeTo(100, 0.01));
    });

    test('updateParams 的 delay 会推迟参数生效', () {
      final spring = Spring()
        ..updateParams(const SpringParams(stiffness: 500, damping: 60), 0.4);
      expect(spring.arrived(), isFalse);

      advance(spring, 1);
      // 参数已生效，此时设目标应按新参数收敛
      spring.setTargetPosition(10);
      advance(spring, 5);
      expect(spring.getCurrentPosition(), closeTo(10, 0.01));
    });

    test('getTargetPosition 反映最新目标', () {
      final spring = Spring()..setTargetPosition(7);
      expect(spring.getTargetPosition(), 7);
    });

    test('SpringParams.merge 只覆盖非空字段', () {
      const base = SpringParams(mass: 1, damping: 10, stiffness: 100);
      final merged = base.merge(const SpringParams(stiffness: 220));
      expect(merged.stiffness, 220);
      expect(merged.damping, 10);
      expect(merged.mass, 1);
    });
  });
}
