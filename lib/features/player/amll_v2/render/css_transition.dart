/// CSS `transition` 的最小实现。
///
/// 上游的不透明度与模糊过渡完全依赖样式表里的 `transition`
/// （`.lyricMainLine { transition: opacity 0.3s 0.1s }` 等）。浏览器里这是
/// 隐式的，移植时必须显式补出来，否则行切换会是硬跳变而不是淡入淡出。
library;

import 'dart:math' as math;

import '../core/easing.dart';

/// CSS `transition-timing-function` 的默认值 `ease`。
final V2BezierEasing cssEase = V2BezierEasing(0.25, 0.1, 0.25, 1.0);

class V2CssTransition {
  V2CssTransition({
    required double initialValue,
    required this.durationMs,
    this.delayMs = 0,
    V2BezierEasing? easing,
  }) : _from = initialValue,
       _to = initialValue,
       _current = initialValue,
       easing = easing ?? cssEase;

  final double durationMs;
  final double delayMs;
  final V2BezierEasing easing;

  double _from;
  double _to;
  double _current;
  double _elapsed = 0;
  bool _running = false;

  double get value => _current;

  /// 立刻跳到某个值，不产生过渡（对应元素刚插入 DOM 的初始状态）。
  void jumpTo(double v) {
    _from = v;
    _to = v;
    _current = v;
    _elapsed = 0;
    _running = false;
  }

  /// 设置目标值。与浏览器一致：中途改目标会以**当前值**为新起点重新计时。
  void setTarget(double v) {
    if (v == _to) return;
    _from = _current;
    _to = v;
    _elapsed = 0;
    _running = true;
  }

  void update(double deltaMs) {
    if (!_running) return;
    _elapsed += deltaMs;
    final t = _elapsed - delayMs;
    if (t <= 0) return;
    if (durationMs <= 0 || t >= durationMs) {
      _current = _to;
      _running = false;
      return;
    }
    _current = _from + (_to - _from) * easing(math.min(1, t / durationMs));
  }
}
