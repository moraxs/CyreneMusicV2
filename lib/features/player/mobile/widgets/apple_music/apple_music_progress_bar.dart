import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../../amll_v2/core/spring.dart';

/// Apple Music 风格进度条：没有圆形滑块，靠轨道本身「按下变粗」。
///
/// 对标 AMLL（applemusic-like-lyrics）`react-full` 包里的 `BouncingSlider`
/// （`components/BouncingSlider/index.tsx` + `index.module.css`），参数照抄：
///
/// - 轨道高度由弹簧驱动，`stiffness: 150, mass: 1, damping: 10`；
///   AMLL 的弹簧位置在 80（静息）与 189（按下）之间跑，再乘 0.08 落成像素，
///   即 6.4px → 15.1px。本实现直接用像素跑弹簧（线性弹簧，缩放不改变动力学），
///   默认值就是这两个数。
/// - 已播放部分是纯白，静息 opacity 0.4、按下 0.9。
/// - 背景轨 `#ffffff26`（白 15%），圆角 100px。
/// - 拖过两端时整条会横向回弹：AMLL 取 `(relPos - 1) * 900` 再 `/100` 落成
///   像素，也就是超出一个整条宽度才位移 9px，越界越多推得越远。
///
/// 与 AMLL 的差异（有意为之）：
/// - AMLL 是鼠标语义（hover 就变粗），这里是触摸语义（按下才变粗）。
/// - 副歌高亮区间是本项目自有的功能，AMLL 没有，照旧保留。
class AppleMusicProgressBar extends StatefulWidget {
  const AppleMusicProgressBar({
    super.key,
    required this.value,
    required this.onSeek,
    this.onSeekStart,
    this.onSeekEnd,
    this.chorusTimes,
    this.durationMs = 0,
    this.activeColor = Colors.white,
    this.inactiveColor = const Color(0x26FFFFFF),
    this.idleHeight = 6.4,
    this.activeHeight = 15.12,
    this.touchHeight = 37,
  });

  /// 当前进度，0..1。拖动期间本控件用手指位置覆盖它，松手后重新跟随。
  final double value;

  /// 拖动/点击过程中持续回报目标进度（0..1）。节流交给调用方。
  final ValueChanged<double> onSeek;

  final VoidCallback? onSeekStart;

  /// 松手时回报最终进度。
  final ValueChanged<double>? onSeekEnd;

  /// 副歌区间，元素形如 `{'startTime': ms, 'endTime': ms}`。
  final List<Map<String, int>>? chorusTimes;

  final double durationMs;

  final Color activeColor;
  final Color inactiveColor;

  /// 静息 / 按下时的轨道高度。
  final double idleHeight;
  final double activeHeight;

  /// 整个控件的高度，也就是触摸热区；轨道在其中垂直居中。
  /// AMLL 用 `min-height: calc(1.16em * 2)`，约 37px。
  final double touchHeight;

  @override
  State<AppleMusicProgressBar> createState() => _AppleMusicProgressBarState();
}

class _AppleMusicProgressBarState extends State<AppleMusicProgressBar>
    with SingleTickerProviderStateMixin {
  /// 轨道高度（像素）。
  late final V2Spring _heightSpring = V2Spring(widget.idleHeight)
    ..updateParams(
      const V2SpringParams(stiffness: 150, mass: 1, damping: 10),
    );

  /// 越界横向回弹位移（像素）。AMLL 只给了 stiffness，其余走默认。
  late final V2Spring _bounceSpring = V2Spring(0)
    ..updateParams(const V2SpringParams(stiffness: 150));

  /// 只在 initState 里建一次，之后靠 start/stop 复用。
  ///
  /// 两个都别改：
  /// - 不要改成「收敛后 dispose、要用时再 createTicker」——
  ///   [SingleTickerProviderStateMixin] 全生命周期只肯发一个 Ticker，第二次
  ///   createTicker 会直接抛断言，弹簧就再也动不了了。
  /// - 不要改成 `late final ... = createTicker(...)` —— 若这条进度条从头到尾
  ///   没被碰过，字段会拖到 dispose() 才第一次求值，而 createTicker 这时要查
  ///   `TickerMode.of(context)`，树已经拆了，直接抛
  ///   「Looking up a deactivated widget's ancestor」。
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  /// 拖动期间的本地进度，松手置空。
  double? _dragValue;
  bool _pressed = false;

  double _trackHeight = 0;
  double _bounceOffset = 0;

  @override
  void initState() {
    super.initState();
    _trackHeight = widget.idleHeight;
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  /// 弹簧收敛后就停 ticker，别白烧一帧一帧的电。
  void _startTicker() {
    final ticker = _ticker;
    if (ticker == null || ticker.isActive) return;
    // Ticker 的 elapsed 从每次 start 起算，所以上一轮的时间戳要清掉。
    _lastTick = Duration.zero;
    ticker.start();
  }

  void _stopTicker() {
    final ticker = _ticker;
    if (ticker != null && ticker.isActive) ticker.stop();
  }

  void _onTick(Duration elapsed) {
    // V2Spring 的时间单位是秒，和 JS 侧一致。
    final delta = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;

    _heightSpring.update(delta);
    _bounceSpring.update(delta);

    final nextHeight = _heightSpring.getCurrentPosition();
    final nextBounce = _bounceSpring.getCurrentPosition();
    if (nextHeight != _trackHeight || nextBounce != _bounceOffset) {
      setState(() {
        _trackHeight = nextHeight;
        _bounceOffset = nextBounce;
      });
    }

    if (_heightSpring.arrived() && _bounceSpring.arrived()) _stopTicker();
  }

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    _pressed = pressed;
    _heightSpring.setTargetPosition(
      pressed ? widget.activeHeight : widget.idleHeight,
    );
    _startTicker();
  }

  /// 把本地横坐标换成 0..1 的进度，并顺手喂越界回弹弹簧。
  double _valueFromDx(double dx, double width) {
    if (width <= 0) return 0;
    final relPos = dx / width;

    // AMLL：越界量按 `(relPos - 1) * 900` 起算，落到像素再 /100。
    final overshoot = relPos > 1
        ? (relPos - 1) * 900
        : (relPos < 0 ? relPos * 900 : 0.0);
    final bounceTarget = overshoot / 100;
    _bounceSpring.setPosition(bounceTarget);
    _bounceSpring.setTargetPosition(bounceTarget);
    _startTicker();

    return relPos.clamp(0.0, 1.0);
  }

  void _release() {
    _setPressed(false);
    _bounceSpring.setTargetPosition(0);
    _startTicker();
    final committed = _dragValue;
    setState(() => _dragValue = null);
    if (committed != null) widget.onSeekEnd?.call(committed);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final shown = (_dragValue ?? widget.value).clamp(0.0, 1.0);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            _setPressed(true);
            final v = _valueFromDx(details.localPosition.dx, width);
            setState(() => _dragValue = v);
            widget.onSeekStart?.call();
            widget.onSeek(v);
          },
          onTapUp: (_) => _release(),
          onTapCancel: _release,
          onHorizontalDragStart: (details) {
            _setPressed(true);
            final v = _valueFromDx(details.localPosition.dx, width);
            setState(() => _dragValue = v);
            widget.onSeekStart?.call();
            widget.onSeek(v);
          },
          onHorizontalDragUpdate: (details) {
            final v = _valueFromDx(details.localPosition.dx, width);
            setState(() => _dragValue = v);
            widget.onSeek(v);
          },
          onHorizontalDragEnd: (_) => _release(),
          onHorizontalDragCancel: _release,
          child: SizedBox(
            height: widget.touchHeight,
            width: double.infinity,
            child: Center(
              child: Transform.translate(
                offset: Offset(_bounceOffset, 0),
                child: CustomPaint(
                  size: Size(width, widget.activeHeight),
                  painter: AppleMusicProgressBarPainter(
                    progress: shown,
                    trackHeight: _trackHeight,
                    // CSS 里 `:active` 把已播放部分从 0.4 提到 0.9。
                    fillOpacity: _pressed ? 0.9 : 0.4,
                    activeColor: widget.activeColor,
                    inactiveColor: widget.inactiveColor,
                    chorusTimes: widget.chorusTimes,
                    durationMs: widget.durationMs,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 进度条画笔。公开是为了让测试能读到 [trackHeight] —— 轨道「按下变粗」是这条
/// 进度条的核心行为，藏在私有类里就没法断言了。
@visibleForTesting
class AppleMusicProgressBarPainter extends CustomPainter {
  AppleMusicProgressBarPainter({
    required this.progress,
    required this.trackHeight,
    required this.fillOpacity,
    required this.activeColor,
    required this.inactiveColor,
    required this.chorusTimes,
    required this.durationMs,
  });

  final double progress;
  final double trackHeight;
  final double fillOpacity;
  final Color activeColor;
  final Color inactiveColor;
  final List<Map<String, int>>? chorusTimes;
  final double durationMs;

  @override
  void paint(Canvas canvas, Size size) {
    final h = trackHeight.clamp(0.0, size.height);
    final top = (size.height - h) / 2;
    final trackRect = Rect.fromLTWH(0, top, size.width, h);
    // CSS 是 border-radius: 100px，实际就是按高度取满圆角。
    final rrect = RRect.fromRectAndRadius(trackRect, Radius.circular(h / 2));

    canvas.save();
    // 轨道整体裁剪，填充与副歌都不会溢出圆角。
    canvas.clipRRect(rrect);

    // 1. 背景轨
    canvas.drawRect(trackRect, Paint()..color = inactiveColor);

    // 2. 已播放部分
    canvas.drawRect(
      Rect.fromLTWH(0, top, size.width * progress, h),
      Paint()..color = activeColor.withValues(alpha: fillOpacity),
    );

    // 3. 副歌高亮（本项目自有）。和旧实现一致，盖在上面两层之上。
    if (durationMs > 0 && chorusTimes != null && chorusTimes!.isNotEmpty) {
      final chorusPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.5);
      for (final chorus in chorusTimes!) {
        final startMs = chorus['startTime']?.toDouble() ?? 0.0;
        final endMs = chorus['endTime']?.toDouble() ?? 0.0;
        if (startMs >= endMs) continue;
        final startX = (startMs / durationMs).clamp(0.0, 1.0) * size.width;
        final endX = (endMs / durationMs).clamp(0.0, 1.0) * size.width;
        canvas.drawRect(
          Rect.fromLTRB(startX, top, endX, top + h),
          chorusPaint,
        );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(AppleMusicProgressBarPainter old) =>
      old.progress != progress ||
      old.trackHeight != trackHeight ||
      old.fillOpacity != fillOpacity ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor ||
      old.durationMs != durationMs ||
      old.chorusTimes != chorusTimes;
}
