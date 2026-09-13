/// 1:1 移植 `dom/lyric-line.ts` 里的三组 Web Animations：
///
/// - `initFloatAnimation`：整词上浮
/// - `initEmphasizeAnimation`：强调词的逐字缩放 / 位移 / 辉光
/// - `generateWebAnimationBasedMaskImage`：逐字渐变遮罩的关键帧
///
/// 浏览器对关键帧数组做的是**线性插值**，所以这里也保留 32 段采样再插值，
/// 而不是直接取解析式——两者有约 1/32 的相位差，逐像素对齐就得照抄采样。
library;

import 'dart:math' as math;

import '../core/easing.dart';
import '../core/interfaces.dart';

/// `ANIMATION_FRAME_QUANTITY`
const int kAnimationFrameQuantity = 32;

/// `LyricLineBase.shouldEmphasize`
bool shouldEmphasize(V2LyricWord word, bool Function(String) isCJK) {
  if (isCJK(word.word)) return word.endTime - word.startTime >= 1000;
  return word.endTime - word.startTime >= 1000 &&
      word.word.trim().length <= 7 &&
      word.word.trim().length > 1;
}

// ---------------------------------------------------------------- 整词上浮

/// `initFloatAnimation` 的求值形式。位移单位是 em。
class V2FloatAnimation {
  V2FloatAnimation({
    required this.delayMs,
    required this.durationMs,
    required this.up,
  });

  /// `word.startTime - line.startTime`
  final double delayMs;

  /// `Math.max(1000, word.endTime - word.startTime)`
  final double durationMs;

  /// `0.05`，背景人声行翻倍
  final double up;

  /// 返回 translateY，单位 em（负值向上）。
  double translateYEm(double timeMs) {
    if (durationMs <= 0) return -up;
    final x = ((timeMs - delayMs) / durationMs).clamp(0.0, 1.0);
    return -up * cssEaseOut(x);
  }
}

// ------------------------------------------------------------ 强调（逐字）

/// 单个字符在某一时刻的强调状态。
class V2EmphasizeState {
  const V2EmphasizeState({
    required this.scale,
    required this.offsetXEm,
    required this.offsetYEm,
    required this.floatYEm,
    required this.glowAlpha,
    required this.glowBlurEm,
  });

  static const V2EmphasizeState identity = V2EmphasizeState(
    scale: 1,
    offsetXEm: 0,
    offsetYEm: 0,
    floatYEm: 0,
    glowAlpha: 0,
    glowBlurEm: 0,
  );

  final double scale;
  final double offsetXEm;
  final double offsetYEm;

  /// `emphasize-word-float`（composite: add，叠在 [offsetYEm] 之上）
  final double floatYEm;

  final double glowAlpha;
  final double glowBlurEm;
}

/// `initEmphasizeAnimation` 的求值形式。
class V2EmphasizeAnimation {
  V2EmphasizeAnimation._({
    required this.charCount,
    required this.de,
    required this.du,
    required this.amount,
    required this.blur,
    required this.isBG,
  });

  /// 依 `initEmphasizeAnimation` 的头部计算推导参数。
  ///
  /// [word] 是合并后的词（连写组）或单词本身，[lineWords] 是所属行的原始词表，
  /// [charCount] 是参与动画的字符数。
  factory V2EmphasizeAnimation({
    required V2LyricWord word,
    required List<V2LyricWord> lineWords,
    required int charCount,
    required double duration,
    required double delay,
    required bool isBG,
  }) {
    final de = math.max(0.0, delay);
    var du = math.max(1000.0, duration);

    var amount = du / 2000;
    amount = amount > 1 ? math.sqrt(amount) : amount * amount * amount;
    var blur = du / 3000;
    blur = blur > 1 ? math.sqrt(blur) : blur * blur * blur;
    amount *= 0.6;
    blur *= 0.5;
    if (lineWords.isNotEmpty && word.word.contains(lineWords.last.word)) {
      amount *= 1.6;
      blur *= 1.5;
      du *= 1.2;
    }
    amount = math.min(1.2, amount);
    blur = math.min(0.8, blur);

    return V2EmphasizeAnimation._(
      charCount: charCount,
      de: de,
      du: du,
      amount: amount,
      blur: blur,
      isBG: isBG,
    );
  }

  final int charCount;
  final double de;
  final double du;
  final double amount;
  final double blur;
  final bool isBG;

  /// `glow` 关键帧：`empEasing` 在 32 段采样点上的值，第 0 段是隐式的中性帧。
  static final List<double> _empSamples = List<double>.generate(
    kAnimationFrameQuantity + 1,
    (j) => j == 0
        ? 0.0
        : makeEmpEasing(kEmpEasingMid)(j / kAnimationFrameQuantity),
  );

  /// `float` 关键帧：`Math.sin(x * Math.PI)`。
  static final List<double> _sinSamples = List<double>.generate(
    kAnimationFrameQuantity + 1,
    (j) => j == 0 ? 0.0 : math.sin((j / kAnimationFrameQuantity) * math.pi),
  );

  static double _sampleLerp(List<double> samples, double x) {
    final p = x.clamp(0.0, 1.0) * kAnimationFrameQuantity;
    final i = p.floor().clamp(0, kAnimationFrameQuantity);
    if (i >= kAnimationFrameQuantity) return samples[kAnimationFrameQuantity];
    return samples[i] + (samples[i + 1] - samples[i]) * (p - i);
  }

  /// 第 [i] 个字符在行内时间 [timeMs]（相对行起始）上的状态。
  V2EmphasizeState stateOf(int i, double timeMs) {
    final n = charCount;
    if (n <= 0) return V2EmphasizeState.identity;
    final wordDe = de + (du / 2.5 / n) * i;

    // glow：duration = du，delay = wordDe
    final gx = du <= 0 ? 1.0 : ((timeMs - wordDe) / du).clamp(0.0, 1.0);
    final transX = _sampleLerp(_empSamples, gx);
    final glowLevel = transX * blur;

    // float：duration = du * 1.4，delay = wordDe - 400
    final fDu = du * 1.4;
    final fDe = wordDe - 400;
    final fx = fDu <= 0 ? 1.0 : ((timeMs - fDe) / fDu).clamp(0.0, 1.0);
    var y = _sampleLerp(_sinSamples, fx);
    if (isBG) y *= 2;

    return V2EmphasizeState(
      scale: 1 + transX * 0.1 * amount,
      offsetXEm: -transX * 0.03 * amount * (n / 2 - i),
      offsetYEm: -transX * 0.025 * amount,
      floatYEm: -y * 0.05,
      glowAlpha: glowLevel,
      glowBlurEm: math.min(0.3, blur * 0.3),
    );
  }
}

// --------------------------------------------------------------- 渐变遮罩

/// 一帧 `mask-position`。`offset` 是 `[0,1]` 的时间轴比例，`posPx` 是 x 偏移。
class V2MaskFrame {
  const V2MaskFrame(this.offset, this.posPx);
  final double offset;
  final double posPx;
}

/// 参与遮罩关键帧计算所需的每个词的度量。
class V2MaskWordMetric {
  const V2MaskWordMetric({
    required this.width,
    required this.padding,
    required this.startTime,
    required this.endTime,
  });

  /// `el.clientWidth - padding * 2`，即文字自身宽度
  final double width;

  /// `1em`
  final double padding;

  final int startTime;
  final int endTime;
}

/// 1:1 移植 `generateWebAnimationBasedMaskImage` 中针对第 [index] 个词的
/// 关键帧生成。[fadeWidth] = `word.height * wordFadeWidth`。
List<V2MaskFrame> buildMaskFrames({
  required List<V2MaskWordMetric> words,
  required int index,
  required int lineStartTime,
  required double totalFadeDuration,
  required double fadeWidth,
}) {
  final word = words[index];
  final minOffset = -(word.width + word.padding * 2 + fadeWidth);
  double clampOffset(double x) => math.max(minOffset, math.min(0, x));

  var widthBeforeSelf = 0.0;
  for (var k = 0; k < index; k++) {
    widthBeforeSelf += words[k].width;
  }
  // JS: `+ (this.splittedWords[0] ? fadeWidth : 0)`，词表非空即恒为真
  if (words.isNotEmpty) widthBeforeSelf += fadeWidth;

  var curPos = -widthBeforeSelf - word.width - word.padding - fadeWidth;
  var timeOffset = 0.0;
  final frames = <V2MaskFrame>[];
  var lastPos = curPos;
  var lastTime = 0.0;

  void pushFrame() {
    final moveOffset = curPos - lastPos;
    final time = math.max(0.0, math.min(1.0, timeOffset));
    final duration = time - lastTime;
    final d = (duration / moveOffset).abs();
    // 因为有可能会和之前的动画有边界
    if (curPos > minOffset && lastPos < minOffset) {
      final staticTime = (lastPos - minOffset).abs() * d;
      frames.add(V2MaskFrame(lastTime + staticTime, clampOffset(lastPos)));
    }
    if (curPos > 0 && lastPos < 0) {
      final staticTime = lastPos.abs() * d;
      frames.add(V2MaskFrame(lastTime + staticTime, clampOffset(curPos)));
    }
    frames.add(V2MaskFrame(time, clampOffset(curPos)));
    lastPos = curPos;
    lastTime = time;
  }

  pushFrame();
  var lastTimeStamp = 0.0;
  for (var j = 0; j < words.length; j++) {
    final otherWord = words[j];
    // 停顿
    {
      final curTimeStamp = (otherWord.startTime - lineStartTime).toDouble();
      final staticDuration = curTimeStamp - lastTimeStamp;
      timeOffset += staticDuration / totalFadeDuration;
      if (staticDuration > 0) pushFrame();
      lastTimeStamp = curTimeStamp;
    }
    // 移动
    {
      final fadeDuration = (otherWord.endTime - otherWord.startTime).toDouble();
      timeOffset += fadeDuration / totalFadeDuration;
      curPos += otherWord.width;
      if (j == 0) curPos += fadeWidth * 1.5;
      if (j == words.length - 1) curPos += fadeWidth * 0.5;
      if (fadeDuration > 0) pushFrame();
      lastTimeStamp += fadeDuration;
    }
  }

  return frames;
}

/// 按 `[0,1]` 的进度在关键帧上线性插值，取得当前的 `mask-position` x 偏移。
double evalMaskFrames(List<V2MaskFrame> frames, double progress) {
  if (frames.isEmpty) return 0;
  final p = progress.clamp(0.0, 1.0);
  if (p <= frames.first.offset) return frames.first.posPx;
  for (var i = 1; i < frames.length; i++) {
    final a = frames[i - 1];
    final b = frames[i];
    if (p <= b.offset) {
      final span = b.offset - a.offset;
      if (span <= 0) return b.posPx;
      return a.posPx + (b.posPx - a.posPx) * ((p - a.offset) / span);
    }
  }
  return frames.last.posPx;
}
