import 'dart:math' as math;

/// 弹簧参数。
///
/// 1:1 移植 `@applemusic-like-lyrics/core` 的 `SpringParams`
/// （原实现基于 MIT License github.com/pushkine/）。
class SpringParams {
  const SpringParams({this.mass, this.damping, this.stiffness, this.soft});

  /// 质量，默认 1.0
  final double? mass;

  /// 阻尼，默认 10.0
  final double? damping;

  /// 弹力，默认 100.0
  final double? stiffness;

  /// 是否强制使用过阻尼解，默认 false
  final bool? soft;

  /// 用本对象里非空的字段覆盖 [base]，未提供的字段保持原样。
  SpringParams merge(SpringParams? other) {
    if (other == null) return this;
    return SpringParams(
      mass: other.mass ?? mass,
      damping: other.damping ?? damping,
      stiffness: other.stiffness ?? stiffness,
      soft: other.soft ?? soft,
    );
  }
}

/// 单个待生效的延迟参数变更。
class _QueuedParams {
  _QueuedParams(this.params, this.time);

  SpringParams params;
  double time;
}

/// 单个待生效的延迟目标位置。
class _QueuedPosition {
  _QueuedPosition(this.position, this.time);

  double position;
  double time;
}

/// 解析解弹簧。
///
/// 与基于时长的补间不同，切换目标位置时会把**当前速度**带入新的解析解
/// （见 [_resetSolver]），因此连续切换目标时位移一阶连续，不会产生顿挫。
/// 这是 AMLL 歌词滚动手感的核心。
///
/// 时间单位为**秒**。
class Spring {
  Spring([double currentPosition = 0])
    : _targetPosition = currentPosition,
      _currentPosition = currentPosition {
    _currentSolver = (_) => _targetPosition;
    _getV = (_) => 0;
    _getV2 = (_) => 0;
  }

  double _currentPosition;
  double _targetPosition;
  double _currentTime = 0;
  SpringParams _params = const SpringParams();

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
      params: _params,
    );
    _getV = _derivative(_currentSolver);
    _getV2 = _derivative(_getV);
  }

  /// 是否已经收敛到目标位置。
  ///
  /// 判据与原实现一致：位移误差 < 0.01，且一阶、二阶数值导数均 < 0.01，
  /// 且没有待生效的延迟变更。
  bool arrived() {
    return (_targetPosition - _currentPosition).abs() < 0.01 &&
        _getV(_currentTime) < 0.01 &&
        _getV2(_currentTime) < 0.01 &&
        _queueParams == null &&
        _queuePosition == null;
  }

  /// 立即把位置与目标一起设为 [targetPosition]，速度归零（不产生动画）。
  void setPosition(double targetPosition) {
    _targetPosition = targetPosition;
    _currentPosition = targetPosition;
    _currentSolver = (_) => _targetPosition;
    _getV = (_) => 0;
    _getV2 = (_) => 0;
  }

  /// 推进 [delta] 秒。
  void update([double delta = 0]) {
    _currentTime += delta;
    _currentPosition = _currentSolver(_currentTime);

    final queuedParams = _queueParams;
    if (queuedParams != null) {
      queuedParams.time -= delta;
      if (queuedParams.time <= 0) {
        updateParams(queuedParams.params);
      }
    }

    final queuedPosition = _queuePosition;
    if (queuedPosition != null) {
      queuedPosition.time -= delta;
      if (queuedPosition.time <= 0) {
        setTargetPosition(queuedPosition.position);
      }
    }

    if (arrived()) {
      setPosition(_targetPosition);
    }
  }

  /// 更新弹簧参数，[delay] 秒后生效（0 表示立即）。
  void updateParams(SpringParams params, [double delay = 0]) {
    if (delay > 0) {
      _queueParams = _QueuedParams(params, delay);
    } else {
      _queuePosition = null;
      _params = _params.merge(params);
      _resetSolver();
    }
  }

  /// 设置目标位置，[delay] 秒后生效（0 表示立即）。
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

  double getTargetPosition() => _targetPosition;
}

/// 数值微分，步长与原实现的 `derivative.ts` 一致（h = 0.001，中心差分）。
double Function(double) _derivative(double Function(double) f) {
  const h = 0.001;
  return (double x) => (f(x + h) - f(x - h)) / (2 * h);
}

/// 求解弹簧运动的解析解。
///
/// 过阻尼/临界阻尼走指数解，欠阻尼走衰减振荡解。
double Function(double t) _solveSpring(
  double from,
  double velocity,
  double to, {
  double delay = 0,
  SpringParams? params,
}) {
  final soft = params?.soft ?? false;
  final stiffness = params?.stiffness ?? 100;
  final damping = params?.damping ?? 10;
  final mass = params?.mass ?? 1;
  final delta = to - from;

  if (soft || damping / (2.0 * math.sqrt(stiffness * mass)) >= 1.0) {
    final angularFrequency = -math.sqrt(stiffness / mass);
    final leftover = -angularFrequency * delta - velocity;
    return (double t) {
      final tt = t - delay;
      if (tt < 0) return from;
      return to - (delta + tt * leftover) * math.exp(tt * angularFrequency);
    };
  }

  final dampingFrequency = math.sqrt(4.0 * mass * stiffness - damping * damping);
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
