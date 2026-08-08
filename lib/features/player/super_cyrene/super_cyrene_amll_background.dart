import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A Flutter adaptation of AMLL's Pixi background.
///
/// AMLL renders four differently sized copies of the album texture, rotates
/// alternate layers in opposite directions, and moves the smaller layers on
/// slow orbits. The source image is heavily blurred and color-corrected once,
/// so animation frames only update GPU transforms.
class SuperCyreneAmllBackground extends StatefulWidget {
  const SuperCyreneAmllBackground({
    super.key,
    required this.imageProvider,
    required this.isPlaying,
  });

  final ImageProvider? imageProvider;
  final bool isPlaying;

  @override
  State<SuperCyreneAmllBackground> createState() =>
      _SuperCyreneAmllBackgroundState();
}

class _SuperCyreneAmllBackgroundState extends State<SuperCyreneAmllBackground>
    with SingleTickerProviderStateMixin {
  static const _flowDuration = Duration(seconds: 2800);

  late final AnimationController _flow;
  ImageProvider? _loadedProvider;
  ui.Image? _processedImage;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _flow = AnimationController(
      vsync: this,
      // The former 28-second loop used fractional turn multipliers. Its end
      // state therefore did not equal its start state and all layers snapped
      // back at once. A 100x master period preserves every original velocity
      // while converting those multipliers to whole cycles.
      duration: _flowDuration,
    );
    _syncPlayback();
    _loadAlbum();
  }

  @override
  void didUpdateWidget(covariant SuperCyreneAmllBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider) _loadAlbum();
    if (oldWidget.isPlaying != widget.isPlaying) _syncPlayback();
  }

  void _syncPlayback() {
    if (widget.isPlaying) {
      _flow.repeat();
    } else {
      _flow.stop();
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    // Hot Reload preserves the existing controller and its old RepeatSimulation.
    // When the seamless loop period changed from 28s to 2800s, that left the
    // new 100x multipliers running on the old period and appeared 100x faster.
    _flow.stop();
    _flow.duration = _flowDuration;
    _syncPlayback();
  }

  /// Produces the soft album texture used by AMLL without mesh warping.
  ///
  /// The previous implementation reused DynamicBgProcessor, whose triangle
  /// mesh becomes visible when its output is rotated in several large layers.
  /// Rendering an overscanned square before blurring keeps every pixel smooth
  /// and prevents transparent or angular edges around the texture.
  Future<ui.Image> _prepareAlbum(ui.Image source) async {
    const side = 360;
    final sourceSide = math.min(source.width, source.height).toDouble();
    final sourceRect = Rect.fromLTWH(
      (source.width - sourceSide) / 2,
      (source.height - sourceSide) / 2,
      sourceSide,
      sourceSide,
    );
    final squareRecorder = ui.PictureRecorder();
    final squareCanvas = Canvas(squareRecorder);
    squareCanvas.drawImageRect(
      source,
      sourceRect,
      const Rect.fromLTWH(0, 0, 360, 360),
      Paint()..filterQuality = FilterQuality.high,
    );
    final square = await squareRecorder.endRecording().toImage(side, side);

    final resultRecorder = ui.PictureRecorder();
    final resultCanvas = Canvas(resultRecorder);
    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: 28,
        sigmaY: 28,
        tileMode: TileMode.clamp,
      )
      // AMLL raises saturation, then darkens the texture before compositing.
      ..colorFilter = const ColorFilter.matrix(<double>[
        .917,
        -.115,
        -.022,
        0,
        0,
        -.058,
        .861,
        -.022,
        0,
        0,
        -.058,
        -.115,
        .953,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]);
    const overscan = 42.0;
    resultCanvas.drawImageRect(
      square,
      const Rect.fromLTWH(0, 0, 360, 360),
      const Rect.fromLTWH(
        -overscan,
        -overscan,
        side + overscan * 2,
        side + overscan * 2,
      ),
      paint,
    );
    final result = await resultRecorder.endRecording().toImage(side, side);
    square.dispose();
    return result;
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
          if (!completer.isCompleted) completer.complete(info.image);
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

      final processed = await _prepareAlbum(source);
      if (!mounted ||
          generation != _loadGeneration ||
          provider != _loadedProvider) {
        processed.dispose();
        return;
      }

      final previous = _processedImage;
      setState(() => _processedImage = processed);
      // Keep the outgoing texture alive for AnimatedSwitcher's cross-fade.
      if (previous != null && !identical(previous, processed)) {
        Future<void>.delayed(
          const Duration(milliseconds: 900),
          previous.dispose,
        );
      }
    } catch (error) {
      debugPrint('SuperCyrene AMLL background failed to load: $error');
    } finally {
      if (listener != null) stream?.removeListener(listener);
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _flow.dispose();
    _processedImage?.dispose();
    super.dispose();
  }

  Widget _texture(
    ui.Image image,
    double size, {
    double opacity = 1,
    bool featherEdges = false,
  }) {
    final texture = SizedBox.square(
      dimension: size,
      child: RawImage(
        image: image,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      ),
    );
    return Opacity(
      opacity: opacity,
      child: featherEdges
          ? ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const RadialGradient(
                center: Alignment.center,
                radius: .72,
                colors: [
                  Color(0xFFFFFFFF),
                  Color(0xE6FFFFFF),
                  Color(0x70FFFFFF),
                  Color(0x00FFFFFF),
                ],
                stops: [0, .34, .68, 1],
              ).createShader(bounds),
              child: texture,
            )
          : texture,
    );
  }

  Widget _animatedTexture({
    required ui.Image image,
    required double size,
    required Offset center,
    required double angle,
    double opacity = 1,
    bool featherEdges = false,
  }) => Positioned(
    left: center.dx - size / 2,
    top: center.dy - size / 2,
    child: Transform.rotate(
      angle: angle,
      child: _texture(
        image,
        size,
        opacity: opacity,
        featherEdges: featherEdges,
      ),
    ),
  );

  Widget _buildLayers(ui.Image image) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final maxSide = math.max(size.width, size.height);
      // This remains outside every viewport corner throughout rotation.
      final coveringSide = math.sqrt(
        size.width * size.width + size.height * size.height,
      );
      final center = size.center(Offset.zero);
      return AnimatedBuilder(
        animation: _flow,
        builder: (context, _) {
          // Every multiplier below is an integer. Position, rotation and their
          // first derivatives are consequently identical at both loop edges.
          final phase = _flow.value * math.pi * 2;
          final orbitX = size.width * .17;
          final orbitY = size.height * .14;
          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _animatedTexture(
                  image: image,
                  size: coveringSide * 1.08,
                  center: center,
                  angle: phase * 12,
                ),
                _animatedTexture(
                  image: image,
                  size: maxSide * .92,
                  center: Offset(size.width * .4, size.height * .4),
                  angle: -phase * 25 + 1.3,
                  opacity: .62,
                  featherEdges: true,
                ),
                _animatedTexture(
                  image: image,
                  size: maxSide * .58,
                  center:
                      center +
                      Offset(
                        math.cos(phase * 75) * orbitX,
                        math.sin(phase * 68) * orbitY,
                      ),
                  angle: phase * 38 + 2.1,
                  opacity: .52,
                  featherEdges: true,
                ),
                _animatedTexture(
                  image: image,
                  size: maxSide * .3,
                  center:
                      center +
                      Offset(
                        math.cos(phase * 108 + 2.4) * orbitX * .72,
                        math.sin(phase * 94 + .8) * orbitY * .78,
                      ),
                  angle: -phase * 52 + .5,
                  opacity: .42,
                  featherEdges: true,
                ),
              ],
            ),
          );
        },
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final image = _processedImage;
    return RepaintBoundary(
      child: ColoredBox(
        color: const Color(0xFF17151D),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 800),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: image == null
              ? const SizedBox.expand(key: ValueKey('empty-amll-background'))
              : SizedBox.expand(
                  key: ValueKey(image),
                  // AMLL blurs the fully composited scene, not only each album
                  // texture. Overscan first so the large kernel never exposes
                  // transparent pixels along the viewport edges.
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: 48,
                      sigmaY: 48,
                      tileMode: TileMode.clamp,
                    ),
                    child: Transform.scale(
                      scale: 1.12,
                      child: _buildLayers(image),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
