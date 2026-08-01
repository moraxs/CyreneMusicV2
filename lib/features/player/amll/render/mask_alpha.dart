/// 亮/暗遮罩透明度的平滑器。
///
/// 对应 `lyric-line.ts` 的 `updateMaskAlphaTargets` + `applyAlphaToDom`。
/// 用非对称的一阶低通：变亮很快（ATTACK 50），变暗较慢（RELEASE 7）。
/// 变亮必须快，否则唱到第一个字时透明度还在爬升，会看不清。
library;

import 'dart:math' as math;

import '../core/lyric_types.dart';

/// 变亮速度
const double kAlphaAttackSpeed = 50.0;

/// 变暗速度
const double kAlphaReleaseSpeed = 7.0;

class MaskAlphaSmoother {
  double _currentBright = 1.0;
  double _currentDark = 0.2;
  double _targetBright = 1.0;
  double _targetDark = 0.2;

  double get brightAlpha => _currentBright;
  double get darkAlpha => _currentDark;

  /// 根据当前缩放与渲染模式更新目标透明度。
  ///
  /// [scale] 是行的当前缩放（1.0 = 原始大小）。非活跃行缩到 0.97，
  /// 因此 `(scale - 0.97) / 0.03` 正好把 0.97..1.0 映射到 0..1。
  void updateTargets(double scale, LyricLineRenderMode mode) {
    final factor = ((scale - 0.97) / 0.03).clamp(0.0, 1.0);
    final dynamicDark = factor * 0.2 + 0.2;
    final dynamicBright = factor * 0.8 + 0.2;

    if (mode == LyricLineRenderMode.solid) {
      // 纯色模式下亮暗一致，整行呈现为统一的暗态
      _targetBright = dynamicDark;
      _targetDark = dynamicDark;
    } else {
      _targetBright = dynamicBright;
      _targetDark = dynamicDark;
    }
  }

  /// 推进 [delta] 秒。
  void update(double delta) {
    final dt = delta <= 0 ? 0.016 : delta;
    double factorFor(double speed) => 1 - math.exp(-speed * dt);

    // 变亮/变暗选用不同速度
    final brightSpeed = _targetBright > _currentBright
        ? kAlphaAttackSpeed
        : kAlphaReleaseSpeed;
    if ((_targetBright - _currentBright).abs() < 0.001) {
      _currentBright = _targetBright;
    } else {
      _currentBright +=
          (_targetBright - _currentBright) * factorFor(brightSpeed);
    }

    final darkSpeed = _targetDark > _currentDark
        ? kAlphaAttackSpeed
        : kAlphaReleaseSpeed;
    if ((_targetDark - _currentDark).abs() < 0.001) {
      _currentDark = _targetDark;
    } else {
      _currentDark += (_targetDark - _currentDark) * factorFor(darkSpeed);
    }
  }

  /// 立即跳到目标值（用于强制布局，不产生过渡）。
  void snapToTarget() {
    _currentBright = _targetBright;
    _currentDark = _targetDark;
  }
}
