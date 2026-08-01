/// 布局计算的纯函数集合。
///
/// 1:1 移植 `@applemusic-like-lyrics/core` 的 `lyric-player/base/layout.ts`。
library;

import 'dart:math' as math;

import 'lyric_types.dart';
import 'spring.dart';
import 'timeline.dart';

double _clamp(double x, double min, double max) =>
    x < min ? min : (x > max ? max : x);

/// 播放器布局状态：对齐方式、间奏点尺寸、上一轮命中的目标行等。
class PlayerLayoutState {
  /// 间奏点元素当前测量得到的尺寸
  List<double> interludeDotsSize = <double>[0, 0];

  /// 上一轮布局实际对齐的目标歌词行索引
  int targetAlignIndex = 0;

  /// 上一轮布局时是否处于间奏区间
  bool lastInterludeState = false;

  /// 当前歌词目标行的对齐锚点
  LayoutAlignAnchor alignAnchor = LayoutAlignAnchor.center;

  /// 目标行在播放器高度中的相对对齐位置
  double alignPosition = 0.35;

  /// 视口上下额外保留的预渲染距离，单位像素
  double overscanPx = 300;
}

/// 当前命中的间奏区间。
class PlayerInterlude {
  const PlayerInterlude({
    required this.startTime,
    required this.endTime,
    required this.anchorLineIndex,
    required this.isNextDuet,
  });

  /// 间奏动画的开始时间
  final int startTime;

  /// 间奏动画的结束时间
  final int endTime;

  /// 间奏点应插入到哪一行之后；`-1` 表示位于第一行之前
  final int anchorLineIndex;

  /// 间奏结束后的下一句是否为对唱歌词
  final bool isNextDuet;
}

/// 间奏探测所需的组信息。
abstract class InterludeGroup extends TimelineGroup {
  /// 该组主歌词行是否为对唱行
  bool get isDuet;
}

/// 根据当前时间与目标行，计算当前是否处于某个可展示的间奏区间。
///
/// 只有空档 ≥ 4000ms 才算间奏。会探测 `scrollToIndex` 前后共三个间隙。
PlayerInterlude? computeCurrentInterlude({
  required int currentTime,
  required int scrollToIndex,
  required List<InterludeGroup> currentGroups,
}) {
  final time = currentTime + 20;
  final groups = currentGroups;

  PlayerInterlude? checkGap(int k) {
    if (k < -1 || k >= groups.length - 1) return null;

    final prevGroup = k == -1 ? null : groups[k];
    final nextGroup = groups[k + 1];

    final gapStart = prevGroup?.endTime ?? 0;
    final gapEnd = math.max(gapStart, nextGroup.startTime - 250);

    if (gapEnd - gapStart < 4000) return null;

    if (gapEnd > time && gapStart < time) {
      return PlayerInterlude(
        startTime: math.max(gapStart, time),
        endTime: gapEnd,
        anchorLineIndex: k,
        isNextDuet: nextGroup.isDuet,
      );
    }
    return null;
  }

  return checkGap(scrollToIndex - 1) ??
      checkGap(scrollToIndex) ??
      checkGap(scrollToIndex + 1);
}

/// [computeLinePosYSpringParams] 的结果。
class ComputeLinePosYSpringParamsResult {
  const ComputeLinePosYSpringParamsResult({
    required this.shouldUpdate,
    this.params,
  });

  final bool shouldUpdate;
  final SpringParams? params;
}

/// 根据当前播放上下文计算歌词纵向滚动的弹簧参数。
///
/// 策略：seeking 或间奏时用更稳的固定参数；普通播放时按相邻歌词的时间间隔
/// 动态调整 —— 间隔越短越硬（stiffness 170→220），damping 取 √stiffness × 2.2
/// 以保持接近临界阻尼、不产生回弹。
ComputeLinePosYSpringParamsResult computeLinePosYSpringParams({
  required bool enabled,
  required List<TimelineGroup> currentGroups,
  required int scrollToIndex,
  required bool isSeeking,
  required bool isInterludeActive,
}) {
  if (!enabled || currentGroups.isEmpty) {
    return const ComputeLinePosYSpringParamsResult(shouldUpdate: false);
  }

  if (isSeeking || isInterludeActive) {
    return const ComputeLinePosYSpringParamsResult(
      shouldUpdate: true,
      params: SpringParams(stiffness: 90, damping: 15),
    );
  }

  final currentGroup = scrollToIndex >= 0 && scrollToIndex < currentGroups.length
      ? currentGroups[scrollToIndex]
      : null;
  final prevGroup =
      scrollToIndex - 1 >= 0 && scrollToIndex - 1 < currentGroups.length
      ? currentGroups[scrollToIndex - 1]
      : null;

  if (currentGroup == null || prevGroup == null) {
    return const ComputeLinePosYSpringParamsResult(shouldUpdate: false);
  }

  final interval = (currentGroup.startTime - prevGroup.startTime).toDouble();

  const minInterval = 100.0;
  const maxInterval = 800.0;
  final clampedInterval = _clamp(interval, minInterval, maxInterval);

  const maxStiffness = 220.0;
  const minStiffness = 170.0;

  var ratio = 1 - (clampedInterval - minInterval) / (maxInterval - minInterval);
  ratio = math.pow(ratio, 0.2).toDouble();

  final targetStiffness = minStiffness + ratio * (maxStiffness - minStiffness);

  const dampingMultiplier = 2.2;
  final targetDamping = math.sqrt(targetStiffness) * dampingMultiplier;

  return ComputeLinePosYSpringParamsResult(
    shouldUpdate: true,
    params: SpringParams(
      stiffness: targetStiffness,
      damping: targetDamping,
    ),
  );
}

/// [computeGroupPresentation] 的结果。
class ComputeGroupPresentationResult {
  const ComputeGroupPresentationResult({
    required this.isActive,
    required this.targetOpacity,
    required this.blurLevel,
  });

  /// 当前歌词行是否应视为活跃行
  final bool isActive;

  /// 目标不透明度
  final double targetOpacity;

  /// 目标模糊值
  final double blurLevel;
}

/// 计算一组歌词在当前布局中的视觉呈现参数。
ComputeGroupPresentationResult computeGroupPresentation({
  required int groupIndex,
  required int scrollToIndex,
  required int latestIndex,
  required bool hasBuffered,
  required bool hidePassedLines,
  required bool isPlaying,
  required bool isNonDynamic,
  required bool enableBlur,
  required bool isUserScrolling,
  required bool isCompact,
  PlayerInterlude? interlude,
}) {
  final isActive =
      hasBuffered || (groupIndex >= scrollToIndex && groupIndex < latestIndex);

  final blurLevel = computeLineBlur(
    enableBlur: enableBlur,
    isUserScrolling: isUserScrolling,
    isActive: isActive,
    itemIndex: groupIndex,
    scrollToIndex: scrollToIndex,
    latestIndex: latestIndex,
    isCompact: isCompact,
  );

  double targetOpacity;
  if (hidePassedLines) {
    final passedBoundary = interlude != null
        ? interlude.anchorLineIndex + 1
        : scrollToIndex;
    if (groupIndex < passedBoundary && isPlaying) {
      // 与原实现一致，用一个极小但非零的值（几乎不可见）
      targetOpacity = 1e-4;
    } else if (hasBuffered) {
      targetOpacity = 0.85;
    } else {
      targetOpacity = isNonDynamic ? 0.2 : 1;
    }
  } else if (hasBuffered) {
    targetOpacity = 0.85;
  } else {
    targetOpacity = isNonDynamic ? 0.2 : 1;
  }

  return ComputeGroupPresentationResult(
    isActive: isActive,
    targetOpacity: targetOpacity,
    blurLevel: blurLevel,
  );
}

/// 计算一行歌词的模糊等级。
///
/// 越远离当前对齐区域越模糊；活跃行、用户滚动中或关闭模糊时返回 0。
double computeLineBlur({
  required bool enableBlur,
  required bool isUserScrolling,
  required bool isActive,
  required int itemIndex,
  required int scrollToIndex,
  required int latestIndex,
  required bool isCompact,
}) {
  if (!enableBlur || isUserScrolling || isActive) {
    return 0;
  }

  var blurLevel = 1.0;

  if (itemIndex < scrollToIndex) {
    blurLevel += (scrollToIndex - itemIndex).abs() + 1;
  } else {
    blurLevel += (itemIndex - math.max(scrollToIndex, latestIndex)).abs();
  }

  return isCompact ? blurLevel * 0.8 : blurLevel;
}
