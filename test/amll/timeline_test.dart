import 'dart:math' as math;

import 'package:cyrene_music_reborn/features/player/amll/core/layout.dart';
import 'package:cyrene_music_reborn/features/player/amll/core/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

class _Group extends InterludeGroup {
  _Group(this.startTime, this.endTime, {this.isDuet = false});

  @override
  final int startTime;
  @override
  final int endTime;
  @override
  final bool isDuet;
}

/// 走一遍 compute + commit 的完整流程。
CommitPlayerTimeStateResult step(
  PlayerTimelineState state,
  List<TimelineGroup> groups,
  int time, {
  bool isSeeking = false,
  bool hasBottomContent = false,
}) {
  state.isSeeking = isSeeking;
  final result = computePlayerTimeState(
    time: time,
    currentGroups: groups,
    timelineState: state,
  );
  return commitPlayerTimeState(
    timelineState: state,
    time: time,
    currentGroups: groups,
    hasBottomContent: hasBottomContent,
    stateResult: result,
  );
}

void main() {
  final groups = <TimelineGroup>[
    _Group(0, 2000),
    _Group(2000, 4000),
    _Group(4000, 6000),
  ];

  group('时间线状态转移', () {
    test('进入第一行时成为热行与缓冲行，并触发布局', () {
      final state = PlayerTimelineState()..initialLayoutFinished = true;
      final r = step(state, groups, 500);

      expect(state.hotGroups, {0});
      expect(state.bufferedGroups, {0});
      expect(state.scrollToIndex, 0);
      expect(r.groupsToEnable, [0]);
      expect(r.shouldLayout, isTrue);
    });

    test('切到下一行时旧缓冲行被移除、新行被启用', () {
      final state = PlayerTimelineState()..initialLayoutFinished = true;
      step(state, groups, 500);
      final r = step(state, groups, 2500);

      expect(state.hotGroups, {1});
      expect(state.bufferedGroups, {1});
      expect(state.scrollToIndex, 1);
      expect(r.groupsToEnable, [1]);
      expect(r.groupsToDisable, [0]);
    });

    test('同一行内推进时间不重复触发布局', () {
      final state = PlayerTimelineState()..initialLayoutFinished = true;
      step(state, groups, 500);
      final r = step(state, groups, 1500);

      expect(r.shouldLayout, isFalse);
      expect(r.groupsToEnable, isEmpty);
      expect(r.groupsToDisable, isEmpty);
    });

    test('落到空档时缓冲行被清空但不改变滚动位置', () {
      final gapGroups = <TimelineGroup>[
        _Group(0, 2000),
        _Group(9000, 11000),
      ];
      final state = PlayerTimelineState()..initialLayoutFinished = true;
      step(state, gapGroups, 500);
      expect(state.bufferedGroups, {0});

      final r = step(state, gapGroups, 3000);
      expect(state.bufferedGroups, isEmpty);
      expect(state.scrollToIndex, 0, reason: '空档期不应改变对齐目标');
      expect(r.groupsToDisable, [0]);
      expect(r.shouldLayout, isTrue);
    });

    test('seek 会重建缓冲集合并请求重置滚动', () {
      final state = PlayerTimelineState()..initialLayoutFinished = true;
      step(state, groups, 500);

      final r = step(state, groups, 4500, isSeeking: true);
      expect(state.hotGroups, {2});
      expect(state.bufferedGroups, {2});
      expect(state.scrollToIndex, 2);
      expect(r.shouldResetScroll, isTrue);
      expect(r.groupsToDisable, contains(0));
    });

    test('seek 到空档时对齐到下一条即将开始的行', () {
      final gapGroups = <TimelineGroup>[
        _Group(0, 2000),
        _Group(9000, 11000),
      ];
      final state = PlayerTimelineState()..initialLayoutFinished = true;
      step(state, gapGroups, 5000, isSeeking: true);

      expect(state.bufferedGroups, isEmpty);
      expect(state.scrollToIndex, 1);
    });

    test('播完全部歌词后对齐到最后一行', () {
      final state = PlayerTimelineState()..initialLayoutFinished = true;
      step(state, groups, 4500);
      final r = step(state, groups, 7000);

      expect(state.scrollToIndex, 2);
      expect(r.shouldLayout, isTrue);
    });

    test('底栏有内容时播完后对齐到底栏位置', () {
      final state = PlayerTimelineState()..initialLayoutFinished = true;
      step(state, groups, 4500);
      step(state, groups, 7000, hasBottomContent: true);

      expect(state.scrollToIndex, groups.length);
    });

    test('重叠歌词行会同时成为缓冲行，对齐到最靠前的一条', () {
      final overlapping = <TimelineGroup>[
        _Group(0, 5000),
        _Group(2000, 7000),
      ];
      final state = PlayerTimelineState()..initialLayoutFinished = true;
      step(state, overlapping, 3000);

      expect(state.hotGroups, {0, 1});
      expect(state.bufferedGroups, {0, 1});
      expect(state.scrollToIndex, 0);
    });
  });

  group('pickScrollToIndexForSeek', () {
    test('有缓冲行时取最小索引', () {
      expect(pickScrollToIndexForSeek(0, groups, {2, 1}), 1);
    });

    test('无缓冲行且时间超过全部歌词时落到末尾之后', () {
      expect(pickScrollToIndexForSeek(99999, groups, {}), groups.length);
    });
  });

  group('computeCurrentInterlude', () {
    final gapGroups = <InterludeGroup>[
      _Group(0, 2000),
      _Group(12000, 14000, isDuet: true),
    ];

    test('空档 ≥4000ms 且当前时间落在其中时命中间奏', () {
      final interlude = computeCurrentInterlude(
        currentTime: 5000,
        scrollToIndex: 0,
        currentGroups: gapGroups,
      );
      expect(interlude, isNotNull);
      expect(interlude!.anchorLineIndex, 0);
      expect(interlude.endTime, 11750, reason: '结束时间应留出 250ms 提前量');
      expect(interlude.isNextDuet, isTrue);
    });

    test('空档不足 4000ms 时不算间奏', () {
      final shortGap = <InterludeGroup>[
        _Group(0, 2000),
        _Group(5000, 7000),
      ];
      expect(
        computeCurrentInterlude(
          currentTime: 3000,
          scrollToIndex: 0,
          currentGroups: shortGap,
        ),
        isNull,
      );
    });

    test('歌词行播放中不算间奏', () {
      expect(
        computeCurrentInterlude(
          currentTime: 1000,
          scrollToIndex: 0,
          currentGroups: gapGroups,
        ),
        isNull,
      );
    });

    test('第一行之前的前奏用 anchorLineIndex = -1 表示', () {
      final intro = <InterludeGroup>[_Group(8000, 10000)];
      final interlude = computeCurrentInterlude(
        currentTime: 1000,
        scrollToIndex: 0,
        currentGroups: intro,
      );
      expect(interlude, isNotNull);
      expect(interlude!.anchorLineIndex, -1);
    });
  });

  group('computeLinePosYSpringParams', () {
    final groups2 = <TimelineGroup>[_Group(0, 2000), _Group(2300, 4000)];

    test('seeking 时用固定的稳态参数', () {
      final r = computeLinePosYSpringParams(
        enabled: true,
        currentGroups: groups2,
        scrollToIndex: 1,
        isSeeking: true,
        isInterludeActive: false,
      );
      expect(r.shouldUpdate, isTrue);
      expect(r.params!.stiffness, 90);
      expect(r.params!.damping, 15);
    });

    test('间奏时同样用固定参数', () {
      final r = computeLinePosYSpringParams(
        enabled: true,
        currentGroups: groups2,
        scrollToIndex: 1,
        isSeeking: false,
        isInterludeActive: true,
      );
      expect(r.params!.stiffness, 90);
    });

    test('间隔短则更硬，且 damping 保持接近临界阻尼', () {
      final fast = computeLinePosYSpringParams(
        enabled: true,
        currentGroups: <TimelineGroup>[_Group(0, 200), _Group(150, 400)],
        scrollToIndex: 1,
        isSeeking: false,
        isInterludeActive: false,
      );
      final slow = computeLinePosYSpringParams(
        enabled: true,
        currentGroups: <TimelineGroup>[_Group(0, 2000), _Group(5000, 7000)],
        scrollToIndex: 1,
        isSeeking: false,
        isInterludeActive: false,
      );

      expect(fast.params!.stiffness!, greaterThan(slow.params!.stiffness!));
      expect(fast.params!.stiffness!, lessThanOrEqualTo(220));
      expect(slow.params!.stiffness!, greaterThanOrEqualTo(170));
      // damping = sqrt(stiffness) * 2.2 → 阻尼比 1.1，略过阻尼、不回弹
      for (final r in [fast, slow]) {
        final ratio =
            r.params!.damping! / (2 * math.sqrt(r.params!.stiffness!));
        expect(ratio, greaterThan(1.0));
      }
    });

    test('禁用弹簧或无歌词时不更新参数', () {
      expect(
        computeLinePosYSpringParams(
          enabled: false,
          currentGroups: groups2,
          scrollToIndex: 1,
          isSeeking: false,
          isInterludeActive: false,
        ).shouldUpdate,
        isFalse,
      );
      expect(
        computeLinePosYSpringParams(
          enabled: true,
          currentGroups: const [],
          scrollToIndex: 0,
          isSeeking: false,
          isInterludeActive: false,
        ).shouldUpdate,
        isFalse,
      );
    });

    test('首行（没有上一行）不更新参数', () {
      expect(
        computeLinePosYSpringParams(
          enabled: true,
          currentGroups: groups2,
          scrollToIndex: 0,
          isSeeking: false,
          isInterludeActive: false,
        ).shouldUpdate,
        isFalse,
      );
    });
  });

  group('computeGroupPresentation', () {
    test('缓冲行为活跃行，opacity 0.85 且不模糊', () {
      final r = computeGroupPresentation(
        groupIndex: 1,
        scrollToIndex: 1,
        latestIndex: 1,
        hasBuffered: true,
        hidePassedLines: false,
        isPlaying: true,
        isNonDynamic: false,
        enableBlur: true,
        isUserScrolling: false,
        isCompact: false,
      );
      expect(r.isActive, isTrue);
      expect(r.targetOpacity, 0.85);
      expect(r.blurLevel, 0);
    });

    test('非活跃逐字歌词行 opacity 为 1，逐行歌词为 0.2', () {
      ComputeGroupPresentationResult run({required bool isNonDynamic}) =>
          computeGroupPresentation(
            groupIndex: 5,
            scrollToIndex: 1,
            latestIndex: 1,
            hasBuffered: false,
            hidePassedLines: false,
            isPlaying: true,
            isNonDynamic: isNonDynamic,
            enableBlur: false,
            isUserScrolling: false,
            isCompact: false,
          );
      expect(run(isNonDynamic: false).targetOpacity, 1);
      expect(run(isNonDynamic: true).targetOpacity, 0.2);
    });

    test('hidePassedLines 时已播放行几乎透明', () {
      final r = computeGroupPresentation(
        groupIndex: 0,
        scrollToIndex: 3,
        latestIndex: 3,
        hasBuffered: false,
        hidePassedLines: true,
        isPlaying: true,
        isNonDynamic: false,
        enableBlur: false,
        isUserScrolling: false,
        isCompact: false,
      );
      expect(r.targetOpacity, lessThan(0.001));
    });
  });

  group('computeLineBlur', () {
    test('距离越远越模糊', () {
      double blurAt(int index) => computeLineBlur(
        enableBlur: true,
        isUserScrolling: false,
        isActive: false,
        itemIndex: index,
        scrollToIndex: 5,
        latestIndex: 5,
        isCompact: false,
      );
      expect(blurAt(6), lessThan(blurAt(8)));
      expect(blurAt(4), lessThan(blurAt(2)));
    });

    test('关闭模糊、用户滚动中、活跃行都返回 0', () {
      double blur({
        bool enableBlur = true,
        bool isUserScrolling = false,
        bool isActive = false,
      }) => computeLineBlur(
        enableBlur: enableBlur,
        isUserScrolling: isUserScrolling,
        isActive: isActive,
        itemIndex: 10,
        scrollToIndex: 0,
        latestIndex: 0,
        isCompact: false,
      );
      expect(blur(enableBlur: false), 0);
      expect(blur(isUserScrolling: true), 0);
      expect(blur(isActive: true), 0);
    });

    test('紧凑布局按 0.8 折减', () {
      double blur({required bool isCompact}) => computeLineBlur(
        enableBlur: true,
        isUserScrolling: false,
        isActive: false,
        itemIndex: 8,
        scrollToIndex: 5,
        latestIndex: 5,
        isCompact: isCompact,
      );
      expect(blur(isCompact: true), closeTo(blur(isCompact: false) * 0.8, 1e-9));
    });
  });
}
