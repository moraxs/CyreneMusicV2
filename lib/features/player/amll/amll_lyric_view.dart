/// AMLL 歌词视图。
///
/// 对应 tauri 端 `AMLLLyricPlayer.tsx`：用 Ticker 逐帧驱动
/// [AmllLyricController.update]，把播放进度节流到 100ms 一次喂给
/// [AmllLyricController.setCurrentTime]（布局重算比弹簧推进昂贵得多）。
library;

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'amll_lyric_controller.dart';
import 'core/lyric_types.dart';
import 'render/interlude_dots.dart';
import 'render/lyric_group.dart';
import 'render/lyric_line_layout.dart';

/// 布局重算的节流间隔，与 tauri 端一致。
const Duration kTimeSyncInterval = Duration(milliseconds: 100);

/// 惯性滚动的每帧摩擦系数（按 16ms 归一）
const double kScrollFriction = 0.95;

/// 用户停止滚动后回归自动对齐的等待时长
const Duration kScrollResetDelay = Duration(seconds: 5);

class AmllLyricView extends StatefulWidget {
  const AmllLyricView({
    super.key,
    required this.lines,
    required this.positionListenable,
    required this.isPlaying,
    this.onSeek,
    this.onTapBlank,
    this.textStyle,
    this.baseColor = const Color(0xFFFFFFFF),
    this.alignPosition = 0.15,
    this.alignAnchor = LayoutAlignAnchor.center,
    this.wordFadeWidth = 1.0,
    this.enableBlur = false,
    this.enableScale = true,
    this.enableSpring = true,
    this.enableGlow = true,
    this.hidePassedLines = false,
    this.showTranslation = true,
    this.showRoman = true,
    this.horizontalPadding = 20,
    this.allowScroll = true,
    this.overscanPx = 300,
    this.timeOffsetMs = 0,
  });

  /// 歌词数据
  final List<AmllLyricLine> lines;

  /// 播放进度来源（毫秒精度的 Duration）
  final ValueListenable<Duration> positionListenable;

  /// 是否正在播放
  final bool isPlaying;

  /// 点击歌词行跳转
  final void Function(Duration position)? onSeek;

  /// 点击非歌词区域（用于宿主切换控制栏显隐）
  final VoidCallback? onTapBlank;

  /// 主歌词样式；未提供时按视口宽度推导字号
  final TextStyle? textStyle;

  /// 文字基色
  final Color baseColor;

  /// 目标行在视口中的相对位置
  final double alignPosition;

  final LayoutAlignAnchor alignAnchor;

  /// 词渐变宽度（主文字字号的倍数）
  final double wordFadeWidth;

  final bool enableBlur;
  final bool enableScale;
  final bool enableSpring;

  /// 是否绘制长词强调辉光
  final bool enableGlow;

  final bool hidePassedLines;

  /// 是否显示翻译行
  final bool showTranslation;

  /// 是否显示音译行
  final bool showRoman;

  final double horizontalPadding;

  /// 是否允许用户拖拽滚动
  final bool allowScroll;

  final double overscanPx;

  /// 歌词时间偏移（毫秒），用于对齐前奏延迟等
  final int timeOffsetMs;

  @override
  State<AmllLyricView> createState() => _AmllLyricViewState();
}

class _AmllLyricViewState extends State<AmllLyricView>
    with SingleTickerProviderStateMixin {
  final AmllLyricController _controller = AmllLyricController();

  late Ticker _ticker;
  Duration _lastTick = Duration.zero;
  Duration _sinceLastSync = kTimeSyncInterval;
  int _lastSyncedTimeMs = -1;
  int _paintTimeMs = 0;

  // 进度外推：PlayerService 的 position 更新频率低于帧率，
  // 用上一次同步点 + 已过时间做补偿，避免逐字动画抖动。
  Duration _lastKnownPosition = Duration.zero;
  Duration _lastPositionTick = Duration.zero;

  // 滚动手势
  double _dragStartOffset = 0;
  double _lastDragY = 0;
  Duration _lastDragTime = Duration.zero;
  double _scrollVelocity = 0;
  bool _inertiaActive = false;
  Duration? _scrollIdleSince;

  @override
  void initState() {
    super.initState();
    _applyConfig();
    _ticker = createTicker(_onTick)..start();
    widget.positionListenable.addListener(_onPositionChanged);
    _lastKnownPosition = widget.positionListenable.value;
  }

  @override
  void didUpdateWidget(AmllLyricView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.positionListenable != widget.positionListenable) {
      oldWidget.positionListenable.removeListener(_onPositionChanged);
      widget.positionListenable.addListener(_onPositionChanged);
    }

    _applyConfig();

    if (!identical(oldWidget.lines, widget.lines)) {
      _loadLines();
    }

    if (oldWidget.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        _controller.resume();
      } else {
        _controller.pause();
      }
    }
  }

  void _applyConfig() {
    _controller
      ..setSubLineVisibility(
        showTranslation: widget.showTranslation,
        showRoman: widget.showRoman,
      )
      ..setAlignPosition(widget.alignPosition)
      ..setAlignAnchor(widget.alignAnchor)
      ..setWordFadeWidth(widget.wordFadeWidth)
      ..setEnableBlur(widget.enableBlur)
      ..setEnableScale(widget.enableScale)
      ..setEnableSpring(widget.enableSpring)
      ..setHidePassedLines(widget.hidePassedLines)
      ..setOverscanPx(widget.overscanPx);
    _controller.scrollState.allowScroll = widget.allowScroll;
  }

  void _loadLines() {
    _controller.setLyricLines(widget.lines, initialTime: _currentPositionMs());
    _lastSyncedTimeMs = -1;
    _sinceLastSync = kTimeSyncInterval;
  }

  int _currentPositionMs() =>
      widget.positionListenable.value.inMilliseconds + widget.timeOffsetMs;

  void _onPositionChanged() {
    _lastKnownPosition = widget.positionListenable.value;
    _lastPositionTick = _lastTick;
  }

  /// 带外推的当前播放时间（毫秒）。
  int _extrapolatedPositionMs() {
    var position = _lastKnownPosition;
    if (widget.isPlaying) {
      final elapsed = _lastTick - _lastPositionTick;
      // 超过 500ms 说明宿主进度停更了，不再外推以免跑飞
      if (elapsed > Duration.zero &&
          elapsed < const Duration(milliseconds: 500)) {
        position += elapsed;
      }
    }
    return position.inMilliseconds + widget.timeOffsetMs;
  }

  void _onTick(Duration elapsed) {
    final delta = _lastTick == Duration.zero
        ? Duration.zero
        : elapsed - _lastTick;
    _lastTick = elapsed;

    // 时间线只负责低频切换热行；绘制时间每帧更新，避免逐字动画以 100ms 为步长。
    _paintTimeMs = _extrapolatedPositionMs();

    _sinceLastSync += delta;
    if (_sinceLastSync >= kTimeSyncInterval) {
      _sinceLastSync = Duration.zero;
      final timeMs = _extrapolatedPositionMs();
      if (timeMs != _lastSyncedTimeMs) {
        _lastSyncedTimeMs = timeMs;
        _controller.setCurrentTime(timeMs);
      }
    }

    _advanceInertia(delta);
    _maybeResetScroll(elapsed);

    final visibleChanged = _controller.update(delta.inMicroseconds / 1000.0);
    if (!mounted) return;

    // 只有「视区内有哪些行」变化时才需要重建 widget 树；
    // 位移/透明度/逐词渐变这些连续量走 _frame 通知，只触发重绘不触发重建。
    if (visibleChanged) {
      setState(() {});
    } else {
      _frame.value++;
    }
  }

  /// 帧计数器：驱动重绘而不重建 widget 树。
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  /// 惯性滚动。
  void _advanceInertia(Duration delta) {
    if (!_inertiaActive) return;
    final dtMs = delta.inMicroseconds / 1000.0;
    if (dtMs <= 0 || dtMs > 100) return;

    if (_scrollVelocity.abs() > 0.05) {
      _controller.scrollState.scrollOffset -= _scrollVelocity * dtMs;
      _controller.scrollState.clampOffset();
      _scrollVelocity *= math.pow(kScrollFriction, dtMs / 16).toDouble();
      _controller.calcLayout(sync: true, force: true);
    } else {
      _inertiaActive = false;
      _controller.scrollState.isUserScrolling = false;
      _scrollIdleSince = _lastTick;
      _controller.calcLayout(sync: true);
    }
  }

  /// 用户停手 5s 后回归自动对齐。
  void _maybeResetScroll(Duration now) {
    final idleSince = _scrollIdleSince;
    if (idleSince == null) return;
    if (_controller.scrollState.scrollOffset == 0) {
      _scrollIdleSince = null;
      return;
    }
    if (now - idleSince >= kScrollResetDelay) {
      _scrollIdleSince = null;
      _controller.resetScroll();
      _controller.calcLayout();
    }
  }

  // ---- 手势 ----

  void _onDragStart(DragStartDetails details) {
    if (!widget.allowScroll) return;
    _inertiaActive = false;
    _scrollIdleSince = null;
    _controller.scrollState.isUserScrolling = true;
    _controller.scrollState.isScrolled = true;
    _dragStartOffset = _controller.scrollState.scrollOffset;
    _accumulatedDragDy = 0;
    _lastDragY = 0;
    _lastDragTime = _lastTick;
    _scrollVelocity = 0;
    _controller.calcLayout(sync: true, force: true);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.allowScroll) return;

    // 累计位移相对拖拽起点，避免逐帧 delta 累加带来的漂移
    _accumulatedDragDy += details.delta.dy;
    _controller.scrollState.scrollOffset =
        _dragStartOffset - _accumulatedDragDy;
    _controller.scrollState.clampOffset();

    // 顺带估一个瞬时速度，作为 onDragEnd 拿不到 velocity 时的兜底
    final dt = (_lastTick - _lastDragTime).inMicroseconds / 1000.0;
    if (dt > 0) {
      _scrollVelocity = (_accumulatedDragDy - _lastDragY) / dt;
      _lastDragY = _accumulatedDragDy;
      _lastDragTime = _lastTick;
    }

    _controller.calcLayout(sync: true, force: true);
  }

  double _accumulatedDragDy = 0;

  void _onDragEnd(DragEndDetails details) {
    _accumulatedDragDy = 0;
    if (!widget.allowScroll) return;

    // 手势识别器给的速度更准；为 0 时退回拖拽过程中估的瞬时速度
    var velocity = details.velocity.pixelsPerSecond.dy / 1000.0;
    if (velocity == 0) velocity = _scrollVelocity;
    _scrollVelocity = velocity.abs() < 0.1 ? 0 : velocity;
    _inertiaActive = _scrollVelocity != 0;
    if (!_inertiaActive) {
      _controller.scrollState.isUserScrolling = false;
      _scrollIdleSince = _lastTick;
      _controller.calcLayout(sync: true);
    }
  }

  void _onDragCancel() {
    _accumulatedDragDy = 0;
    _inertiaActive = false;
    _controller.scrollState.isUserScrolling = false;
    _scrollIdleSince = _lastTick;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (!widget.allowScroll) return;
    if (event is! PointerScrollEvent) return;
    _scrollIdleSince = _lastTick;
    _controller.scrollState.isScrolled = true;
    _controller.scrollState.scrollOffset += event.scrollDelta.dy;
    _controller.scrollState.clampOffset();
    _controller.calcLayout(sync: true);
  }

  void _onTapUp(TapUpDetails details) {
    final index = _controller.hitTestGroup(details.localPosition.dy);
    if (index == null) {
      widget.onTapBlank?.call();
      return;
    }
    final group = _controller.groups[index];
    // 跳转用未经优化的原始起始时间，避免把提前量也算进去
    final rawIndex = math.min(index, widget.lines.length - 1);
    final target = rawIndex >= 0
        ? widget.lines[rawIndex].startTime
        : group.startTime;
    final seekMs = target - widget.timeOffsetMs;
    if (seekMs >= 0) {
      _controller
        ..resetScroll()
        ..calcLayout();
      widget.onSeek?.call(Duration(milliseconds: seekMs));
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    widget.positionListenable.removeListener(_onPositionChanged);
    _controller.dispose();
    _frame.dispose();
    super.dispose();
  }

  /// 按视口宽度推导默认字号。
  ///
  /// 对应 CSS 的 `font-size: max(8vw, 12px)`（窄屏）与
  /// `max(max(5vh, 2.5vw), 12px)`（宽屏）。
  TextStyle _resolveTextStyle(Size size) {
    final provided = widget.textStyle;
    if (provided != null) {
      return provided.copyWith(height: provided.height ?? 1.2);
    }
    final isCompact = size.width <= 768;
    final fontSize = isCompact
        ? math.max(size.width * 0.08, 12.0)
        : math.max(math.max(size.height * 0.05, size.width * 0.025), 12.0);
    return TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      height: 1.2,
      color: widget.baseColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lines.isEmpty) {
      return const SizedBox.expand();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final textStyle = _resolveTextStyle(size);
        final contentWidth = math.max(
          0.0,
          size.width - widget.horizontalPadding * 2,
        );

        _controller.setViewport(
          size: size,
          textStyle: textStyle,
          contentMaxWidth: contentWidth,
        );

        // 首次拿到尺寸后才能构建内容
        if (_controller.groups.isEmpty && widget.lines.isNotEmpty) {
          _loadLines();
        }
        _controller.primeVisibleGroups();

        return Listener(
          onPointerSignal: _onPointerSignal,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _onTapUp,
            onVerticalDragStart: _onDragStart,
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            onVerticalDragCancel: _onDragCancel,
            // 帧通知放在 Stack 外层：Positioned 必须是 Stack 的直接子级，
            // 不能套在 ValueListenableBuilder 里，否则定位失效。
            child: ClipRect(
              child: ValueListenableBuilder<int>(
                valueListenable: _frame,
                builder: (context, _, _) => Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: _buildChildren(textStyle, contentWidth),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildChildren(TextStyle textStyle, double contentWidth) {
    final children = <Widget>[];

    for (final index in _controller.visibleGroups) {
      if (index < 0 || index >= _controller.groups.length) continue;
      final group = _controller.groups[index];
      children.add(
        _AmllGroupWidget(
          key: ValueKey<int>(index),
          group: group,
          currentTimeMs: _paintTimeMs,
          textStyle: textStyle,
          contentWidth: contentWidth,
          horizontalPadding: widget.horizontalPadding,
          baseColor: widget.baseColor,
          enableGlow: widget.enableGlow,
          showTranslation: widget.showTranslation,
          showRoman: widget.showRoman,
          isDuet: group.isDuet,
          verticalPadding: _controller.lineVerticalPadding,
        ),
      );
    }

    // 间奏点
    final placement = _controller.interludeDots;
    final dotsState = _controller.interludeDotsState;
    if (placement != null && dotsState.isVisible) {
      final dotSize = _controller.interludeDotDiameter;
      children.add(
        Positioned(
          top: placement.top,
          left: widget.horizontalPadding,
          width: contentWidth,
          height: dotSize,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: InterludeDotsPainter(
                state: dotsState,
                color: widget.baseColor,
                dotSize: dotSize,
                gap: dotSize * 0.5,
                alignRight: placement.alignRight,
              ),
            ),
          ),
        ),
      );
    }

    return children;
  }
}

/// 单个歌词组的 widget：主歌词 + 翻译/音译 + 背景人声。
class _AmllGroupWidget extends StatelessWidget {
  const _AmllGroupWidget({
    super.key,
    required this.group,
    required this.currentTimeMs,
    required this.textStyle,
    required this.contentWidth,
    required this.horizontalPadding,
    required this.baseColor,
    required this.enableGlow,
    required this.showTranslation,
    required this.showRoman,
    required this.isDuet,
    required this.verticalPadding,
  });

  final AmllLyricGroup group;
  final int currentTimeMs;
  final TextStyle textStyle;
  final double contentWidth;
  final double horizontalPadding;
  final Color baseColor;
  final bool enableGlow;
  final bool showTranslation;
  final bool showRoman;
  final bool isDuet;

  /// 行的上下内边距（单侧），由控制器统一提供以保证与高度计算一致
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final mainLayout = group.mainLine.layout;
    if (mainLayout == null) return const SizedBox.shrink();

    final scale = group.mainLine.currentScale;
    final blur = group.blur;

    Widget content = Column(
      crossAxisAlignment: isDuet
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // 背景人声在主歌词之前
        if (group.bgLine != null && group.isBgFirst) _buildBgLine(),
        _buildMainLine(mainLayout.size),
        _buildSubLines(),
        if (group.bgLine != null && !group.isBgFirst) _buildBgLine(),
      ],
    );

    // 行的上下内边距，对应 .lyricLineWrapper 的 padding: 0.4em
    content = Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: content,
    );

    // 不套 Opacity：透明度已经乘进各 painter 的颜色里，
    // 套了会每帧 saveLayer（离屏缓冲），代价很高。
    content = Transform.scale(
      scale: scale,
      alignment: isDuet ? Alignment.centerRight : Alignment.centerLeft,
      child: content,
    );

    if (blur > 0.05) {
      content = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: content,
      );
    }

    // 必须用 Positioned：它是 Stack 的定位子级，不参与 Stack 的尺寸计算。
    // 换成 Transform.translate 会让本组变成非定位子级 —— Transform 只偏移
    // 绘制、不改变布局位置，所有行会被挤在 Stack 左上角。
    return Transform.translate(
      offset: Offset(horizontalPadding, group.currentTop),
      child: SizedBox(
        width: contentWidth,
        child: RepaintBoundary(child: content),
      ),
    );
  }

  double get _groupOpacity => group.opacity.clamp(0.0, 1.0);

  Widget _buildMainLine(Size size) {
    final painter = group.mainLine.buildPainter(
      currentTimeMs: currentTimeMs,
      textStyle: textStyle,
      baseColor: baseColor,
      enableGlow: enableGlow,
      groupOpacity: _groupOpacity,
    );
    if (painter == null) return SizedBox(height: size.height);
    return CustomPaint(size: Size(contentWidth, size.height), painter: painter);
  }

  Widget _buildBgLine() {
    final bg = group.bgLine;
    final layout = bg?.layout;
    if (bg == null || layout == null) return const SizedBox.shrink();

    final progress = group.bgActiveProgress;
    if (progress <= 0.001) return const SizedBox.shrink();

    final bgStyle = textStyle.copyWith(
      fontSize: math.max((textStyle.fontSize ?? 24) * 0.7, 10),
    );
    // 背景人声的进场透明度同样乘进颜色，避免额外的 saveLayer
    final painter = bg.buildPainter(
      currentTimeMs: currentTimeMs,
      textStyle: bgStyle,
      baseColor: baseColor,
      enableGlow: enableGlow,
      groupOpacity: _groupOpacity * progress.clamp(0.0, 1.0),
    );
    if (painter == null) return const SizedBox.shrink();

    // 隐藏时向上/下滑出并缩小，与 DOM 的 bgWrapper 一致
    final slidePx = group.bgSlidePercent / 100 * layout.size.height;
    return Transform.translate(
      offset: Offset(0, slidePx),
      child: Transform.scale(
        scale: group.bgScale,
        alignment: isDuet ? Alignment.topRight : Alignment.topLeft,
        child: SizedBox(
          height: layout.size.height * progress,
          child: CustomPaint(
            size: Size(contentWidth, layout.size.height),
            painter: painter,
          ),
        ),
      ),
    );
  }

  Widget _buildSubLines() {
    final line = group.mainLine.line;
    final translation = showTranslation ? line.translatedLyric : '';
    final roman = showRoman ? line.romanLyric : '';
    if (translation.isEmpty && roman.isEmpty) return const SizedBox.shrink();

    // 样式与间距必须与 measureSubLines 完全一致，否则组高度会算错、
    // 下一行歌词就会压到翻译上。
    final subStyle = subLineStyle(
      textStyle,
    ).copyWith(color: baseColor.withValues(alpha: 0.3 * _groupOpacity));

    return Padding(
      padding: EdgeInsets.only(top: subLineGap(textStyle)),
      child: Column(
        crossAxisAlignment: isDuet
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (translation.isNotEmpty)
            Text(
              translation,
              style: subStyle,
              textAlign: isDuet ? TextAlign.right : TextAlign.left,
            ),
          if (roman.isNotEmpty)
            Text(
              roman,
              style: subStyle,
              textAlign: isDuet ? TextAlign.right : TextAlign.left,
            ),
        ],
      ),
    );
  }
}
