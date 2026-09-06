import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'monet_palette.dart';

/// 「莫奈」的飘落装饰层：十片极淡的樱花瓣在整幅画面上缓慢游走。
///
/// 移植自上游 `MonetFloatingDecor.tsx`。上游会优先用主题里配的 lucide 图标，
/// 没配才回退到樱花瓣；本项目没有「歌词主题图标」这一层，所以只保留樱花瓣分支。
///
/// 粒子的位置、大小、时长全部由序号算死（`(i * 127 + 43) % 80` 这类整数序列），
/// 不用随机数——换歌、重开播放器看到的都是同一组构图，这是上游刻意的。
class MonetFloatingDecor extends StatefulWidget {
  const MonetFloatingDecor({
    super.key,
    required this.palette,
    this.animate = true,
  });

  final MonetPalette palette;

  /// 关掉后按每片花瓣的初始角度静态摆放（上游的 `staticMode`）。
  final bool animate;

  @override
  State<MonetFloatingDecor> createState() => _MonetFloatingDecorState();
}

class _MonetFloatingDecorState extends State<MonetFloatingDecor>
    with SingleTickerProviderStateMixin {
  /// 花瓣的重绘间隔。
  ///
  /// 一片花瓣最快也就 360°/20s，一帧挪不到半个像素，按 60fps 整屏重绘纯属浪费；
  /// 更要紧的是这块背景每变一次，压在上面的液态玻璃就得重采样一次。20fps 下
  /// 单步位移仍在亚像素级，看不出台阶。
  static const Duration _kFrameInterval = Duration(milliseconds: 50);

  /// 逐帧写入的经过秒数。只驱动重绘，不触发 build。
  final ValueNotifier<double> _seconds = ValueNotifier<double>(0);
  Ticker? _ticker;
  Duration _lastPaintedAt = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _startTicker();
  }

  @override
  void didUpdateWidget(covariant MonetFloatingDecor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate == oldWidget.animate) return;
    if (widget.animate) {
      _startTicker();
    } else {
      _stopTicker();
      _seconds.value = 0;
    }
  }

  @override
  void dispose() {
    _stopTicker();
    _seconds.dispose();
    super.dispose();
  }

  void _startTicker() {
    _ticker = createTicker((elapsed) {
      if (elapsed - _lastPaintedAt < _kFrameInterval) return;
      _lastPaintedAt = elapsed;
      _seconds.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    })..start();
  }

  void _stopTicker() {
    _ticker
      ?..stop()
      ..dispose();
    _ticker = null;
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      // ClipRect 不能省：花瓣按百分比定位后还要叠一段 ±60px 的位移，CustomPaint
      // 本身又不裁剪，所以贴边的那几片会画到盒子外面去。外层给这一层留出的底部
      // 空档（不让它垫在液态玻璃胶囊下面）只有裁剪之后才真正成立。
      child: ClipRect(
        child: CustomPaint(
          size: Size.infinite,
          painter: _MonetPetalPainter(
            seconds: _seconds,
            color: monetAlpha(widget.palette.secondary, .55),
            animate: widget.animate,
          ),
        ),
      ),
    ),
  );
}

const int _kParticleCount = 10;

class _Petal {
  const _Petal({
    required this.xPercent,
    required this.yPercent,
    required this.size,
    required this.rotationDeg,
    required this.durationSeconds,
    required this.delaySeconds,
    required this.opacity,
    required this.reverse,
  });

  factory _Petal.forIndex(int i) => _Petal(
    xPercent: ((i * 127 + 43) % 80) + 10,
    yPercent: ((i * 211 + 17) % 80) + 5,
    size: (46 + ((i * 53) % 40)).toDouble(),
    rotationDeg: ((i * 97) % 360).toDouble(),
    durationSeconds: (20 + ((i * 71) % 20)).toDouble(),
    delaySeconds: ((i * 41) % 80) / 10,
    opacity: 0.06 + ((i * 31) % 12) / 100,
    reverse: i.isEven,
  );

  final double xPercent;
  final double yPercent;
  final double size;
  final double rotationDeg;
  final double durationSeconds;
  final double delaySeconds;
  final double opacity;
  final bool reverse;

  List<double> get yTrack =>
      reverse ? const [-40, 60, -20, 40, -40] : const [40, -60, 20, -40, 40];

  List<double> get xTrack =>
      reverse ? const [15, -25, 10, -20, 15] : const [-15, 25, -10, 20, -15];

  List<double> get rotationTrack {
    final swing = reverse ? -1 : 1;
    return [
      rotationDeg,
      rotationDeg + 120 * swing,
      rotationDeg + 60 * swing,
      rotationDeg + 180 * swing,
      rotationDeg,
    ];
  }

  List<double> get opacityTrack => [
    opacity * 0.6,
    opacity * 1.2,
    opacity,
    opacity * 1.3,
    opacity * 0.7,
  ];
}

final List<_Petal> _kPetals = List<_Petal>.generate(
  _kParticleCount,
  _Petal.forIndex,
  growable: false,
);

class _MonetPetalPainter extends CustomPainter {
  _MonetPetalPainter({
    required this.seconds,
    required this.color,
    required this.animate,
  }) : super(repaint: seconds);

  final ValueListenable<double> seconds;
  final Color color;
  final bool animate;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final elapsed = seconds.value;

    for (final petal in _kPetals) {
      final left = size.width * petal.xPercent / 100;
      final top = size.height * petal.yPercent / 100;

      final double dx;
      final double dy;
      final double rotation;
      final double opacity;
      if (animate) {
        final t = _loopProgress(elapsed, petal);
        dx = _keyframe(petal.xTrack, t);
        dy = _keyframe(petal.yTrack, t);
        rotation = _keyframe(petal.rotationTrack, t);
        opacity = _keyframe(petal.opacityTrack, t);
      } else {
        dx = 0;
        dy = 0;
        rotation = petal.rotationDeg;
        opacity = petal.opacity;
      }

      canvas.save();
      canvas.translate(left + dx, top + dy);
      // CSS 的 `transform: rotate()` 绕元素中心转，这里的图元原点在左上角。
      canvas.translate(petal.size / 2, petal.size / 2);
      canvas.rotate(rotation * math.pi / 180);
      canvas.translate(-petal.size / 2, -petal.size / 2);
      canvas.scale(petal.size / 24);
      _paintPetal(canvas, color.withValues(alpha: color.a * opacity));
      canvas.restore();
    }
  }

  /// framer-motion 的 `repeat: Infinity` + `delay`：延迟内停在第一帧，之后循环。
  double _loopProgress(double elapsed, _Petal petal) {
    final shifted = elapsed - petal.delaySeconds;
    if (shifted <= 0) return 0;
    final loops = shifted / petal.durationSeconds;
    return loops - loops.floorToDouble();
  }

  @override
  bool shouldRepaint(covariant _MonetPetalPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.animate != animate ||
      oldDelegate.seconds != seconds;
}

/// 关键帧数组按等间隔铺满一个循环，段内走 easeInOut（framer-motion 的默认缓动）。
double _keyframe(List<double> values, double progress) {
  if (values.length == 1) return values.first;
  final position = progress.clamp(0.0, 1.0) * (values.length - 1);
  final index = position.floor().clamp(0, values.length - 2);
  final eased = Curves.easeInOut.transform((position - index).clamp(0.0, 1.0));
  return values[index] + (values[index + 1] - values[index]) * eased;
}

/// 24×24 视图框里的一片樱花瓣，与上游 `SakuraPetal` 的 SVG 路径逐段等价。
void _paintPetal(Canvas canvas, Color color) {
  final petal = Path()
    ..moveTo(12, 3)
    ..cubicTo(14.5, 5.5, 16.8, 9, 16, 14)
    ..cubicTo(15.2, 19, 13.5, 21, 12, 21)
    ..cubicTo(10.5, 21, 8.8, 19, 8, 14)
    ..cubicTo(7.2, 9, 9.5, 5.5, 12, 3)
    ..close();
  canvas.drawPath(petal, Paint()..color = color);

  final vein = Path()
    ..moveTo(12, 6)
    ..cubicTo(12, 6, 11.3, 10.5, 11.3, 14.5)
    ..cubicTo(11.3, 17.5, 12, 20, 12, 20);
  canvas.drawPath(
    vein,
    Paint()
      ..color = color.withValues(alpha: color.a * .35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .45
      ..strokeCap = StrokeCap.round,
  );
}
