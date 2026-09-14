import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../../domain/models/media_url.dart';
import 'for_you_palette.dart';

/// 直接使用推荐接口的封面与现有磁盘缓存，按实际显示尺寸解码。
/// 装饰不额外请求图片，也不为横向滚动中的每张封面启动淡入动画。
class ForYouArtwork extends StatelessWidget {
  const ForYouArtwork({
    super.key,
    required this.url,
    this.size,
    this.cornerRadius = 18,
  });

  final String url;
  final double? size;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    final palette = ForYouPalette.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.peach, palette.rose],
        ),
      ),
      child: Center(
        child: Icon(Icons.music_note_rounded, color: palette.accent, size: 30),
      ),
    );
    Widget artwork = Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: palette.paper,
        shape: MiuixSquircleBorder(cornerRadius: cornerRadius),
      ),
      child: url.isEmpty
          ? fallback
          : LayoutBuilder(
              builder: (context, constraints) => CachedNetworkImage(
                imageUrl: url,
                httpHeaders: imageHeaders(url),
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                memCacheWidth: coverDecodeWidth(
                  constraints.maxWidth.isFinite ? constraints.maxWidth : 220,
                  dpr,
                ),
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
              ),
            ),
    );
    if (size != null) {
      artwork = SizedBox.square(dimension: size, child: artwork);
    }
    return artwork;
  }
}

/// 唱片纹路是一次静态绘制，播放时不启动常驻旋转 ticker。
class ForYouRecord extends StatelessWidget {
  const ForYouRecord({super.key, required this.coverUrl, required this.size});

  final String coverUrl;
  final double size;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned.fill(child: CustomPaint(painter: _RecordPainter())),
          Container(
            width: size * 0.43,
            height: size * 0.43,
            clipBehavior: Clip.antiAlias,
            decoration: const BoxDecoration(shape: BoxShape.circle),
            child: ForYouArtwork(url: coverUrl, cornerRadius: 0),
          ),
          Container(
            width: size * 0.065,
            height: size * 0.065,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF252225),
              border: Border.all(color: const Color(0xFFE7DED1), width: 1.2),
            ),
          ),
        ],
      ),
    ),
  );
}

class _RecordPainter extends CustomPainter {
  const _RecordPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final disc = Paint()
      ..shader = const SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [
          Color(0xFF252326),
          Color(0xFF4D4949),
          Color(0xFF201F22),
          Color(0xFF39363A),
          Color(0xFF252326),
        ],
        stops: [0, 0.22, 0.46, 0.73, 1],
      ).createShader(Offset.zero & size);
    canvas.drawCircle(center, radius, disc);
    final groove = Paint()
      ..color = const Color(0x17FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    for (var i = 0; i < 9; i++) {
      canvas.drawCircle(center, radius * (0.52 + i * 0.048), groove);
    }
    canvas.drawCircle(
      center,
      radius - 0.6,
      Paint()
        ..color = const Color(0x3DFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7,
    );
  }

  @override
  bool shouldRepaint(covariant _RecordPainter oldDelegate) => false;
}

/// 两张唱片照片与一张黑胶形成轻盈的纸张拼贴，封面均来自当天推荐。
class ForYouCoverCollage extends StatelessWidget {
  const ForYouCoverCollage({
    super.key,
    required this.covers,
    required this.width,
  });

  final List<String> covers;
  final double width;

  String _cover(int index) =>
      covers.isEmpty ? '' : covers[index % covers.length];

  @override
  Widget build(BuildContext context) {
    final palette = ForYouPalette.of(context);
    return ExcludeSemantics(
      child: IgnorePointer(
        child: SizedBox(
          width: width,
          height: width * 1.28,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: -3,
                top: width * 0.42,
                child: ForYouRecord(coverUrl: _cover(2), size: width * 0.76),
              ),
              Positioned(
                top: 7,
                right: 3,
                child: Transform.rotate(
                  angle: 0.17,
                  child: _CoverPrint(
                    coverUrl: _cover(1),
                    width: width * 0.66,
                    caption: 'GOOD DAYS',
                  ),
                ),
              ),
              Positioned(
                top: width * 0.15,
                left: 0,
                child: Transform.rotate(
                  angle: -0.11,
                  child: _CoverPrint(
                    coverUrl: _cover(0),
                    width: width * 0.76,
                    caption: 'a little joy',
                  ),
                ),
              ),
              Positioned(
                right: 4,
                bottom: 0,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: palette.rose,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.paper, width: 2.5),
                  ),
                  child: Icon(
                    Icons.favorite_rounded,
                    size: 15,
                    color: palette.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverPrint extends StatelessWidget {
  const _CoverPrint({
    required this.coverUrl,
    required this.width,
    required this.caption,
  });

  final String coverUrl;
  final double width;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final palette = ForYouPalette.of(context);
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(5, 5, 5, 0),
      decoration: BoxDecoration(
        color: palette.paper,
        borderRadius: BorderRadius.circular(11),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 15,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ForYouArtwork(url: coverUrl, cornerRadius: 7),
          ),
          SizedBox(
            height: 20,
            child: Center(
              child: Text(
                caption,
                // 拼贴上的印刷装饰不是正文，不随系统大字体挤出照片边框。
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 8,
                  letterSpacing: 1.2,
                  color: palette.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
