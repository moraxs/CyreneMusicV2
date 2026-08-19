import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// SuperCyrene「纹理玻璃」（Textured / Fluted Glass）背景。
///
/// 视觉灵感源自小米 HyperOS / iOS 锁屏个性化中的长虹/瓦楞纹理玻璃质感：
/// 1. 采用 GPU 网格形变（[Canvas.drawVertices] + [ui.ImageShader]），静态模拟柱面透镜折射与波浪错位；
/// 2. 保持高清原图画质，水平与垂直方向的光学折射使画面边缘产生物理级别的弯折与拉丝纹理；
/// 3. 每个玻璃柱条左侧带有晶莹细腻的透光高光线与轻微棱镜色散，右侧带有凹槽阴影；
/// 4. 纯静态渲染，支持通过参数自定义条纹粗细、折射强度、光泽亮度、凹槽深度与色散强弱。
class SuperCyreneTexturedGlassBackground extends StatefulWidget {
  const SuperCyreneTexturedGlassBackground({
    super.key,
    required this.imageProvider,
    this.isPlaying = false,
    this.fluteWidth = 16.0,
    this.refractionStrength = 1.0,
    this.lightingIntensity = 1.0,
    this.grooveDepth = 1.0,
    this.dispersion = 1.0,
  });

  final ImageProvider? imageProvider;
  final bool isPlaying;
  final double fluteWidth;
  final double refractionStrength;
  final double lightingIntensity;
  final double grooveDepth;
  final double dispersion;

  @override
  State<SuperCyreneTexturedGlassBackground> createState() =>
      _SuperCyreneTexturedGlassBackgroundState();
}

class _SuperCyreneTexturedGlassBackgroundState
    extends State<SuperCyreneTexturedGlassBackground> {
  ImageProvider? _loadedProvider;
  ui.Image? _processedImage;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadAlbum();
  }

  @override
  void didUpdateWidget(
      covariant SuperCyreneTexturedGlassBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider) _loadAlbum();
  }

  Future<void> _loadAlbum() async {
    final provider = widget.imageProvider;
    _loadedProvider = provider;
    final generation = ++_loadGeneration;
    if (provider == null) {
      final previous = _processedImage;
      if (mounted) setState(() => _processedImage = null);
      previous?.dispose();
      return;
    }

    ImageStream? stream;
    ImageStreamListener? listener;
    try {
      final completer = Completer<ui.Image>();
      stream = provider.resolve(const ImageConfiguration());
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) completer.complete(info.image.clone());
        },
        onError: (Object error, StackTrace? stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
      );
      stream.addListener(listener);
      final source = await completer.future;
      stream.removeListener(listener);
      listener = null;

      if (!mounted ||
          generation != _loadGeneration ||
          provider != _loadedProvider) {
        source.dispose();
        return;
      }

      final previous = _processedImage;
      setState(() => _processedImage = source);
      if (previous != null && !identical(previous, source)) {
        Future<void>.delayed(
          const Duration(milliseconds: 600),
          previous.dispose,
        );
      }
    } catch (error) {
      debugPrint('SuperCyrene Textured Glass background failed to load: $error');
    } finally {
      if (listener != null) stream?.removeListener(listener);
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _processedImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 基础底衬
        const ColoredBox(color: Color(0xFF13111A)),
        // 纹理玻璃主体静态折射网格
        CustomPaint(
          painter: _TexturedGlassPainter(
            image: _processedImage,
            fluteWidth: widget.fluteWidth,
            refractionStrength: widget.refractionStrength,
            lightingIntensity: widget.lightingIntensity,
            grooveDepth: widget.grooveDepth,
            dispersion: widget.dispersion,
          ),
          child: const SizedBox.expand(),
        ),
        // 轻微防遮挡晕影（保护顶部状态与底部控制条）
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x4D000000),
                Colors.transparent,
                Colors.transparent,
                Color(0x66000000),
              ],
              stops: [0.0, 0.18, 0.78, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

/// 纹理玻璃柱面静态光学折射画笔（基于 GPU 三角形网格形变）
class _TexturedGlassPainter extends CustomPainter {
  const _TexturedGlassPainter({
    required this.image,
    this.fluteWidth = 16.0,
    this.refractionStrength = 1.0,
    this.lightingIntensity = 1.0,
    this.grooveDepth = 1.0,
    this.dispersion = 1.0,
  });

  final ui.Image? image;
  final double fluteWidth;
  final double refractionStrength;
  final double lightingIntensity;
  final double grooveDepth;
  final double dispersion;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return;

    final img = image;
    if (img == null) {
      final fallbackRect = Offset.zero & size;
      final fallbackPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2C2448),
            Color(0xFF1B1832),
            Color(0xFF0F1124),
          ],
        ).createShader(fallbackRect);
      canvas.drawRect(fallbackRect, fallbackPaint);
      return;
    }

    final imgW = img.width.toDouble();
    final imgH = img.height.toDouble();

    // 1. 计算 BoxFit.cover 裁切区域
    final screenAspect = size.width / size.height;
    final imgAspect = imgW / imgH;

    double cropW, cropH, cropX, cropY;
    if (imgAspect > screenAspect) {
      cropH = imgH;
      cropW = imgH * screenAspect;
      cropX = (imgW - cropW) / 2;
      cropY = 0;
    } else {
      cropW = imgW;
      cropH = imgW / screenAspect;
      cropX = 0;
      cropY = (imgH - cropH) / 2;
    }

    // 2. 瓦楞玻璃网格构建
    final targetFluteWidth = fluteWidth.clamp(8.0, 32.0);
    final fluteCount = (size.width / targetFluteWidth).round().clamp(12, 200);
    final actualFluteWidth = size.width / fluteCount;

    const subColsPerFlute = 4;
    const rows = 28;

    final totalCols = fluteCount * subColsPerFlute;
    final positions = <Offset>[];
    final texCoords = <Offset>[];

    for (var r = 0; r <= rows; r++) {
      final vNorm = r / rows;
      final y = vNorm * size.height;

      for (var f = 0; f < fluteCount; f++) {
        // 相邻柱条交错波浪起伏位移
        final colWave1 = math.sin(f * 0.48) * 0.055;
        final colWave2 = math.cos(f * 1.15) * 0.035;
        final fluteYDisplacement = (colWave1 + colWave2) * refractionStrength;

        for (var s = 0; s < subColsPerFlute; s++) {
          final subNorm = s / subColsPerFlute;
          final x = (f + subNorm) * actualFluteWidth;

          // 柱面圆弧角度：-π/2 ~ +π/2
          final angle = (subNorm - 0.5) * math.pi;

          // 边缘强折射与水平透镜偏转
          final lensRefractX =
              math.sin(angle) * (actualFluteWidth * 0.42) * refractionStrength;

          // 边缘纵向强拉伸与折射
          final edgeStretch = (1.0 - math.cos(angle)) * 0.12 * refractionStrength;
          final dynamicWave =
              math.sin(vNorm * math.pi * 4 + f * 0.6) * 0.015 * refractionStrength;

          final baseU = ((f + 0.5) / fluteCount) +
              (subNorm - 0.5) * (1.0 / fluteCount) * 0.65;
          final uDisplaced =
              (baseU + (lensRefractX / size.width)).clamp(0.0, 1.0);

          final vDisplaced = (vNorm +
                  fluteYDisplacement * (1.0 - (vNorm - 0.5).abs() * 0.6) +
                  edgeStretch +
                  dynamicWave)
              .clamp(0.0, 1.0);

          positions.add(Offset(x, y));
          texCoords.add(Offset(
            cropX + uDisplaced * cropW,
            cropY + vDisplaced * cropH,
          ));
        }
      }

      // 最后一列
      final x = size.width;
      final uDisplaced = 1.0;
      final vDisplaced = vNorm;
      positions.add(Offset(x, y));
      texCoords.add(Offset(
        cropX + uDisplaced * cropW,
        cropY + vDisplaced * cropH,
      ));
    }

    // 生成三角形索引
    final indices = <int>[];
    final stride = totalCols + 1;

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < totalCols; c++) {
        final i0 = r * stride + c;
        final i1 = i0 + 1;
        final i2 = (r + 1) * stride + c;
        final i3 = i2 + 1;

        indices.add(i0);
        indices.add(i1);
        indices.add(i2);

        indices.add(i1);
        indices.add(i3);
        indices.add(i2);
      }
    }

    final matrix = Float64List.fromList(Matrix4.identity().storage);
    final shader = ui.ImageShader(
      img,
      TileMode.clamp,
      TileMode.clamp,
      matrix,
    );

    final meshPaint = Paint()
      ..shader = shader
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true;

    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: texCoords,
      indices: indices,
    );

    // 绘制真实物理折射变形后的静态曲面网格
    canvas.drawVertices(vertices, BlendMode.srcOver, meshPaint);

    // 3. 绘制玻璃柱面 3D 棱镜光效图层（透光高光条、凹槽阴影、色散边缘、柱面漫射）
    final highlightPaint = Paint()..style = PaintingStyle.fill;
    final shadowPaint = Paint()..style = PaintingStyle.fill;
    final sheenPaint = Paint()..style = PaintingStyle.fill;
    final rainbowPaint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < fluteCount; i++) {
      final x = i * actualFluteWidth;
      final fluteRect = Rect.fromLTWH(x, 0, actualFluteWidth, size.height);

      // A. 柱面立体反光弧面
      sheenPaint.shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color.fromRGBO(255, 255, 255, (0.18 * lightingIntensity).clamp(0.0, 1.0)),
          Color.fromRGBO(255, 255, 255, (0.04 * lightingIntensity).clamp(0.0, 1.0)),
          Color.fromRGBO(0, 0, 0, (0.08 * grooveDepth).clamp(0.0, 1.0)),
          Color.fromRGBO(0, 0, 0, (0.32 * grooveDepth).clamp(0.0, 1.0)),
        ],
        stops: const [0.0, 0.32, 0.78, 1.0],
      ).createShader(fluteRect);
      canvas.drawRect(fluteRect, sheenPaint);

      // B. 左侧棱镜高光与青蓝轻微色散边缘（Chromatic Dispersion Rim）
      if (dispersion > 0.01) {
        rainbowPaint.color = Color.fromRGBO(
            80, 220, 255, (0.20 * dispersion).clamp(0.0, 1.0));
        canvas.drawRect(Rect.fromLTWH(x, 0, 0.8, size.height), rainbowPaint);
      }

      if (lightingIntensity > 0.01) {
        final highlightRect = Rect.fromLTWH(x + 0.6, 0, 1.2, size.height);
        highlightPaint.color = Color.fromRGBO(
            255, 255, 255, (0.42 * lightingIntensity).clamp(0.0, 1.0));
        canvas.drawRect(highlightRect, highlightPaint);
      }

      // C. 右侧凹槽深邃阴影线（Groove Shadow）
      if (grooveDepth > 0.01) {
        final shadowRect =
            Rect.fromLTWH(x + actualFluteWidth - 1.4, 0, 1.4, size.height);
        shadowPaint.color =
            Color.fromRGBO(0, 0, 0, (0.48 * grooveDepth).clamp(0.0, 1.0));
        canvas.drawRect(shadowRect, shadowPaint);
      }

      // D. 右边缘紫红微色散
      if (dispersion > 0.01) {
        rainbowPaint.color = Color.fromRGBO(
            230, 90, 255, (0.12 * dispersion).clamp(0.0, 1.0));
        canvas.drawRect(
            Rect.fromLTWH(x + actualFluteWidth - 0.6, 0, 0.6, size.height),
            rainbowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TexturedGlassPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.fluteWidth != fluteWidth ||
        oldDelegate.refractionStrength != refractionStrength ||
        oldDelegate.lightingIntensity != lightingIntensity ||
        oldDelegate.grooveDepth != grooveDepth ||
        oldDelegate.dispersion != dispersion;
  }
}
