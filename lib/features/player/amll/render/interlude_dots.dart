/// 间奏呼吸点。
///
/// 1:1 移植 AMLL 的 `InterludeDots`：三个圆点整体做呼吸缩放，
/// 逐点瀑布式提亮，进场用 easeOutExpo，退场用 easeInOutBack 回弹。
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

double _clamp(double x, double min, double max) =>
    x < min ? min : (x > max ? max : x);
double _clamp01(double x) => _clamp(x, 0, 1);
double _clampPositive(double x) => x < 0 ? 0 : x;

double _easeInOutBack(double x) {
  const c1 = 1.70158;
  const c2 = c1 * 1.525;
  return x < 0.5
      ? (math.pow(2 * x, 2) * ((c2 + 1) * 2 * x - c2)) / 2
      : (math.pow(2 * x - 2, 2) * ((c2 + 1) * (x * 2 - 2) + c2) + 2) / 2;
}

double _easeOutExpo(double x) =>
    x == 1 ? 1 : 1 - math.pow(2, -10 * x).toDouble();

/// 间奏点的瞬时状态。
class InterludeDotsState {
  const InterludeDotsState({
    required this.scale,
    required this.dotOpacities,
  });

  static const InterludeDotsState hidden = InterludeDotsState(
    scale: 0,
    dotOpacities: <double>[0, 0, 0],
  );

  /// 整体缩放
  final double scale;

  /// 三个点各自的不透明度
  final List<double> dotOpacities;

  bool get isVisible => scale > 0.01;
}

/// 间奏点的动画解算器。
///
/// 状态只由「间奏区间 + 当前时间」决定，因此可以直接按时间求值，
/// 不需要自己累加 delta（原实现用 delta 累加是因为 DOM 侧没有可靠时钟）。
class InterludeDotsAnimation {
  /// 呼吸周期的目标时长
  static const double targetBreatheDuration = 1500;

  /// 求 [currentTimeMs] 处的状态。
  ///
  /// [startTime] / [endTime] 是间奏区间（毫秒）。
  static InterludeDotsState stateAt({
    required int currentTimeMs,
    required int startTime,
    required int endTime,
  }) {
    final interludeDuration = (endTime - startTime).toDouble();
    if (interludeDuration <= 0) return InterludeDotsState.hidden;

    final currentDuration = (currentTimeMs - startTime).toDouble();
    if (currentDuration < 0 || currentDuration > interludeDuration) {
      return InterludeDotsState.hidden;
    }

    final breatheCount = (interludeDuration / targetBreatheDuration).ceil();
    final breatheDuration = interludeDuration / breatheCount;

    var scale = 1.0;
    var globalOpacity = 1.0;

    // 呼吸：正弦轻微起伏
    scale *=
        math.sin(1.5 * math.pi - (currentDuration / breatheDuration) * 2) / 20 +
        1;

    // 进场缩放
    if (currentDuration < 2000) {
      scale *= _easeOutExpo(_clamp01(currentDuration / 2000));
    }

    // 进场渐显
    if (currentDuration < 500) {
      globalOpacity = 0;
    } else if (currentDuration < 1000) {
      globalOpacity *= (currentDuration - 500) / 500;
    }

    // 退场回弹缩放
    final remaining = interludeDuration - currentDuration;
    if (remaining < 750) {
      scale *= 1 - _easeInOutBack(_clamp01((750 - remaining) / 750 / 2));
    }
    // 退场渐隐
    if (remaining < 375) {
      globalOpacity *= _clamp01(remaining / 375);
    }

    final dotsDuration = _clampPositive(interludeDuration - 750);
    scale = _clampPositive(scale) * 0.7;

    double rawDotOpacity(double t) {
      if (dotsDuration <= 0) return 0.25;
      return _clamp((t * 3 / dotsDuration) * 0.75, 0.25, 1);
    }

    double finalize(double v) => _clamp01(globalOpacity * v);

    return InterludeDotsState(
      scale: scale,
      dotOpacities: <double>[
        finalize(rawDotOpacity(currentDuration)),
        finalize(rawDotOpacity(currentDuration - dotsDuration / 3)),
        finalize(rawDotOpacity(currentDuration - (dotsDuration / 3) * 2)),
      ],
    );
  }
}

/// 间奏点的绘制。
class InterludeDotsPainter extends CustomPainter {
  const InterludeDotsPainter({
    required this.state,
    required this.color,
    required this.dotSize,
    required this.gap,
    required this.alignRight,
  });

  final InterludeDotsState state;
  final Color color;
  final double dotSize;
  final double gap;

  /// 对唱时靠右对齐
  final bool alignRight;

  /// 三个点排布所需的宽度
  static double widthFor(double dotSize, double gap) => dotSize * 3 + gap * 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (!state.isVisible) return;

    final totalWidth = widthFor(dotSize, gap);
    final originX = alignRight ? size.width - totalWidth : 0.0;
    final centerY = size.height / 2;

    canvas.save();
    // 以整组的中心为锚点缩放
    final anchorX = originX + totalWidth / 2;
    canvas.translate(anchorX, centerY);
    canvas.scale(state.scale);
    canvas.translate(-anchorX, -centerY);

    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 3; i++) {
      final opacity = i < state.dotOpacities.length
          ? state.dotOpacities[i]
          : 0.0;
      if (opacity <= 0.001) continue;
      paint.color = color.withValues(alpha: opacity);
      final cx = originX + dotSize / 2 + i * (dotSize + gap);
      canvas.drawCircle(Offset(cx, centerY), dotSize / 2, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(InterludeDotsPainter old) =>
      old.state.scale != state.scale ||
      !_sameOpacities(old.state.dotOpacities, state.dotOpacities) ||
      old.color != color ||
      old.dotSize != dotSize ||
      old.gap != gap ||
      old.alignRight != alignRight;

  static bool _sameOpacities(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
