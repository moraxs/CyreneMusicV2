/// 歌词播放器控制器。
///
/// 对应 AMLL 的 `LyricPlayerBase` / `DomLyricPlayer`：持有歌词组、时间线状态、
/// 布局状态与滚动状态，对外提供 [setLyricLines] / [setCurrentTime] /
/// [calcLayout] / [update] 四个入口，逐帧由宿主的 Ticker 驱动。
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'core/layout.dart';
import 'core/lyric_types.dart';
import 'core/optimize_lyric.dart';
import 'core/spring.dart';
import 'core/timeline.dart';
import 'render/interlude_dots.dart';
import 'render/lyric_group.dart';
import 'render/lyric_line_view.dart';

/// 用户滚动状态。
class PlayerScrollState {
  double minOffset = 0;
  double maxOffset = 0;

  /// 用户滚动带来的额外偏移
  double scrollOffset = 0;

  /// 是否允许用户滚动
  bool allowScroll = true;

  /// 是否滚动过、尚未回归自动对齐
  bool isScrolled = false;

  /// 是否正在滚动交互或惯性滚动中
  bool isUserScrolling = false;

  void clampOffset() {
    scrollOffset = scrollOffset.clamp(minOffset, maxOffset);
  }

  void reset() {
    isScrolled = false;
    scrollOffset = 0;
    isUserScrolling = false;
  }
}

/// 间奏点当前的布局与时间信息。
class InterludeDotsPlacement {
  const InterludeDotsPlacement({
    required this.top,
    required this.alignRight,
    required this.startTime,
    required this.endTime,
  });

  final double top;
  final bool alignRight;
  final int startTime;
  final int endTime;
}

class AmllLyricController extends ChangeNotifier {
  AmllLyricController();

  // ---- 配置项 ----

  bool _enableSpring = true;
  bool _enableScale = true;
  bool _enableBlur = false;
  bool _hidePassedLines = false;
  bool _alwaysPostpositionBackground = false;

  /// 是否显示翻译行（参与高度计算，必须与渲染层一致）
  bool showTranslation = true;

  /// 是否显示音译行
  bool showRoman = true;

  /// 有组高度发生变化，需要在本帧末尾统一重新布局。
  ///
  /// 构建每组时立刻 calcLayout 会在首帧产生 O(n²) 的重复布局，是卡顿来源之一。
  bool _needsRelayout = false;
  double _wordFadeWidth = 0.5;
  MaskObsceneWordsMode _maskObsceneWords = MaskObsceneWordsMode.disabled;
  String _maskObsceneWordChar = '*';

  final PlayerTimelineState _timeline = PlayerTimelineState();
  final PlayerLayoutState _layoutState = PlayerLayoutState();
  final PlayerScrollState scrollState = PlayerScrollState();

  SpringParams _posYSpringParams = const SpringParams(
    mass: 0.9,
    damping: 15,
    stiffness: 90,
  );
  SpringParams _scaleSpringParams = const SpringParams(
    mass: 2,
    damping: 25,
    stiffness: 100,
  );
  SpringParams _scaleForBGSpringParams = const SpringParams(
    mass: 1,
    damping: 20,
    stiffness: 50,
  );

  List<AmllLyricLine> _currentLyricLines = const [];
  List<AmllLyricLine> _processedLines = const [];
  List<AmllLyricGroup> _groups = const [];
  bool _isNonDynamic = false;
  bool _hasDuetLine = false;

  Size _viewportSize = Size.zero;
  double _fontSize = 24;
  TextStyle _textStyle = const TextStyle(fontSize: 24);
  double _contentMaxWidth = 0;

  /// 底部内容（如创作者信息）的高度，参与布局与「播完对齐底栏」判定
  double _bottomLineHeight = 0;

  final Spring _bottomLinePosY = Spring(0);

  InterludeDotsPlacement? _interludeDots;
  PlayerInterlude? _currentInterlude;

  /// 需要绘制的组索引（在视区内）
  final Set<int> _visibleGroups = <int>{};

  // ---- 只读访问 ----

  List<AmllLyricGroup> get groups => _groups;
  List<AmllLyricLine> get lyricLines => _currentLyricLines;
  bool get isNonDynamic => _isNonDynamic;
  bool get hasDuetLine => _hasDuetLine;
  bool get isPlaying => _timeline.isPlaying;
  int get currentTime => _timeline.currentTime;
  int get scrollToIndex => _timeline.scrollToIndex;
  bool get enableSpring => _enableSpring;
  bool get enableScale => _enableScale;
  bool get enableBlur => _enableBlur;
  double get wordFadeWidth => _wordFadeWidth;
  Size get viewportSize => _viewportSize;
  double get fontSize => _fontSize;
  TextStyle get textStyle => _textStyle;
  InterludeDotsPlacement? get interludeDots => _interludeDots;
  Set<int> get visibleGroups => _visibleGroups;
  double get bottomLineTop => _bottomLinePosY.getCurrentPosition();
  double get contentMaxWidth => _contentMaxWidth;

  /// 每组的测量高度缓存
  final Map<AmllLyricGroup, double> _groupHeights = <AmllLyricGroup, double>{};

  double heightOf(AmllLyricGroup group) =>
      _groupHeights[group] ?? _lineHeightFallback;

  double get _lineHeightFallback =>
      _viewportSize.height <= 0 ? 80 : _viewportSize.height / 5;

  // ---- 配置入口 ----

  /// 设置文字动画的渐变宽度，单位为主文字字号的倍数。
  ///
  /// 0.5 近似 Apple Music for iPad，1.0 近似 Apple Music for Android。
  void setWordFadeWidth(double value) {
    final v = math.max(0.0001, value);
    if (_wordFadeWidth == v) return;
    _wordFadeWidth = v;
    _rebuildAllLines();
    calcLayout(sync: true);
  }

  void setEnableScale(bool enable) {
    if (_enableScale == enable) return;
    _enableScale = enable;
    calcLayout();
  }

  void setEnableBlur(bool enable) {
    if (_enableBlur == enable) return;
    _enableBlur = enable;
    calcLayout();
  }

  void setEnableSpring(bool enable) {
    if (_enableSpring == enable) return;
    _enableSpring = enable;
    calcLayout(sync: true);
  }

  void setHidePassedLines(bool hide) {
    if (_hidePassedLines == hide) return;
    _hidePassedLines = hide;
    calcLayout();
  }

  void setAlignAnchor(LayoutAlignAnchor anchor) {
    if (_layoutState.alignAnchor == anchor) return;
    _layoutState.alignAnchor = anchor;
    calcLayout();
  }

  void setAlignPosition(double alignPosition) {
    if (_layoutState.alignPosition == alignPosition) return;
    _layoutState.alignPosition = alignPosition;
    calcLayout();
  }

  void setOverscanPx(double px) {
    _layoutState.overscanPx = math.max(0, px);
  }

  void setAlwaysPostpositionBackground(bool enable) {
    if (_alwaysPostpositionBackground == enable) return;
    _alwaysPostpositionBackground = enable;
    calcLayout();
  }

  void setMaskObsceneWords(MaskObsceneWordsMode mode) {
    if (_maskObsceneWords == mode) return;
    _maskObsceneWords = mode;
    _rebuildAllLines();
    calcLayout();
  }

  void setMaskObsceneWordChar(String char) {
    final c = char.isEmpty ? '*' : char[0];
    if (_maskObsceneWordChar == c) return;
    _maskObsceneWordChar = c;
    if (_maskObsceneWords != MaskObsceneWordsMode.disabled) {
      _rebuildAllLines();
      calcLayout();
    }
  }

  /// 设置底部内容的高度（0 表示没有底部内容）。
  void setBottomLineHeight(double height) {
    if (_bottomLineHeight == height) return;
    _bottomLineHeight = height;
    calcLayout(sync: true);
  }

  /// 视口尺寸与文字样式变化时调用。
  void setViewport({
    required Size size,
    required TextStyle textStyle,
    required double contentMaxWidth,
  }) {
    final sizeChanged = _viewportSize != size;
    final styleChanged = _textStyle != textStyle;
    final widthChanged = (_contentMaxWidth - contentMaxWidth).abs() > 0.5;
    if (!sizeChanged && !styleChanged && !widthChanged) return;

    _viewportSize = size;
    _textStyle = textStyle;
    _fontSize = textStyle.fontSize ?? 24;
    _contentMaxWidth = contentMaxWidth;

    if (styleChanged || widthChanged) {
      _rebuildAllLines();
    }
    calcLayout(sync: true, force: sizeChanged && _groupHeights.isEmpty);
  }

  /// 处理不雅用语。
  String processObsceneWord(AmllLyricWord word) {
    final text = word.word;
    if (!word.obscene || _maskObsceneWords == MaskObsceneWordsMode.disabled) {
      return text;
    }

    final maskChar = _maskObsceneWordChar;

    if (_maskObsceneWords == MaskObsceneWordsMode.fullMask) {
      return text.replaceAll(RegExp(r'\S'), maskChar);
    }

    // 保留首尾字符，掩码中间
    final trimmed = text.trim();
    if (trimmed.length <= 2) {
      return text.replaceAll(RegExp(r'\S'), maskChar);
    }
    final startPos = text.indexOf(trimmed);
    final endPos = startPos + trimmed.length - 1;
    return text.substring(0, startPos + 1) +
        text
            .substring(startPos + 1, endPos)
            .replaceAll(RegExp(r'\S'), maskChar) +
        text.substring(endPos);
  }

  // ---- 歌词数据 ----

  /// 设置当前播放歌词。
  ///
  /// [lines] 会被深拷贝后做优化处理，调用方无需自己拷贝。
  void setLyricLines(
    List<AmllLyricLine> lines, {
    int initialTime = 0,
    OptimizeLyricOptions options = const OptimizeLyricOptions(),
  }) {
    _timeline.initialLayoutFinished = true;
    _timeline.lastCurrentTime = initialTime;
    _timeline.currentTime = initialTime;
    _timeline.hotGroups.clear();
    _timeline.bufferedGroups.clear();
    _timeline.scrollToIndex = 0;

    _currentLyricLines = cloneLyricLines(lines);
    _processedLines = cloneLyricLines(_currentLyricLines);
    optimizeLyricLines(_processedLines, options);

    _isNonDynamic = true;
    for (final line in _processedLines) {
      if (line.words.length > 1) {
        _isNonDynamic = false;
        break;
      }
    }
    _hasDuetLine = _processedLines.any((line) => line.isDuet);

    // 按「主歌词 + 紧随其后的背景人声」分组
    final groups = <AmllLyricGroup>[];
    AmllLyricGroup? currentGroup;
    for (final line in _processedLines) {
      final view = AmllLyricLineView(line: line, isBG: line.isBG);
      if (!line.isBG || currentGroup == null) {
        currentGroup = AmllLyricGroup(
          mainLine: view,
          // 初始位置放在视区下方，让首次布局有一个自下而上的入场
          initialPosY: _viewportSize.height <= 0
              ? 800
              : _viewportSize.height * 2,
        );
        groups.add(currentGroup);
      } else {
        currentGroup.addBgLine(view);
      }
    }

    _groups = groups;
    _groupHeights.clear();
    _visibleGroups.clear();
    _interludeDots = null;
    _currentInterlude = null;

    _applyPosYSpringParams();
    _applyScaleSpringParams();

    setCurrentTime(initialTime, isSeek: true);
    calcLayout(sync: true);
    notifyListeners();
  }

  void _rebuildAllLines() {
    for (final group in _groups) {
      group.teardownContent();
    }
    _groupHeights.clear();
  }

  // ---- 时间推进 ----

  /// 设置当前播放进度（毫秒）。
  ///
  /// 调用频率越高越准确；实际动画由 [update] 逐帧驱动。
  void setCurrentTime(int time, {bool isSeek = false}) {
    _timeline.isSeeking = isSeek;
    _timeline.currentTime = time;

    if (!_timeline.initialLayoutFinished && !isSeek) return;

    final timelineGroups = _groups.cast<TimelineGroup>().toList();
    final stateResult = computePlayerTimeState(
      time: time,
      currentGroups: timelineGroups,
      timelineState: _timeline,
    );
    final commitResult = commitPlayerTimeState(
      timelineState: _timeline,
      time: time,
      currentGroups: timelineGroups,
      hasBottomContent: _bottomLineHeight > 0,
      stateResult: stateResult,
    );

    for (final id in commitResult.groupsToDisable) {
      if (id >= 0 && id < _groups.length) _groups[id].disable();
    }
    for (final id in commitResult.groupsToEnable) {
      if (id >= 0 && id < _groups.length) _groups[id].enable();
    }

    if (commitResult.shouldResetScroll) resetScroll();
    if (commitResult.shouldLayout) calcLayout();
  }

  void setIsSeeking(bool isSeeking) {
    _timeline.isSeeking = isSeeking;
  }

  void pause() {
    if (!_timeline.isPlaying) return;
    _timeline.isPlaying = false;
    calcLayout();
  }

  void resume() {
    if (_timeline.isPlaying) return;
    _timeline.isPlaying = true;
    calcLayout();
  }

  void resetScroll() {
    scrollState.reset();
  }

  // ---- 布局 ----

  /// 重新计算歌词行位置。
  ///
  /// [sync] 表示不做逐行错峰延迟（初始化/resize 时用）；
  /// [force] 表示绕过弹簧直接就位。
  void calcLayout({bool sync = false, bool force = false}) {
    if (_groups.isEmpty) {
      _interludeDots = null;
      return;
    }

    final interlude = computeCurrentInterlude(
      currentTime: _timeline.currentTime,
      scrollToIndex: _timeline.scrollToIndex,
      currentGroups: _groups.cast<InterludeGroup>().toList(),
    );
    _currentInterlude = interlude;
    final isInterludeActive = interlude != null;

    // 目标行或间奏状态变化时，重算纵向弹簧参数
    if (_layoutState.targetAlignIndex != _timeline.scrollToIndex ||
        _layoutState.lastInterludeState != isInterludeActive) {
      _layoutState.lastInterludeState = isInterludeActive;
      final result = computeLinePosYSpringParams(
        enabled: _enableSpring,
        currentGroups: _groups.cast<TimelineGroup>().toList(),
        scrollToIndex: _timeline.scrollToIndex,
        isSeeking: _timeline.isSeeking,
        isInterludeActive: isInterludeActive,
      );
      if (result.shouldUpdate && result.params != null) {
        setLinePosYSpringParams(result.params!);
      }
    }

    var curPos = -scrollState.scrollOffset;
    final targetAlignIndex = _timeline.scrollToIndex;

    final dotMargin = _fontSize * 0.4;
    final dotsHeight = _interludeDotsHeight;
    final totalInterludeHeight = dotsHeight + dotMargin * 2;

    if (interlude != null && interlude.anchorLineIndex != -1) {
      curPos -= totalInterludeHeight;
    }

    // 目标行之前所有行的高度之和
    var scrollOffset = 0.0;
    for (var i = 0; i < targetAlignIndex && i < _groups.length; i++) {
      scrollOffset += heightOf(_groups[i]);
    }

    scrollState.minOffset = -scrollOffset;
    curPos -= scrollOffset;
    curPos += _viewportSize.height * _layoutState.alignPosition;

    _layoutState.targetAlignIndex = targetAlignIndex;

    final isBottomFocused = targetAlignIndex == _groups.length;
    final targetGroup =
        targetAlignIndex >= 0 && targetAlignIndex < _groups.length
        ? _groups[targetAlignIndex]
        : null;
    final targetLineHeight = targetGroup != null
        ? heightOf(targetGroup)
        : (isBottomFocused ? _bottomLineHeight : 0.0);

    if (targetLineHeight > 0) {
      switch (_layoutState.alignAnchor) {
        case LayoutAlignAnchor.bottom:
          curPos -= targetLineHeight;
        case LayoutAlignAnchor.center:
          curPos -= targetLineHeight / 2;
        case LayoutAlignAnchor.top:
          break;
      }
    }

    final latestIndex = _timeline.bufferedGroups.isEmpty
        ? -1
        : _timeline.bufferedGroups.reduce(math.max);

    var delay = 0.0;
    var baseDelay = sync ? 0.0 : 0.05;
    var setDots = false;
    InterludeDotsPlacement? dotsPlacement;

    final isCompact = _viewportSize.width <= 1024;

    for (var i = 0; i < _groups.length; i++) {
      final group = _groups[i];
      final hasBuffered = _timeline.bufferedGroups.contains(i);

      // 间奏点插在锚定行之后
      if (!setDots && interlude != null && i == interlude.anchorLineIndex + 1) {
        setDots = true;
        curPos += dotMargin;
        dotsPlacement = InterludeDotsPlacement(
          top: curPos,
          alignRight: interlude.isNextDuet,
          startTime: interlude.startTime,
          endTime: interlude.endTime,
        );
        curPos += dotsHeight;
        curPos += dotMargin;
      }

      final presentation = computeGroupPresentation(
        groupIndex: i,
        scrollToIndex: _timeline.scrollToIndex,
        latestIndex: latestIndex,
        hasBuffered: hasBuffered,
        hidePassedLines: _hidePassedLines,
        isPlaying: _timeline.isPlaying,
        isNonDynamic: _isNonDynamic,
        enableBlur: _enableBlur,
        isUserScrolling: scrollState.isUserScrolling,
        isCompact: isCompact,
        interlude: interlude,
      );

      group.setTransform(
        top: curPos,
        force: force,
        delay: delay,
        isActive: presentation.isActive,
        opacity: presentation.targetOpacity,
        blur: presentation.blurLevel,
        enableSpring: _enableSpring,
        enableScale: _enableScale,
        isPlaying: _timeline.isPlaying,
        isNonDynamic: _isNonDynamic,
        alwaysPostpositionBackground: _alwaysPostpositionBackground,
      );

      curPos += heightOf(group);

      // 错峰：越往后延迟越多，但增量逐步收敛
      if (curPos >= 0 && !_timeline.isSeeking) {
        delay += baseDelay;
        if (i >= _timeline.scrollToIndex) baseDelay /= 1.05;
      }
    }

    _interludeDots = dotsPlacement;

    scrollState.maxOffset =
        curPos + scrollState.scrollOffset - _viewportSize.height / 2;
    if (scrollState.maxOffset < scrollState.minOffset) {
      scrollState.maxOffset = scrollState.minOffset;
    }

    if (force || !_enableSpring) {
      _bottomLinePosY.setPosition(curPos);
    } else {
      _bottomLinePosY.setTargetPosition(curPos, delay);
    }
  }

  double get _interludeDotsHeight => math.max(8, _fontSize * 0.5);

  /// 间奏点绘制所需的尺寸
  Size get interludeDotsSize {
    final dot = _interludeDotsHeight;
    return Size(InterludeDotsPainter.widthFor(dot, dot * 0.5), dot);
  }

  /// 间奏点的圆点直径
  double get interludeDotDiameter => _interludeDotsHeight;

  // ---- 弹簧参数 ----

  void setLinePosYSpringParams(SpringParams params) {
    _posYSpringParams = _posYSpringParams.merge(params);
    _applyPosYSpringParams();
  }

  void _applyPosYSpringParams() {
    _bottomLinePosY.updateParams(_posYSpringParams);
    for (final group in _groups) {
      group.updatePosYSpringParams(_posYSpringParams);
    }
  }

  void setLineScaleSpringParams(SpringParams params) {
    _scaleSpringParams = _scaleSpringParams.merge(params);
    _scaleForBGSpringParams = _scaleForBGSpringParams.merge(params);
    _applyScaleSpringParams();
  }

  void _applyScaleSpringParams() {
    for (final group in _groups) {
      group.updateScaleSpringParams(
        mainParams: _scaleSpringParams,
        bgParams: _scaleForBGSpringParams,
      );
    }
  }

  // ---- 逐帧更新 ----

  /// 逐帧推进动画。[delta] 单位为毫秒。
  ///
  /// 返回视区内的组集合是否发生了增删（用于决定是否需要重建 widget 树；
  /// 位移/透明度等连续量的重绘由各行的 painter 自行判断）。
  bool update(double delta) {
    if (!_timeline.initialLayoutFinished) return false;
    final deltaS = delta / 1000;

    _bottomLinePosY.update(deltaS);

    var changed = false;
    final newVisible = <int>{};

    for (var i = 0; i < _groups.length; i++) {
      final group = _groups[i];
      group.update(deltaS, enableSpring: _enableSpring);

      final inSight = group.isInSight(
        viewportHeight: _viewportSize.height,
        overscanPx: _layoutState.overscanPx,
        measuredHeight: heightOf(group),
      );

      if (inSight) {
        newVisible.add(i);
        if (!group.isBuilt) {
          _buildGroup(group);
          changed = true;
        }
      } else if (group.isBuilt) {
        group.teardownContent();
        changed = true;
      }
    }

    if (!setEquals(newVisible, _visibleGroups)) {
      _visibleGroups
        ..clear()
        ..addAll(newVisible);
      changed = true;
    }

    // 本帧内可能构建了多组、各自更新了高度，这里只统一重排一次
    if (_needsRelayout) {
      _needsRelayout = false;
      calcLayout(sync: true);
      changed = true;
    }

    return changed;
  }

  /// 构建某组的排版与动画解算，并记录其测量高度。
  void _buildGroup(AmllLyricGroup group) {
    if (_contentMaxWidth <= 0) return;

    group.mainLine.build(
      textStyle: _textStyle,
      maxWidth: _contentMaxWidth,
      isNonDynamic: _isNonDynamic,
      wordFadeWidth: _wordFadeWidth,
      processWord: processObsceneWord,
      translation: showTranslation ? group.mainLine.line.translatedLyric : '',
      roman: showRoman ? group.mainLine.line.romanLyric : '',
    );

    final bg = group.bgLine;
    if (bg != null) {
      bg.build(
        textStyle: _bgTextStyle,
        maxWidth: _contentMaxWidth,
        isNonDynamic: _isNonDynamic,
        wordFadeWidth: _wordFadeWidth,
        processWord: processObsceneWord,
        translation: showTranslation ? bg.line.translatedLyric : '',
        roman: showRoman ? bg.line.romanLyric : '',
      );
    }

    _recordGroupHeight(group);
  }

  /// 背景人声的字号是主歌词的 0.7 倍（对应 `--amll-lp-bg-line-scale`）。
  TextStyle get _bgTextStyle =>
      _textStyle.copyWith(fontSize: math.max(_fontSize * 0.7, 10));

  void _recordGroupHeight(AmllLyricGroup group) {
    final previous = _groupHeights[group];
    final height = group.contentHeight(verticalPadding: lineVerticalPadding);
    if (previous == null || (previous - height).abs() > 0.5) {
      _groupHeights[group] = height;
      _needsRelayout = true;
    }
  }

  /// 行的上下内边距（单侧），对应 CSS `.lyricLineWrapper` 的 `padding: 0.4em`。
  double get lineVerticalPadding => _fontSize * 0.4;

  /// 预先构建所有落在视区内的组（首帧用）。
  void primeVisibleGroups() {
    for (final group in _groups) {
      final inSight = group.isInSight(
        viewportHeight: _viewportSize.height,
        overscanPx: _layoutState.overscanPx,
        measuredHeight: heightOf(group),
      );
      if (inSight && !group.isBuilt) {
        _buildGroup(group);
        _visibleGroups.add(_groups.indexOf(group));
      }
    }
    if (_needsRelayout) {
      _needsRelayout = false;
      calcLayout(sync: true);
    }
  }

  /// 设置副歌词行的显示开关（影响高度计算）。
  void setSubLineVisibility({
    required bool showTranslation,
    required bool showRoman,
  }) {
    if (this.showTranslation == showTranslation &&
        this.showRoman == showRoman) {
      return;
    }
    this.showTranslation = showTranslation;
    this.showRoman = showRoman;
    _rebuildAllLines();
    calcLayout(sync: true);
  }

  /// 求当前间奏点的动画状态。
  InterludeDotsState get interludeDotsState {
    final placement = _interludeDots;
    if (placement == null) return InterludeDotsState.hidden;
    if (!_timeline.isPlaying) return InterludeDotsState.hidden;
    return InterludeDotsAnimation.stateAt(
      currentTimeMs: _timeline.currentTime,
      startTime: placement.startTime,
      endTime: placement.endTime,
    );
  }

  /// 当前是否处于间奏
  bool get isInterludeActive => _currentInterlude != null;

  /// 找到某个纵向位置对应的歌词组索引，用于点击跳转。
  int? hitTestGroup(double localY) {
    for (var i = 0; i < _groups.length; i++) {
      final group = _groups[i];
      final top = group.currentTop;
      final height = heightOf(group);
      if (localY >= top && localY <= top + height) return i;
    }
    return null;
  }
}
