/// 时间线状态机。
///
/// 1:1 移植 `@applemusic-like-lyrics/core` 的 `lyric-player/base/timeline.ts`，
/// 全部是纯函数，不触碰任何 UI，便于单测。
library;

/// 时间线只需要知道每组歌词的始末时间。
abstract class TimelineGroup {
  int get startTime;
  int get endTime;
}

/// 播放时间线状态。
///
/// 这里定义了三种歌词状态：
/// - 普通行：当前不处于时间范围内
/// - 热行（[hotGroups]）：当前时间正命中的组
/// - 缓冲行（[bufferedGroups]）：UI 上仍保持激活表现的组，通常包含热行，
///   以及刚结束但仍在过渡中的组
///
/// 行为规则：
/// - 仍有缓冲行时加入新热行 → 不解除当前缓冲行，也不改滚动位置
/// - 所有缓冲行都将删除且无新热行 → 删除所有缓冲行，不改滚动位置
/// - 所有缓冲行都将删除且有新热行 → 删除旧缓冲行、加入新热行，并改滚动位置
class PlayerTimelineState {
  PlayerTimelineState();

  /// 当前播放时间，单位毫秒
  int currentTime = 0;

  /// 上一次提交的播放时间，单位毫秒
  int lastCurrentTime = 0;

  /// 热组集合
  Set<int> hotGroups = <int>{};

  /// 缓冲组集合
  Set<int> bufferedGroups = <int>{};

  /// 当前应滚动对齐到的歌词组索引
  int scrollToIndex = 0;

  /// 是否正在拖拽进度条
  bool isSeeking = false;

  /// 是否处于播放状态
  bool isPlaying = true;

  /// 是否已完成至少一次初始布局
  bool initialLayoutFinished = false;
}

/// [computePlayerTimeState] 的返回值。
class ComputePlayerTimeStateResult {
  ComputePlayerTimeStateResult({
    required this.nextHotGroups,
    required this.addedIds,
    required this.removedHotIds,
    required this.removedBufferedIds,
  });

  /// 计算后的新热组集合
  final Set<int> nextHotGroups;

  /// 需要新加入热组的索引
  final Set<int> addedIds;

  /// 需要从热组移除的索引
  final Set<int> removedHotIds;

  /// 需要从缓冲组移除的索引
  final Set<int> removedBufferedIds;
}

/// 计算指定时间点的热行/缓冲行状态转移。
ComputePlayerTimeStateResult computePlayerTimeState({
  required int time,
  required List<TimelineGroup> currentGroups,
  required PlayerTimelineState timelineState,
}) {
  final hotGroups = timelineState.hotGroups;
  final bufferedGroups = timelineState.bufferedGroups;

  final nextHotGroups = <int>{...hotGroups};
  final addedIds = <int>{};
  final removedHotIds = <int>{};
  final removedBufferedIds = <int>{};

  for (final lastHotId in hotGroups) {
    final group = lastHotId >= 0 && lastHotId < currentGroups.length
        ? currentGroups[lastHotId]
        : null;
    if (group == null || time < group.startTime || group.endTime <= time) {
      nextHotGroups.remove(lastHotId);
      removedHotIds.add(lastHotId);
    }
  }

  for (var id = 0; id < currentGroups.length; id++) {
    final group = currentGroups[id];
    if (group.startTime <= time &&
        group.endTime > time &&
        !nextHotGroups.contains(id)) {
      nextHotGroups.add(id);
      addedIds.add(id);
    }
  }

  for (final id in bufferedGroups) {
    if (!nextHotGroups.contains(id)) {
      removedBufferedIds.add(id);
    }
  }

  return ComputePlayerTimeStateResult(
    nextHotGroups: nextHotGroups,
    addedIds: addedIds,
    removedHotIds: removedHotIds,
    removedBufferedIds: removedBufferedIds,
  );
}

/// seeking 场景下选出应对齐滚动到的目标行索引。
///
/// 若仍存在缓冲行，优先对齐最靠前的缓冲行；否则对齐第一条开始时间不小于
/// 当前时间的歌词行；都没有则落到末尾（即底栏位置）。
int pickScrollToIndexForSeek(
  int time,
  List<TimelineGroup> currentGroups,
  Set<int> bufferedGroups,
) {
  if (bufferedGroups.isNotEmpty) {
    return bufferedGroups.reduce((a, b) => a < b ? a : b);
  }
  final foundIndex = currentGroups.indexWhere(
    (group) => group.startTime >= time,
  );
  return foundIndex == -1 ? currentGroups.length : foundIndex;
}

/// [commitPlayerTimeState] 的返回值：一份供宿主执行的副作用计划。
class CommitPlayerTimeStateResult {
  CommitPlayerTimeStateResult({
    required this.shouldLayout,
    required this.shouldResetScroll,
    required this.groupsToEnable,
    required this.groupsToDisable,
  });

  /// 是否需要重新布局
  final bool shouldLayout;

  /// 是否需要重置用户滚动状态
  final bool shouldResetScroll;

  /// 需要启用的歌词组索引
  final List<int> groupsToEnable;

  /// 需要禁用的歌词组索引
  final List<int> groupsToDisable;
}

bool _setEquals(Set<int> a, Set<int> b) {
  if (a.length != b.length) return false;
  for (final v in a) {
    if (!b.contains(v)) return false;
  }
  return true;
}

/// 把一次时间线状态转移写回 [timelineState]，并返回副作用计划。
CommitPlayerTimeStateResult commitPlayerTimeState({
  required PlayerTimelineState timelineState,
  required int time,
  required List<TimelineGroup> currentGroups,
  required bool hasBottomContent,
  required ComputePlayerTimeStateResult stateResult,
}) {
  final addedIds = stateResult.addedIds;
  final removedHotIds = stateResult.removedHotIds;
  final removedBufferedIds = stateResult.removedBufferedIds;
  final isSeeking = timelineState.isSeeking;

  timelineState.currentTime = time;
  timelineState.hotGroups = stateResult.nextHotGroups;

  var shouldLayout = false;
  var shouldResetScroll = false;
  final groupsToEnable = <int>[];
  final groupsToDisable = <int>{};

  if (isSeeking) {
    timelineState.bufferedGroups = <int>{...timelineState.hotGroups};
    timelineState.scrollToIndex = pickScrollToIndexForSeek(
      time,
      currentGroups,
      timelineState.bufferedGroups,
    );
    groupsToDisable.addAll(removedHotIds);
    groupsToEnable.addAll(timelineState.hotGroups);
    groupsToDisable.addAll(removedBufferedIds);

    shouldResetScroll = true;
    shouldLayout = true;
  } else if (addedIds.isNotEmpty) {
    for (final id in addedIds) {
      timelineState.bufferedGroups.add(id);
      groupsToEnable.add(id);
    }
    for (final id in removedBufferedIds) {
      timelineState.bufferedGroups.remove(id);
      groupsToDisable.add(id);
    }
    if (timelineState.bufferedGroups.isNotEmpty) {
      timelineState.scrollToIndex = timelineState.bufferedGroups.reduce(
        (a, b) => a < b ? a : b,
      );
    }
    shouldLayout = true;
  } else if (removedBufferedIds.isNotEmpty &&
      _setEquals(removedBufferedIds, timelineState.bufferedGroups)) {
    for (final id in timelineState.bufferedGroups.toList()) {
      if (timelineState.hotGroups.contains(id)) continue;
      timelineState.bufferedGroups.remove(id);
      groupsToDisable.add(id);
    }
    shouldLayout = true;
  }

  // 歌词全部播完后，对齐到底栏（若底栏有内容）或最后一行
  if (timelineState.bufferedGroups.isEmpty && currentGroups.isNotEmpty) {
    final lastGroup = currentGroups.last;
    if (time >= lastGroup.endTime) {
      final targetIndex = hasBottomContent
          ? currentGroups.length
          : currentGroups.length - 1;
      if (timelineState.scrollToIndex != targetIndex) {
        timelineState.scrollToIndex = targetIndex;
        shouldLayout = true;
      }
    }
  }

  timelineState.lastCurrentTime = time;

  return CommitPlayerTimeStateResult(
    shouldLayout: shouldLayout,
    shouldResetScroll: shouldResetScroll,
    groupsToEnable: groupsToEnable,
    groupsToDisable: groupsToDisable.toList(),
  );
}
