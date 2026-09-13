/// AMLL v2 歌词视图：把 [V2LyricPlayer] 接到 Flutter 的帧循环与手势上。
///
/// 对应上游宿主（`react` 包的 `LyricPlayer` 组件）+ `base.ts` 构造函数里那段
/// `touchstart` / `touchmove` / `touchend` / `wheel` 监听。滚动的摩擦系数、
/// 5 秒回归、边界判定全部照抄，不另起一套惯性模型。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'core/interfaces.dart';
import 'player/lyric_player.dart';
import 'render/lyric_painter.dart';
import 'render/metrics.dart';

class AmllV2LyricView extends StatefulWidget {
  const AmllV2LyricView({
    super.key,
    required this.lines,
    required this.positionListenable,
    required this.isPlaying,
    this.onSeek,
    this.onTapBlank,
    this.fontSizeOverride,
    this.fontFamily,
    this.color = const Color(0xFFFFFFFF),
    this.fontWeight = FontWeight.w700,
    this.alignPosition = 0.35,
    this.alignAnchor = 'center',
    this.wordFadeWidth = 0.5,
    this.enableBlur = true,
    this.enableScale = true,
    this.enableSpring = true,
    this.hidePassedLines = false,
    this.allowScroll = true,
    this.overscanPx = 300,
  });

  final List<V2LyricLine> lines;
  final ValueListenable<Duration> positionListenable;
  final bool isPlaying;
  final void Function(Duration position)? onSeek;
  final VoidCallback? onTapBlank;

  /// 覆盖 `--amll-lp-font-size`；null 时走样式表里的 `max(max(5vh,2.5vw),12px)`
  final double? fontSizeOverride;
  final String? fontFamily;

  /// `--amll-lp-color`
  final Color color;
  final FontWeight fontWeight;

  final double alignPosition;

  /// `"top" | "bottom" | "center"`
  final String alignAnchor;

  final double wordFadeWidth;
  final bool enableBlur;
  final bool enableScale;
  final bool enableSpring;
  final bool hidePassedLines;
  final bool allowScroll;
  final double overscanPx;

  @override
  State<AmllV2LyricView> createState() => _AmllV2LyricViewState();
}

class _AmllV2LyricViewState extends State<AmllV2LyricView>
    with SingleTickerProviderStateMixin {
  final V2LyricPlayer _player = V2LyricPlayer();
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  V2CssMetrics? _metrics;
  int _lastTimeMs = 0;

  // base.ts 构造函数里的滚动局部变量
  double _startScrollY = 0;
  double _startTouchPosY = 0;
  String _direction = 'none';
  int _startScrollTime = 0;
  int _lastDragTime = 0;
  double _lastMoveY = 0;
  double _scrollSpeed = 0;
  bool _flinging = false;

  @override
  void initState() {
    super.initState();
    _applyOptions();
    _ticker = createTicker(_onTick)..start();
    widget.positionListenable.addListener(_onPosition);
  }

  @override
  void didUpdateWidget(AmllV2LyricView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.positionListenable, widget.positionListenable)) {
      oldWidget.positionListenable.removeListener(_onPosition);
      widget.positionListenable.addListener(_onPosition);
    }
    _applyOptions();
    if (!identical(oldWidget.lines, widget.lines)) {
      _setLines();
    }
    if (oldWidget.isPlaying != widget.isPlaying) {
      widget.isPlaying ? _player.resume() : _player.pause();
    }
  }

  void _applyOptions() {
    _player
      ..setAlignPosition(widget.alignPosition)
      ..setAlignAnchor(widget.alignAnchor)
      ..setWordFadeWidth(widget.wordFadeWidth)
      ..setEnableBlur(widget.enableBlur)
      ..setEnableScale(widget.enableScale)
      ..setEnableSpring(widget.enableSpring)
      ..setHidePassedLines(widget.hidePassedLines)
      ..setOverscanPx(widget.overscanPx)
      ..allowScroll = widget.allowScroll;
  }

  bool _linesLoaded = false;

  void _setLines() {
    _player.setLyricLines(
      widget.lines.map((l) => l.clone()).toList(),
      widget.positionListenable.value.inMilliseconds,
    );
    _linesLoaded = true;
    widget.isPlaying ? _player.resume() : _player.pause();
  }

  void _onPosition() {
    final ms = widget.positionListenable.value.inMilliseconds;
    final isSeek = (ms - _lastTimeMs).abs() > 500;
    _lastTimeMs = ms;
    _player.setCurrentTime(ms, isSeek);
  }

  void _onTick(Duration elapsed) {
    final delta = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1000.0;
    _lastTick = elapsed;
    if (_flinging) _stepFling(delta);
    _player.update(delta);
    // 弹簧/时钟每帧都在推进，绘制层靠 player 这个 Listenable 重绘
    _player.repaint();
  }

  @override
  void dispose() {
    widget.positionListenable.removeListener(_onPosition);
    _ticker.dispose();
    _player.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------- 滚动

  int get _now => DateTime.now().millisecondsSinceEpoch;

  void _onDragStart(DragStartDetails details) {
    if (!_player.beginScrollHandler()) return;
    _flinging = false;
    _startScrollY = _player.scrollOffset;
    _startTouchPosY = details.globalPosition.dy;
    _lastMoveY = _startTouchPosY;
    _startScrollTime = _now;
    _scrollSpeed = 0;
    _direction = 'none';
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_player.beginScrollHandler()) return;
    final touchScreenY = details.globalPosition.dy;
    final delta = touchScreenY - _startTouchPosY;
    final lastDelta = touchScreenY - _lastMoveY;
    final targetDirection = lastDelta > 0
        ? 'down'
        : lastDelta < 0
        ? 'up'
        : 'none';
    if (_direction != targetDirection) {
      _direction = targetDirection;
      _startScrollY = _player.scrollOffset;
      _startTouchPosY = touchScreenY;
      _startScrollTime = _now;
    } else {
      _player.scrollOffset = _startScrollY - delta;
    }
    _lastMoveY = touchScreenY;
    _lastDragTime = _now;
    _player.limitScrollOffset();
    _player.calcLayout(true);
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_player.beginScrollHandler()) return;
    _startTouchPosY = 0;
    final curTime = _now;
    if (curTime - _lastDragTime > 100) return;
    final scrollDuration = curTime - _startScrollTime;
    if (scrollDuration <= 0) return;
    _scrollSpeed =
        ((_player.scrollOffset - _startScrollY) / scrollDuration) * 1000;
    _flinging = true;
  }

  /// `onScrollFrame`：每帧 `scrollSpeed *= 0.99`，撞到边界或速度 < 1 即停。
  void _stepFling(double deltaMs) {
    if (!_player.beginScrollHandler()) {
      _flinging = false;
      return;
    }
    _player.scrollOffset += (_scrollSpeed * deltaMs) / 1000;
    _scrollSpeed *= 0.99;
    _player.limitScrollOffset();
    _player.calcLayout(true);
    if (_scrollSpeed.abs() <= 1 ||
        _player.scrollBoundary.contains(_player.scrollOffset)) {
      _flinging = false;
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_player.beginScrollHandler()) return;
    _flinging = false;
    _player.scrollOffset += event.scrollDelta.dy;
    _player.limitScrollOffset();
    _player.calcLayout(true);
  }

  // ----------------------------------------------------------------- 点击

  void _onTapUp(TapUpDetails details) {
    final local = details.localPosition;
    for (var i = 0; i < _player.currentLyricLineObjects.length; i++) {
      final el = _player.currentLyricLineObjects[i];
      final layout = el.layout;
      if (layout == null) continue;
      final top = el.posY.getCurrentPosition();
      if (local.dy < top || local.dy > top + layout.size.height) continue;
      final onSeek = widget.onSeek;
      if (onSeek == null) break;
      // 跳转用未被 `setLyricLines` 提早一秒改写过的原始时间
      final source = i < _player.currentLyricLines.length
          ? _player.currentLyricLines[i]
          : el.line;
      _player.resetScroll();
      _flinging = false;
      onSeek(Duration(milliseconds: source.startTime));
      _player.setCurrentTime(source.startTime, true);
      return;
    }
    widget.onTapBlank?.call();
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final playerSize = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
        );
        final metrics = V2CssMetrics(
          playerSize: playerSize,
          windowSize: media.size,
          hasDuetLine: _player.hasDuetLine,
          fontSizeOverride: widget.fontSizeOverride,
          fontFamily: widget.fontFamily,
          color: widget.color,
          fontWeight: widget.fontWeight,
        );

        if (!_linesLoaded) {
          _player.windowWidth = metrics.windowSize.width;
          _player.windowHeight = metrics.windowSize.height;
          _player.size = playerSize;
          _setLines();
        }
        if (!metrics.sameLayoutInputsAs(_metrics) ||
            _player.needsLayoutRebuild) {
          _metrics = metrics;
          if (!playerSize.isEmpty) {
            _player.rebuildLayouts(metrics, textScaler: media.textScaler);
          }
        }

        return Listener(
          onPointerSignal: _onPointerSignal,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _onTapUp,
            onVerticalDragStart: widget.allowScroll ? _onDragStart : null,
            onVerticalDragUpdate: widget.allowScroll ? _onDragUpdate : null,
            onVerticalDragEnd: widget.allowScroll ? _onDragEnd : null,
            child: CustomPaint(
              size: playerSize,
              isComplex: true,
              painter: V2LyricPainter(player: _player, metrics: metrics),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}
