import 'package:flutter/material.dart';

import '../../domain/models/track.dart';
import 'track_artwork.dart';

/// The classic desktop stage from the Next.js player: a large vinyl record,
/// inset album label and a separate tonearm. It deliberately stays free of a
/// card background so the ambient artwork remains part of the composition.
///
/// 独立成文件是为了让样式设置页的缩略预览也能画出同一张唱片——这里的绘制
/// 参数（纹路步长、唱臂贝塞尔控制点）全是手调的魔数，复制一份必然随时间漂移。
/// 本组件只吃 [track] / [size] / [isPlaying] 三个参数，不碰任何全局单例，
/// 因此在没有播放器上下文的地方（如设置页预览）也能直接用。
class ClassicRecordStage extends StatefulWidget {
  const ClassicRecordStage({
    super.key,
    required this.track,
    required this.size,
    required this.isPlaying,
    this.cover,
  });

  final Track track;
  final double size;
  final bool isPlaying;

  /// 唱片中心的封面。为 null 时走 [TrackArtwork]（真实播放器的路径）；预览场景
  /// 传一个自绘的渐变盘，避免 [TrackArtwork] 的空封面占位取设置页主题色，在
  /// 浅色模式下于黑胶中央糊出一块亮灰方块。
  final Widget? cover;

  @override
  State<ClassicRecordStage> createState() => _ClassicRecordStageState();
}

class _ClassicRecordStageState extends State<ClassicRecordStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation;

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
    if (widget.isPlaying) _rotation.repeat();
  }

  @override
  void didUpdateWidget(covariant ClassicRecordStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying == oldWidget.isPlaying) return;
    if (widget.isPlaying) {
      _rotation.repeat();
    } else {
      _rotation.stop();
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return Center(
      child: SizedBox(
        width: size * 1.12,
        height: size * 1.08,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 0,
              top: size * .04,
              width: size,
              height: size,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .48),
                      blurRadius: 54,
                      offset: const Offset(0, 24),
                    ),
                  ],
                ),
                child: RotationTransition(
                  turns: _rotation,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(painter: const _VinylPainter()),
                      Center(
                        child: Container(
                          width: size * .66,
                          height: size * .66,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .18),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: .35),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child:
                                widget.cover ??
                                TrackArtwork(
                                  track: widget.track,
                                  size: size * .66,
                                  borderRadius: size,
                                ),
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: size * .09,
                          height: size * .09,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFFE7E7E7),
                                Color(0xFF777777),
                                Color(0xFF171717),
                              ],
                            ),
                            border: Border.all(color: Colors.white38),
                            boxShadow: const [
                              BoxShadow(color: Colors.black54, blurRadius: 5),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: size * .005,
              top: 0,
              width: size * .27,
              height: size * .58,
              child: AnimatedRotation(
                turns: widget.isPlaying ? .067 : .011,
                alignment: const Alignment(.72, -.88),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                child: CustomPaint(painter: const _TonearmPainter()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VinylPainter extends CustomPainter {
  const _VinylPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF282828), Color(0xFF111111), Color(0xFF050505)],
          stops: [.05, .55, 1],
        ).createShader(Offset.zero & size),
    );
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: .16),
    );
    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .75;
    for (double fraction = .10; fraction < .94; fraction += .032) {
      groovePaint.color = Colors.white.withValues(
        alpha: fraction.remainder(.064) < .02 ? .085 : .035,
      );
      canvas.drawCircle(center, radius * fraction, groovePaint);
    }
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * .83),
      -.65,
      .7,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: .08),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TonearmPainter extends CustomPainter {
  const _TonearmPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width * .73, size.height * .10);
    canvas.drawCircle(
      pivot,
      size.width * .16,
      Paint()..color = const Color(0xFFF1F1F1),
    );
    canvas.drawCircle(
      pivot,
      size.width * .07,
      Paint()..color = const Color(0xFFBDBDBD),
    );
    final arm = Path()
      ..moveTo(pivot.dx, pivot.dy + size.width * .04)
      ..quadraticBezierTo(
        size.width * .62,
        size.height * .43,
        size.width * .48,
        size.height * .80,
      );
    canvas.drawPath(
      arm,
      Paint()
        ..color = const Color(0xFFF4F4F4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .075
        ..strokeCap = StrokeCap.round,
    );
    final head = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width * .46, size.height * .84),
        width: size.width * .24,
        height: size.height * .10,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(head, Paint()..color = const Color(0xFFEAEAEA));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .39,
          size.height * .89,
          size.width * .13,
          size.height * .025,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF202020),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
