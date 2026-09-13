/// 1:1 移植 `@applemusic-like-lyrics/core` 的 `src/utils/spring.ts`
/// 与 `src/utils/derivative.ts`（原实现 MIT License github.com/pushkine/）。
///
/// 时间单位为**秒**，与 JS 侧一致（player 调用时传 `delta / 1000`）。
library;

import 'dart:math' as math;

/// 对应 `SpringParams`。全部可空，语义是「未提供的字段保持原样」。
class V2SpringParams {
  const V2SpringParams({this.mass, this.damping, this.stiffness, this.soft});

  final double? mass; // = 1.0
  final double? damping; // = 10.0
  final double? stiffness; // = 100.0
  final bool? soft; // = false

  /// 对应 JS 的 `{...this.params, ...params}`。
  V2SpringParams merged(V2SpringParams other) => V2SpringParams(
    mass: other.mass ?? mass,
    damping: other.damping ?? damping,
    stiffness: other.stiffness ?? stiffness,
    soft: other.soft ?? soft,
  );
}

class _QueuedParams {
  _QueuedParams(this.params, this.time);
  V2SpringParams params;
  double time;
}

class _QueuedPosition {
  _QueuedPosition(this.position, this.time);
  double position;
  double time;
}

/// 对应 `class Spring`。
class V2Spring {
  V2Spring([double currentPosition = 0])
    : _targetPosition = currentPosition,
      _currentPosition = currentPosition {
    _currentSolver = (_) => _targetPosition;
    _getV = (_) => 0;
    _getV2 = (_) => 0;
  }

  double _currentPosition;
  double _targetPosition;
  double _currentTime = 0;
  V2SpringParams _params = const V2SpringParams();

  late double Function(double t) _currentSolver;
  late double Function(double t) _getV;
  late double Function(double t) _getV2;

  _QueuedParams? _queueParams;
  _QueuedPosition? _queuePosition;

  void _resetSolver() {
    final curV = _getV(_currentTime);
    _currentTime = 0;
    _currentSolver = _solveSpring(
      _currentPosition,
      curV,
      _targetPosition,
      0,
      _params,
    );
    _getV = _getVelocity(_currentSolver);
    _getV2 = _getVelocity(_getV);
  }

  bool arrived() =>
      (_targetPosition - _currentPosition).abs() < 0.01 &&
      _getV(_currentTime) < 0.01 &&
      _getV2(_currentTime) < 0.01 &&
      _queueParams == null &&
      _queuePosition == null;

  void setPosition(double targetPosition) {
    _targetPosition = targetPosition;
    _currentPosition = targetPosition;
    _currentSolver = (_) => _targetPosition;
    _getV = (_) => 0;
    _getV2 = (_) => 0;
  }

  void update([double delta = 0]) {
    _currentTime += delta;
    _currentPosition = _currentSolver(_currentTime);
    final qp = _queueParams;
    if (qp != null) {
      qp.time -= delta;
      if (qp.time <= 0) updateParams(qp.params);
    }
    final qs = _queuePosition;
    if (qs != null) {
      qs.time -= delta;
      if (qs.time <= 0) setTargetPosition(qs.position);
    }
    if (arrived()) setPosition(_targetPosition);
  }

  void updateParams(V2SpringParams params, [double delay = 0]) {
    if (delay > 0) {
      _queueParams = _QueuedParams(params, delay);
    } else {
      _queuePosition = null;
      _params = _params.merged(params);
      _resetSolver();
    }
  }

  void setTargetPosition(double targetPosition, [double delay = 0]) {
    if (delay > 0) {
      _queuePosition = _QueuedPosition(targetPosition, delay);
    } else {
      _queuePosition = null;
      _targetPosition = targetPosition;
      _resetSolver();
    }
  }

  double getCurrentPosition() => _currentPosition;
}

/// `derivative.ts`：中心差分，步长 0.001。
double Function(double) _getVelocity(double Function(double) f) {
  const h = 0.001;
  return (double x) => (f(x + h) - f(x - h)) / (2 * h);
}

double Function(double) _solveSpring(
  double from,
  double velocity,
  double to,
  double delay,
  V2SpringParams? params,
) {
  final soft = params?.soft ?? false;
  final stiffness = params?.stiffness ?? 100;
  final damping = params?.damping ?? 10;
  final mass = params?.mass ?? 1;
  final delta = to - from;

  if (soft || 1.0 <= damping / (2.0 * math.sqrt(stiffness * mass))) {
    final angularFrequency = -math.sqrt(stiffness / mass);
    final leftover = -angularFrequency * delta - velocity;
    return (double t) {
      final tt = t - delay;
      if (tt < 0) return from;
      return to - (delta + tt * leftover) * math.exp(tt * angularFrequency);
    };
  }

  final dampingFrequency = math.sqrt(
    4.0 * mass * stiffness - damping * damping,
  );
  final leftover = (damping * delta - 2.0 * mass * velocity) / dampingFrequency;
  final dfm = (0.5 * dampingFrequency) / mass;
  final dm = -(0.5 * damping) / mass;
  return (double t) {
    final tt = t - delay;
    if (tt < 0) return from;
    return to -
        (math.cos(tt * dfm) * delta + math.sin(tt * dfm) * leftover) *
            math.exp(tt * dm);
  };
}
