/// 三次贝塞尔缓动求值。
///
/// 移植 JS 侧 `bezier-easing` 包的算法（AMLL 用它构造强调动画的
/// `bezIn(0.2,0.4,0.58,1.0)` / `bezOut(0.3,0.0,0.58,1.0)`）。
///
/// 不能直接用 Flutter 的 [Cubic]：`Cubic.transform` 用的是二分法且强制
/// `t ∈ [0,1]` 断言，而这里需要与 JS 完全一致的采样表 + 牛顿迭代路径，
/// 才能保证辉光/位移曲线逐帧对齐。
library;

const int _kSplineTableSize = 11;
const double _kSampleStepSize = 1.0 / (_kSplineTableSize - 1.0);
const double _kNewtonIterations = 4;
const double _kNewtonMinSlope = 0.001;
const double _kSubdivisionPrecision = 0.0000001;
const int _kSubdivisionMaxIterations = 10;

double _a(double aA1, double aA2) => 1.0 - 3.0 * aA2 + 3.0 * aA1;
double _b(double aA1, double aA2) => 3.0 * aA2 - 6.0 * aA1;
double _c(double aA1) => 3.0 * aA1;

/// 计算 t 处的贝塞尔坐标值
double _calcBezier(double aT, double aA1, double aA2) =>
    ((_a(aA1, aA2) * aT + _b(aA1, aA2)) * aT + _c(aA1)) * aT;

/// 计算 t 处的斜率
double _getSlope(double aT, double aA1, double aA2) =>
    3.0 * _a(aA1, aA2) * aT * aT + 2.0 * _b(aA1, aA2) * aT + _c(aA1);

double _binarySubdivide(
  double aX,
  double aA,
  double aB,
  double mX1,
  double mX2,
) {
  var a = aA;
  var b = aB;
  double currentX;
  double currentT;
  var i = 0;
  do {
    currentT = a + (b - a) / 2.0;
    currentX = _calcBezier(currentT, mX1, mX2) - aX;
    if (currentX > 0.0) {
      b = currentT;
    } else {
      a = currentT;
    }
  } while (currentX.abs() > _kSubdivisionPrecision &&
      ++i < _kSubdivisionMaxIterations);
  return currentT;
}

double _newtonRaphsonIterate(double aX, double aGuessT, double mX1, double mX2) {
  var guess = aGuessT;
  for (var i = 0; i < _kNewtonIterations; i++) {
    final currentSlope = _getSlope(guess, mX1, mX2);
    if (currentSlope == 0.0) return guess;
    final currentX = _calcBezier(guess, mX1, mX2) - aX;
    guess -= currentX / currentSlope;
  }
  return guess;
}

/// 一条三次贝塞尔缓动曲线。
///
/// 用采样表定位区间后按斜率选择牛顿迭代或二分求逆，与 `bezier-easing` 一致。
class BezierEasing {
  BezierEasing(this.mX1, this.mY1, this.mX2, this.mY2)
    : assert(
        mX1 >= 0 && mX1 <= 1 && mX2 >= 0 && mX2 <= 1,
        'bezier x 值必须落在 [0, 1] 内',
      ),
      _isLinear = mX1 == mY1 && mX2 == mY2 {
    if (!_isLinear) {
      for (var i = 0; i < _kSplineTableSize; i++) {
        _sampleValues[i] = _calcBezier(i * _kSampleStepSize, mX1, mX2);
      }
    }
  }

  final double mX1;
  final double mY1;
  final double mX2;
  final double mY2;

  final bool _isLinear;
  final List<double> _sampleValues = List<double>.filled(_kSplineTableSize, 0);

  double _getTForX(double aX) {
    var intervalStart = 0.0;
    var currentSample = 1;
    const lastSample = _kSplineTableSize - 1;

    while (currentSample != lastSample && _sampleValues[currentSample] <= aX) {
      intervalStart += _kSampleStepSize;
      currentSample++;
    }
    currentSample--;

    // 在当前采样区间内线性插值出初始猜测
    final dist =
        (aX - _sampleValues[currentSample]) /
        (_sampleValues[currentSample + 1] - _sampleValues[currentSample]);
    final guessForT = intervalStart + dist * _kSampleStepSize;

    final initialSlope = _getSlope(guessForT, mX1, mX2);
    if (initialSlope >= _kNewtonMinSlope) {
      return _newtonRaphsonIterate(aX, guessForT, mX1, mX2);
    }
    if (initialSlope == 0.0) return guessForT;
    return _binarySubdivide(
      aX,
      intervalStart,
      intervalStart + _kSampleStepSize,
      mX1,
      mX2,
    );
  }

  /// 求 x 处的缓动值。端点直接返回，避免数值误差。
  double transform(double x) {
    if (_isLinear) return x;
    if (x == 0.0) return 0.0;
    if (x == 1.0) return 1.0;
    return _calcBezier(_getTForX(x), mY1, mY2);
  }

  double call(double x) => transform(x);
}
