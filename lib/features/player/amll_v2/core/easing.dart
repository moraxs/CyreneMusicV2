/// 1:1 移植 npm 包 `bezier-easing`（AMLL 的 `dom/lyric-line.ts` 直接依赖它），
/// 以及 CSS `ease-out` 关键字对应的 `cubic-bezier(0, 0, 0.58, 1)`。
///
/// 不用 Flutter 自带的 [Cubic]：那份实现是二分法且对 `t` 有 `[0,1]` 断言，
/// 采样点与 `bezier-easing` 的「11 点采样表 + 牛顿迭代」不同，逐帧取值会有
/// 肉眼可见的偏差，破坏「1:1」这条前提。
library;

const int _kSplineTableSize = 11;
const double _kSampleStepSize = 1.0 / (_kSplineTableSize - 1.0);
const int _kNewtonIterations = 4;
const double _kNewtonMinSlope = 0.001;
const double _kSubdivisionPrecision = 0.0000001;
const int _kSubdivisionMaxIterations = 10;

double _a(double aA1, double aA2) => 1.0 - 3.0 * aA2 + 3.0 * aA1;
double _b(double aA1, double aA2) => 3.0 * aA2 - 6.0 * aA1;
double _c(double aA1) => 3.0 * aA1;

double _calcBezier(double aT, double aA1, double aA2) =>
    ((_a(aA1, aA2) * aT + _b(aA1, aA2)) * aT + _c(aA1)) * aT;

double _getSlope(double aT, double aA1, double aA2) =>
    3.0 * _a(aA1, aA2) * aT * aT + 2.0 * _b(aA1, aA2) * aT + _c(aA1);

/// 三次贝塞尔缓动。
class V2BezierEasing {
  V2BezierEasing(this.mX1, this.mY1, this.mX2, this.mY2)
    : _linear = mX1 == mY1 && mX2 == mY2 {
    if (!_linear) {
      for (var i = 0; i < _kSplineTableSize; i++) {
        _sampleValues[i] = _calcBezier(i * _kSampleStepSize, mX1, mX2);
      }
    }
  }

  final double mX1, mY1, mX2, mY2;
  final bool _linear;
  final List<double> _sampleValues = List<double>.filled(_kSplineTableSize, 0);

  double _binarySubdivide(double aX, double aA, double aB) {
    double currentX, currentT;
    var i = 0;
    var a = aA;
    var b = aB;
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

  double _newtonRaphsonIterate(double aX, double aGuessT) {
    var t = aGuessT;
    for (var i = 0; i < _kNewtonIterations; i++) {
      final currentSlope = _getSlope(t, mX1, mX2);
      if (currentSlope == 0.0) return t;
      final currentX = _calcBezier(t, mX1, mX2) - aX;
      t -= currentX / currentSlope;
    }
    return t;
  }

  double _getTForX(double aX) {
    var intervalStart = 0.0;
    var currentSample = 1;
    const lastSample = _kSplineTableSize - 1;
    while (currentSample != lastSample && _sampleValues[currentSample] <= aX) {
      intervalStart += _kSampleStepSize;
      currentSample++;
    }
    currentSample--;

    final dist =
        (aX - _sampleValues[currentSample]) /
        (_sampleValues[currentSample + 1] - _sampleValues[currentSample]);
    final guessForT = intervalStart + dist * _kSampleStepSize;

    final initialSlope = _getSlope(guessForT, mX1, mX2);
    if (initialSlope >= _kNewtonMinSlope) {
      return _newtonRaphsonIterate(aX, guessForT);
    }
    if (initialSlope == 0.0) return guessForT;
    return _binarySubdivide(
      aX,
      intervalStart,
      intervalStart + _kSampleStepSize,
    );
  }

  double call(double x) {
    if (_linear) return x;
    if (x == 0) return 0;
    if (x == 1) return 1;
    return _calcBezier(_getTForX(x), mY1, mY2);
  }
}

// ---- lyric-line.ts 顶部那几个常量 ----

double Function(double) _norNum(double min, double max) =>
    (double x) => (x - min) / (max - min) < 0
    ? 0
    : ((x - min) / (max - min) > 1 ? 1 : (x - min) / (max - min));

/// `EMP_EASING_MID`
const double kEmpEasingMid = 0.5;

final _beginNum = _norNum(0, kEmpEasingMid);
final _endNum = _norNum(kEmpEasingMid, 1);

final V2BezierEasing bezIn = V2BezierEasing(0.2, 0.4, 0.58, 1.0);
final V2BezierEasing bezOut = V2BezierEasing(0.3, 0.0, 0.58, 1.0);

/// `makeEmpEasing(mid)`
double Function(double) makeEmpEasing(double mid) =>
    (double x) => x < mid ? bezIn(_beginNum(x)) : 1 - bezOut(_endNum(x));

/// CSS `ease-out` 关键字：`initFloatAnimation` 用的就是它。
final V2BezierEasing cssEaseOut = V2BezierEasing(0, 0, 0.58, 1.0);
