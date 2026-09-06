/// 「莫奈」背景的 AE-wiggle 式漂移。
///
/// 逐行移植自上游 `src/components/visualizer/backgrounds/monet/
/// monetBackgroundDrift.ts`：分形值噪声采样成一条很长、且首尾严格闭合的关键帧
/// 轨道。上游把它交给 Web Animations API 播（线性缓动、逐段插值），所以这里也
/// 只做「按等间隔采样 + 线性插值」，不要换成连续求值——那会得到一条比原版更平滑
/// 的曲线，抖动的手感就没了。
///
/// 元素被预先放大到超过两倍最大位移，这才是平移永远拖不出图片边缘的原因。
library;

import 'dart:math' as math;

/// 噪声点阵跑完一整圈的时长。长到看不出这是个循环。
const double kMonetDriftLoopSeconds = 240;

/// 一圈里的点阵格数。间距约 4.6s，即每 ~9s 抖一下。
const int _kLatticePoints = 76;

/// 一圈里发出的采样数。每格三个采样，逐段线性播放才不会出现可见的折角。
const int _kSampleCount = 156;

/// strength = 1 时的位移与呼吸幅度。
const double _kMaxTravelPercent = 3.4;
const double _kBreathAmplitude = 0.035;

/// 几何最小值之上的余量，保证取整永远不会露出边缘。
const double _kOverscanMargin = 0.01;

/// 三条通道各自的点阵；偏移量让 x、y、缩放不会同步运动。
const double _kSeedX = 12.9898;
const double _kSeedY = 78.233;
const double _kSeedScale = 39.425;

/// 漂移轨道在某一时刻的采样值。
class MonetDriftSample {
  const MonetDriftSample({
    required this.dxPercent,
    required this.dyPercent,
    required this.scale,
  });

  /// 平移量，单位是元素自身盒子的百分比（与 CSS `translate3d(x%, y%)` 一致）。
  final double dxPercent;
  final double dyPercent;
  final double scale;

  static const zero = MonetDriftSample(dxPercent: 0, dyPercent: 0, scale: 1);
}

/// 一条按 strength（0..1）解算好的漂移轨道。
///
/// 解算是纯 CPU 的三条 157 长度数组，构造一次即可反复采样；同一 strength 会命中
/// [MonetDriftTrack.of] 的缓存，页面里多个图层不会各算一遍。
class MonetDriftTrack {
  MonetDriftTrack._(
    this._x,
    this._y,
    this._scale, {
    required this.travelPercent,
    required this.minScale,
    required this.breath,
  });

  /// 按 [strength] 取（并缓存）一条轨道。
  factory MonetDriftTrack.of(double strength) {
    final clamped = math.min(1.0, math.max(0.0, strength));
    // 量化到 0.01，避免调节滑块时把缓存打穿。
    final key = (clamped * 100).round();
    return _cache.putIfAbsent(key, () => MonetDriftTrack._build(key / 100));
  }

  static MonetDriftTrack _build(double strength) {
    final travelPercent = _kMaxTravelPercent * strength;
    final minScale = 1 + (travelPercent / 100) * 2 + _kOverscanMargin;
    final breath = _kBreathAmplitude * strength;

    final rawX = <double>[];
    final rawY = <double>[];
    final rawScale = <double>[];
    for (var index = 0; index <= _kSampleCount; index++) {
      final t = (_kLatticePoints * index) / _kSampleCount;
      rawX.add(_periodicFbm(t, _kSeedX));
      rawY.add(_periodicFbm(t, _kSeedY));
      rawScale.add(_periodicFbm(t, _kSeedScale));
    }

    return MonetDriftTrack._(
      _normalize(rawX),
      _normalize(rawY),
      _normalize(rawScale),
      travelPercent: travelPercent,
      minScale: minScale,
      breath: breath,
    );
  }

  static final Map<int, MonetDriftTrack> _cache = {};

  final List<double> _x;
  final List<double> _y;
  final List<double> _scale;

  /// 任一关键帧达到的最大 |平移|，占元素自身盒子的百分比。
  final double travelPercent;

  /// 任一关键帧的最小缩放；必须大于 1 + 2 × travelPercent 才能藏住边缘。
  final double minScale;
  final double breath;

  /// 按循环进度（0..1，允许越界，会自行取模）采样。
  MonetDriftSample sampleAt(double progress) {
    final wrapped = _wrap(progress, 1);
    final position = wrapped * _kSampleCount;
    final index = position.floor().clamp(0, _kSampleCount - 1);
    final fraction = position - index;

    final x = _lerp(_x[index], _x[index + 1], fraction);
    final y = _lerp(_y[index], _y[index + 1], fraction);
    final scale = _lerp(_scale[index], _scale[index + 1], fraction);

    return MonetDriftSample(
      dxPercent: x * travelPercent,
      dyPercent: y * travelPercent,
      scale: minScale + breath * ((scale + 1) / 2),
    );
  }
}

double _wrap(double value, double modulus) =>
    ((value % modulus) + modulus) % modulus;

double _lerp(double from, double to, double t) => from + (to - from) * t;

double _hash(int lattice, double seed) {
  final value = math.sin(lattice * 127.1 + seed * 311.7) * 43758.5453;
  return value - value.floorToDouble();
}

double _smoothstep(double t) => t * t * (3 - 2 * t);

/// 每 [points] 格严格重复一次的值噪声，轨道因此首尾闭合。
double _periodicNoise(double t, int points, double seed) {
  final cell = t.floor();
  final from = _hash(_wrapInt(cell, points), seed);
  final to = _hash(_wrapInt(cell + 1, points), seed);
  return from + (to - from) * _smoothstep(t - cell);
}

int _wrapInt(int value, int modulus) => ((value % modulus) + modulus) % modulus;

/// 两个八度的周期噪声，以 0 为中心。第二个八度提供更细的 AE 味抖动。
double _periodicFbm(double t, double seed) {
  final base = _periodicNoise(t, _kLatticePoints, seed);
  final detail = _periodicNoise(t * 2, _kLatticePoints * 2, seed + 17.31);
  return (base * 0.68 + detail * 0.32) * 2 - 1;
}

/// 把一条通道缩放到极值恰好落在 ±1，位移预算才是精确的。
List<double> _normalize(List<double> samples) {
  var peak = 0.0;
  for (final value in samples) {
    peak = math.max(peak, value.abs());
  }
  if (peak <= 0) return samples;
  return [for (final value in samples) value / peak];
}
