import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// 品牌光斑背景：三团柔和的彩色光晕，色相由主题 primary 派生。
///
/// 实现刻意**不用高斯模糊**：`RadialGradient` 的柔和边缘是渐变自带的，
/// 而 `ImageFilter.blur` 需要逐帧离屏采样，在中低端安卓上是实打实的掉帧源。
/// 这里整层是静态的，套 `RepaintBoundary` 后只光栅化一次，滚动/转场零成本。
///
/// 登录页与首启引导页共用（两者视觉上是同一条链路，光斑必须完全一致，
/// 否则从引导页进到登录步骤时背景会跳一下）。
class CyreneAuroraBackdrop extends StatelessWidget {
  const CyreneAuroraBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    // 从 primary 出发在 OkLch 里转色相：感知均匀，转到任何角度都不会
    // 突然变暗或发灰（HSV 转色相就会）。三团构成邻近色和谐配色。
    final base = theme.colors.primary.toOkLch();
    // 暗色下光斑要更收敛，否则在深底上糊成一片亮斑。
    final isDark = theme.brightness == Brightness.dark;
    final lightness = isDark ? 62.0 : 78.0;
    final chroma = isDark ? 26.0 : 34.0;
    Color spot(double hueShift, double alpha) =>
        OkLch(lightness, chroma, (base.h + hueShift) % 360).toColor(alpha);

    return RepaintBoundary(
      child: CustomPaint(
        painter: _AuroraPainter(
          // 主色团偏左上（品牌图标后方），另两团做冷暖呼应。
          spots: [
            _AuroraSpot(
              center: const Alignment(-0.75, -0.85),
              radius: 0.95,
              color: spot(0, isDark ? .34 : .30),
            ),
            _AuroraSpot(
              center: const Alignment(0.95, -0.35),
              radius: 0.8,
              color: spot(48, isDark ? .26 : .24),
            ),
            _AuroraSpot(
              center: const Alignment(-0.3, 0.9),
              radius: 1.05,
              color: spot(-42, isDark ? .22 : .20),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个光斑的几何与颜色。[radius] 是相对于画布短边的倍数。
class _AuroraSpot {
  const _AuroraSpot({
    required this.center,
    required this.radius,
    required this.color,
  });

  final Alignment center;
  final double radius;
  final Color color;
}

class _AuroraPainter extends CustomPainter {
  const _AuroraPainter({required this.spots});

  final List<_AuroraSpot> spots;

  @override
  void paint(Canvas canvas, Size size) {
    final shortestSide = size.shortestSide;
    for (final spot in spots) {
      final center = spot.center.withinRect(Offset.zero & size);
      final radius = shortestSide * spot.radius;
      final rect = Rect.fromCircle(center: center, radius: radius);
      // stops 让中心保持一段实色再向外衰减，避免看起来像个硬边圆；
      // 末端 alpha 归零，光斑之间叠加处自然过渡。
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              spot.color,
              spot.color.withValues(alpha: spot.color.a * 0.45),
              spot.color.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter oldDelegate) {
    if (oldDelegate.spots.length != spots.length) return true;
    for (var i = 0; i < spots.length; i++) {
      final a = oldDelegate.spots[i];
      final b = spots[i];
      if (a.color != b.color || a.center != b.center || a.radius != b.radius) {
        return true;
      }
    }
    return false;
  }
}
