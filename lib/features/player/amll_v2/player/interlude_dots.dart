/// 1:1 移植 `lyric-player/dom/interlude-dots.ts`。
///
/// 只保留状态计算；DOM 里靠 `transform` / `opacity` 表达的结果，这里变成
/// [scale] 与 [dotOpacities] 两个字段，由绘制层读取。
library;

import 'dart:math' as math;

double _easeInOutBack(double x) {
  const c1 = 1.70158;
  const c2 = c1 * 1.525;
  final v = x < 0.5
      ? (math.pow(2 * x, 2) * ((c2 + 1) * 2 * x - c2)) / 2
      : (math.pow(2 * x - 2, 2) * ((c2 + 1) * (x * 2 - 2) + c2) + 2) / 2;
  return v.toDouble();
}

double _easeOutExpo(double x) =>
    x == 1 ? 1 : (1 - math.pow(2, -10 * x)).toDouble();

double _clamp(double min, double cur, double max) =>
    math.max(min, math.min(cur, max));

class V2InterludeDots {
  double left = 0;
  double top = 0;
  bool _playing = true;

  /// `[开始时间, 结束时间]`，单位毫秒
  List<int>? _currentInterlude;
  double _currentTime = 0;

  /// `targetBreatheDuration`
  final double targetBreatheDuration = 1500;

  /// `.interludeDots { opacity: 0 }` / `.enabled { opacity: 1 }`
  bool get enabled => _currentInterlude != null;

  /// 整体缩放，`transform: ... scale(x)`
  double scale = 0;

  /// 三个圆点各自的 opacity
  final List<double> dotOpacities = <double>[0, 0, 0];

  void setTransform(double left, double top) {
    this.left = left;
    this.top = top;
    update();
  }

  void setInterlude(List<int>? interlude) {
    _currentInterlude = interlude;
    _currentTime = (interlude?[0] ?? 0).toDouble();
  }

  void pause() => _playing = false;
  void resume() => _playing = true;

  void update([double delta = 0]) {
    if (!_playing) return;
    _currentTime += delta;
    final interlude = _currentInterlude;
    if (interlude == null) return;

    final interludeDuration = (interlude[1] - interlude[0]).toDouble();
    final currentDuration = _currentTime - interlude[0];
    if (currentDuration <= interludeDuration) {
      final breatheDuration =
          interludeDuration /
          (interludeDuration / targetBreatheDuration).ceil();
      var s = 1.0;
      var globalOpacity = 1.0;

      s *=
          math.sin(1.5 * math.pi - (currentDuration / breatheDuration) * 2) /
              20 +
          1;

      if (currentDuration < 2000) {
        s *= _easeOutExpo(currentDuration / 2000);
      }

      if (currentDuration < 500) {
        globalOpacity = 0;
      } else if (currentDuration < 1000) {
        globalOpacity *= (currentDuration - 500) / 500;
      }

      if (interludeDuration - currentDuration < 750) {
        s *=
            1 -
            _easeInOutBack(
              (750 - (interludeDuration - currentDuration)) / 750 / 2,
            );
      }
      if (interludeDuration - currentDuration < 375) {
        globalOpacity *= _clamp(
          0,
          (interludeDuration - currentDuration) / 375,
          1,
        );
      }

      final dotsDuration = math.max(0.0, interludeDuration - 750);

      scale = math.max(0, s) * 0.7;

      final dot0 = _clamp(
        0.25,
        ((currentDuration * 3) / dotsDuration) * 0.75,
        1,
      );
      final dot1 = _clamp(
        0.25,
        (((currentDuration - dotsDuration / 3) * 3) / dotsDuration) * 0.75,
        1,
      );
      final dot2 = _clamp(
        0.25,
        (((currentDuration - (dotsDuration / 3) * 2) * 3) / dotsDuration) *
            0.75,
        1,
      );

      dotOpacities[0] = _clamp(0, math.max(0, globalOpacity * dot0), 1);
      dotOpacities[1] = _clamp(0, math.max(0, globalOpacity * dot1), 1);
      dotOpacities[2] = _clamp(0, math.max(0, globalOpacity * dot2), 1);
    } else {
      scale = 0;
      dotOpacities[0] = 0;
      dotOpacities[1] = 0;
      dotOpacities[2] = 0;
    }
  }
}
