/// 词级动画曲线。
///
/// 把 AMLL 里那些用 Web Animations 关键帧表达的效果，改写成可以在
/// Flutter 逐帧直接求值的纯函数。关键帧在 JS 侧是 32 段采样后由浏览器
/// 插值，这里直接取解析式 —— 数值等价，且更平滑。
library;

import 'dart:math' as math;

import 'bezier_easing.dart';
import 'lyric_types.dart';

/// 强调缓动的分段中点，与 JS 侧 `EMP_EASING_MID` 一致。
const double kEmpEasingMid = 0.5;

final BezierEasing _bezIn = BezierEasing(0.2, 0.4, 0.58, 1.0);
final BezierEasing _bezOut = BezierEasing(0.3, 0.0, 0.58, 1.0);

double _norNum(double x, double min, double max) {
  final v = (x - min) / (max - min);
  return v < 0 ? 0 : (v > 1 ? 1 : v);
}

/// 强调动画的缓动：前半段用 [_bezIn] 升到 1，后半段用 [_bezOut] 落回 0。
///
/// 对应 JS 的 `makeEmpEasing(mid)`。
double empEasing(double x, [double mid = kEmpEasingMid]) {
  if (x < mid) return _bezIn.transform(_norNum(x, 0, mid));
  return 1 - _bezOut.transform(_norNum(x, mid, 1));
}

/// ease-out（CSS `ease-out` 即 cubic-bezier(0, 0, 0.58, 1)）
final BezierEasing _easeOut = BezierEasing(0, 0, 0.58, 1.0);

/// 词级浮动动画。
///
/// 每个词在自己的时间窗内向上浮动 0.05em（背景人声行加倍），ease-out。
/// 对应 `initFloatAnimation`：duration = max(1000, 词时长)，delay = 词相对行的偏移。
class WordFloatAnimation {
  WordFloatAnimation({
    required this.delayMs,
    required this.durationMs,
    required this.isBG,
  });

  /// 相对歌词行开始时间的延迟
  final double delayMs;

  /// 动画时长，至少 1000ms
  final double durationMs;

  /// 是否属于背景人声行（浮动幅度加倍）
  final bool isBG;

  factory WordFloatAnimation.forWord(AmllLyricWord word, int lineStartTime, {
    required bool isBG,
  }) {
    final delay = (word.startTime - lineStartTime).toDouble();
    final duration = math.max(1000, word.endTime - word.startTime).toDouble();
    return WordFloatAnimation(
      delayMs: delay.isFinite ? delay : 0,
      durationMs: duration.isFinite ? duration : 0,
      isBG: isBG,
    );
  }

  /// 求 [relativeTimeMs]（相对歌词行开始）处的纵向偏移，单位 em（向上为负）。
  double offsetEmAt(double relativeTimeMs) {
    if (durationMs <= 0) return 0;
    final t = (relativeTimeMs - delayMs) / durationMs;
    if (t <= 0) return 0;
    final progress = t >= 1 ? 1.0 : _easeOut.transform(t);
    final up = isBG ? 0.1 : 0.05;
    return -up * progress;
  }
}

/// 单个字素在强调动画中的瞬时状态。
class EmphasisState {
  const EmphasisState({
    required this.scale,
    required this.offsetXEm,
    required this.offsetYEm,
    required this.glowAlpha,
    required this.glowRadiusEm,
  });

  static const EmphasisState none = EmphasisState(
    scale: 1,
    offsetXEm: 0,
    offsetYEm: 0,
    glowAlpha: 0,
    glowRadiusEm: 0,
  );

  /// 缩放倍率
  final double scale;

  /// 横向偏移，单位 em
  final double offsetXEm;

  /// 纵向偏移（含强调自身的正弦浮动），单位 em
  final double offsetYEm;

  /// 辉光透明度
  final double glowAlpha;

  /// 辉光半径，单位 em
  final double glowRadiusEm;
}

/// 长词强调动画（缩放 + 轻微位移 + 辉光 + 正弦浮动）。
///
/// 对应 `initEmphasizeAnimation`。按原实现，强调只作用于缩放、位移与辉光，
/// 词级的基础浮动（[WordFloatAnimation]）依然独立叠加。
class EmphasisAnimation {
  EmphasisAnimation._({
    required this.delayMs,
    required this.durationMs,
    required this.amount,
    required this.blur,
    required this.charCount,
    required this.anchorCharCount,
    required this.isBG,
  });

  /// 相对歌词行开始时间的延迟
  final double delayMs;

  /// 动画时长（末词会被拉长 1.2 倍）
  final double durationMs;

  /// 缩放/位移幅度系数
  final double amount;

  /// 辉光强度系数
  final double blur;

  /// 参与强调的字素数量
  final int charCount;

  /// 逐字错峰所用的锚定字数（有 ruby 时按 ruby 字数）
  final int anchorCharCount;

  /// 是否属于背景人声行
  final bool isBG;

  /// 依据合并词构造强调动画。
  ///
  /// [isLastWordOfLine] 对应原实现里「该词包含行内最后一个词」的判定，
  /// 命中时幅度 ×1.6、辉光 ×1.5、时长 ×1.2。
  factory EmphasisAnimation.forWord({
    required int durationMs,
    required int delayMs,
    required int charCount,
    required int rubyCharCount,
    required bool isLastWordOfLine,
    required bool isBG,
  }) {
    final de = delayMs < 0 ? 0.0 : delayMs.toDouble();
    var du = math.max(1000, durationMs).toDouble();

    var amount = du / 2000;
    amount = amount > 1 ? math.sqrt(amount) : amount * amount * amount;
    var blur = du / 3000;
    blur = blur > 1 ? math.sqrt(blur) : blur * blur * blur;
    amount *= 0.6;
    blur *= 0.5;

    if (isLastWordOfLine) {
      amount *= 1.6;
      blur *= 1.5;
      du *= 1.2;
    }

    amount = math.min(1.2, amount);
    blur = math.min(0.8, blur);

    final anchor = rubyCharCount > 0 ? rubyCharCount : math.max(1, charCount);

    return EmphasisAnimation._(
      delayMs: de,
      durationMs: du.isFinite ? du : 0,
      amount: amount,
      blur: blur,
      charCount: charCount,
      anchorCharCount: anchor,
      isBG: isBG,
    );
  }

  /// 求第 [charIndex] 个字素在 [relativeTimeMs] 处的强调状态。
  EmphasisState stateAt(double relativeTimeMs, int charIndex) {
    if (durationMs <= 0 || charCount <= 0) return EmphasisState.none;

    // 逐字错峰：第 i 个字延后 du / 2.5 / anchorCharCount * i
    final charDelay = delayMs + (durationMs / 2.5 / anchorCharCount) * charIndex;

    // 主体（缩放 + 位移 + 辉光）
    var scale = 1.0;
    var offsetX = 0.0;
    var offsetY = 0.0;
    var glowAlpha = 0.0;

    final tMain = (relativeTimeMs - charDelay) / durationMs;
    if (tMain > 0) {
      // fill: both —— 超出末尾时保持末帧
      final x = tMain >= 1 ? 1.0 : tMain;
      final transX = empEasing(x);
      scale = 1 + transX * 0.1 * amount;
      offsetX = -transX * 0.03 * amount * (charCount / 2 - charIndex);
      offsetY = -transX * 0.025 * amount;
      glowAlpha = transX * blur;
    }

    // 另一路正弦浮动：时长 ×1.4，提前 400ms 开始
    final floatDuration = durationMs * 1.4;
    final floatDelay = charDelay - 400;
    if (floatDuration > 0) {
      final tFloat = (relativeTimeMs - floatDelay) / floatDuration;
      if (tFloat > 0) {
        final x = tFloat >= 1 ? 1.0 : tFloat;
        var y = math.sin(x * math.pi);
        if (isBG) y *= 2;
        offsetY += -y * 0.05;
      }
    }

    return EmphasisState(
      scale: scale,
      offsetXEm: offsetX,
      offsetYEm: offsetY,
      glowAlpha: glowAlpha,
      glowRadiusEm: math.min(0.3, blur * 0.3),
    );
  }
}
