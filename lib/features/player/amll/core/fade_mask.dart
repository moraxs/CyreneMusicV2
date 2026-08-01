/// 词级渐变遮罩的几何与时序。
///
/// AMLL 在 DOM 里的做法是：给每个词元素套一张三段式 `linear-gradient` 遮罩，
/// 宽度是词宽的若干倍，然后用 Web Animations 逐帧平移 `mask-position`，
/// 让「亮 → 暗」的分界线扫过整行（见 `generateWebAnimationBasedMaskImage`）。
///
/// 这里把它还原成一个可直接求值的函数：给定行内相对时间，得到每个词
/// 当前的遮罩偏移量（像素）。渲染层据此构造 shader，无需逐帧重建关键帧。
library;

import 'dart:math' as math;

/// 一个词在遮罩计算中所需的几何与时间信息。
class FadeMaskWord {
  FadeMaskWord({
    required this.startTime,
    required this.endTime,
    required this.width,
    this.padding = 0,
  });

  /// 起始时间（毫秒，绝对时间）
  final int startTime;

  /// 结束时间（毫秒，绝对时间）
  final int endTime;

  /// 词的绘制宽度（不含 padding）
  final double width;

  /// 词元素的水平内边距（DOM 侧用于扩大命中区域，几何上要补偿回来）
  final double padding;
}

/// 单个词的遮罩解算结果。
class FadeMaskSolution {
  const FadeMaskSolution({
    required this.fadeWidth,
    required this.minOffset,
    required this.keyframes,
    required this.geometry,
    required this.maskWidth,
  });

  /// 渐变过渡带宽度（像素）
  final double fadeWidth;

  /// 遮罩偏移的下界（完全未点亮）
  final double minOffset;

  /// 关键帧序列，按 [FadeKeyframe.time] 升序（time ∈ [0,1]）
  final List<FadeKeyframe> keyframes;

  /// 该词的遮罩渐变几何
  final FadeGradientGeometry geometry;

  /// 遮罩总宽（像素）
  final double maskWidth;

  /// 求 [progress] 处，亮区在词内的结束位置（像素，词左边缘为 0）。
  ///
  /// 遮罩以 [offsetAt] 的偏移贴在词上，亮区结束于
  /// `offset + brightStop * maskWidth`。
  double brightEdgeAt(double progress) =>
      offsetAt(progress) + geometry.brightStop * maskWidth;

  /// 求 [progress] 处，暗区在词内的开始位置（像素）。
  double darkEdgeAt(double progress) =>
      offsetAt(progress) + geometry.darkStop * maskWidth;

  /// 求 [progress]（0..1，相对整行渐变时长）处的遮罩偏移量。
  double offsetAt(double progress) {
    if (keyframes.isEmpty) return minOffset;
    if (progress <= keyframes.first.time) return keyframes.first.offset;
    if (progress >= keyframes.last.time) return keyframes.last.offset;

    // 关键帧数量不多（与词数同阶），线性查找足够
    for (var i = 0; i < keyframes.length - 1; i++) {
      final a = keyframes[i];
      final b = keyframes[i + 1];
      if (progress >= a.time && progress <= b.time) {
        final span = b.time - a.time;
        if (span <= 0) return b.offset;
        final t = (progress - a.time) / span;
        return a.offset + (b.offset - a.offset) * t;
      }
    }
    return keyframes.last.offset;
  }
}

/// 遮罩位移关键帧。
class FadeKeyframe {
  const FadeKeyframe(this.time, this.offset);

  /// 归一化时间，0..1
  final double time;

  /// 遮罩水平偏移（像素）
  final double offset;

  @override
  String toString() =>
      'FadeKeyframe(${time.toStringAsFixed(4)}, ${offset.toStringAsFixed(2)})';
}

/// 三段式渐变遮罩的几何。
///
/// 对应 `generateFadeGradient`：遮罩总宽是词宽的 `2 + w + padding` 倍，
/// 中间那段宽度占比 `w / totalAspect` 就是过渡带。
class FadeGradientGeometry {
  const FadeGradientGeometry({
    required this.totalAspect,
    required this.brightStop,
    required this.darkStop,
  });

  /// 遮罩总宽相对词宽的倍数
  final double totalAspect;

  /// 亮区结束位置（归一化到遮罩总宽）
  final double brightStop;

  /// 暗区开始位置（归一化到遮罩总宽）
  final double darkStop;
}

/// 计算三段式渐变遮罩的几何。
///
/// [widthRatio] 是过渡带宽度相对词宽（含 padding）的比值。
FadeGradientGeometry computeFadeGradient(double widthRatio, [double padding = 0]) {
  final totalAspect = 2 + widthRatio + padding;
  final widthInTotal = widthRatio / totalAspect;
  final leftPos = (1 - widthInTotal) / 2;
  return FadeGradientGeometry(
    totalAspect: totalAspect,
    brightStop: leftPos,
    darkStop: leftPos + widthInTotal,
  );
}

double _clamp01(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);

/// 为一行歌词解算每个词的遮罩位移关键帧。
///
/// 关键点（与原实现一致）：
/// - 整行渐变时长以「所有词的最晚结束时间」和行结束时间的较大者为准，
///   避免行比词早结束导致动画提前停止
/// - 每个词的起点位置要扣掉它前面所有词的宽度，这样分界线在整行上是连续的
/// - 首词额外 +1.5×fadeWidth、末词额外 +0.5×fadeWidth，用于衔接首尾
/// - 词与词之间的停顿会插入静止关键帧
///
/// [wordFadeWidth] 是过渡带宽度相对**词高**的倍数（AMLL 默认 0.5，
/// tauri 端设为 1.0）。
List<FadeMaskSolution> solveLineFadeMask({
  required List<FadeMaskWord> words,
  required int lineStartTime,
  required int lineEndTime,
  required double wordHeight,
  required double wordFadeWidth,
}) {
  if (words.isEmpty) return const [];

  final fadeWidth = wordHeight * wordFadeWidth;

  var latestWordEnd = 0;
  for (final w in words) {
    if (w.endTime > latestWordEnd) latestWordEnd = w.endTime;
  }
  final totalFadeDuration =
      math.max(math.max(0, latestWordEnd), lineEndTime) - lineStartTime;
  final safeDuration = totalFadeDuration <= 0 ? 1 : totalFadeDuration;

  final solutions = <FadeMaskSolution>[];

  for (var i = 0; i < words.length; i++) {
    final word = words[i];

    final ratio = fadeWidth / (word.width + word.padding * 2);
    final geometry = computeFadeGradient(ratio);

    // 本词之前所有词的宽度之和（首词再加一个 fadeWidth 的起始留白）
    var widthBeforeSelf = 0.0;
    for (var j = 0; j < i; j++) {
      widthBeforeSelf += words[j].width;
    }
    widthBeforeSelf += fadeWidth;

    final minOffset = -(word.width + word.padding * 2 + fadeWidth);
    double clampOffset(double x) => x < minOffset ? minOffset : (x > 0 ? 0 : x);

    var curPos = -widthBeforeSelf - word.width - word.padding - fadeWidth;
    var timeOffset = 0.0;
    var lastPos = curPos;
    var lastTime = 0.0;
    final keyframes = <FadeKeyframe>[];

    void pushFrame() {
      // 原实现刻意不加缓动函数：加了会破坏逐词时序的准确性
      final moveOffset = curPos - lastPos;
      final time = _clamp01(timeOffset);
      final duration = time - lastTime;
      final d = moveOffset == 0 ? 0.0 : (duration / moveOffset).abs();

      // 跨越边界时补插关键帧，避免越界段被线性插值抹平
      if (curPos > minOffset && lastPos < minOffset) {
        final staticTime = (lastPos - minOffset).abs() * d;
        keyframes.add(FadeKeyframe(lastTime + staticTime, clampOffset(lastPos)));
      }
      if (curPos > 0 && lastPos < 0) {
        final staticTime = lastPos.abs() * d;
        keyframes.add(FadeKeyframe(lastTime + staticTime, clampOffset(curPos)));
      }

      keyframes.add(FadeKeyframe(time, clampOffset(curPos)));
      lastPos = curPos;
      lastTime = time;
    }

    pushFrame();

    var lastTimeStamp = 0;
    for (var j = 0; j < words.length; j++) {
      final otherWord = words[j];

      // 停顿段
      final curTimeStamp = otherWord.startTime - lineStartTime;
      final staticDuration = curTimeStamp - lastTimeStamp;
      timeOffset += staticDuration / safeDuration;
      if (staticDuration > 0) pushFrame();
      lastTimeStamp = curTimeStamp;

      // 移动段
      final fadeDuration = math.max(0, otherWord.endTime - otherWord.startTime);
      timeOffset += fadeDuration / safeDuration;
      curPos += otherWord.width;
      if (j == 0) curPos += fadeWidth * 1.5;
      if (j == words.length - 1) curPos += fadeWidth * 0.5;
      if (fadeDuration > 0) pushFrame();
      lastTimeStamp += fadeDuration;
    }

    solutions.add(
      FadeMaskSolution(
        fadeWidth: fadeWidth,
        minOffset: minOffset,
        keyframes: keyframes,
        geometry: geometry,
        maskWidth: (word.width + word.padding * 2) * geometry.totalAspect,
      ),
    );
  }

  return solutions;
}

/// 整行渐变的总时长（毫秒）。
int lineFadeDuration({
  required List<FadeMaskWord> words,
  required int lineStartTime,
  required int lineEndTime,
}) {
  var latestWordEnd = 0;
  for (final w in words) {
    if (w.endTime > latestWordEnd) latestWordEnd = w.endTime;
  }
  return math.max(math.max(0, latestWordEnd), lineEndTime) - lineStartTime;
}
