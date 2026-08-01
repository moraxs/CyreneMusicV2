
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../compat/dynamic_bg_processor.dart';

class FlowingLightBackground extends StatefulWidget {
  final ImageProvider? imageProvider;
  final Widget? child;
  final bool useDesktopProcessing;
  final Duration duration;

  const FlowingLightBackground({
    super.key,
    this.imageProvider,
    this.child,
    this.useDesktopProcessing = false,
    this.duration = const Duration(seconds: 5), // Speed up to 5s
    // Kotlin uses 3400ms, which is quite fast for a background. Maybe 10s is better for music player.
  });

  @override
  State<FlowingLightBackground> createState() => _FlowingLightBackgroundState();
}

class _FlowingLightBackgroundState extends State<FlowingLightBackground> with SingleTickerProviderStateMixin {
  ui.Image? _processedImage;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  late Animation<Alignment> _alignmentAnimation;
  late Animation<double> _rotateAnimation;
  
  // Cache to prevent re-processing same image
  ImageProvider? _lastProvider;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5), // Faster animation for fluid feel
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _startRandomAnimation();
      }
    });

    _startRandomAnimation();
    _loadAndProcessImage();
  }

  @override
  void didUpdateWidget(FlowingLightBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageProvider != _lastProvider) {
      _loadAndProcessImage();
    }
  }

  void _startRandomAnimation() {
    final random = math.Random();
    
    // Random scale (Increased zoom to prevent white borders from blur edges)
    // Using 2.0 to 2.5 scale to ensure we only see the opaque center of the processed image
    final beginScale = _controller.value > 0 ? _scaleAnimation.value : 2.0 + random.nextDouble() * 0.5;
    final endScale = 2.0 + random.nextDouble() * 0.5;
    
    // Random alignment (Restricted range)
    // We must limit alignment deviation to avoid exposing the blurred/transparent edges of the image.
    // Confining to +/- 0.25 ensures we stay near the opaque center.
    final double range = 0.25;
    final beginAlign = _controller.value > 0 ? _alignmentAnimation.value : Alignment(
      (random.nextDouble() * 2 - 1) * range, 
      (random.nextDouble() * 2 - 1) * range
    );
    final endAlign = Alignment(
      (random.nextDouble() * 2 - 1) * range, 
      (random.nextDouble() * 2 - 1) * range
    );

    // Random rotation (small angle to add twist)
    final beginRotate = _controller.value > 0 ? _rotateAnimation.value : (random.nextDouble() - 0.5) * 0.15;
    final endRotate = (random.nextDouble() - 0.5) * 0.15;

    _scaleAnimation = Tween<double>(begin: beginScale, end: endScale).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut)
    );
    
    _alignmentAnimation = AlignmentTween(begin: beginAlign, end: endAlign).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut)
    );

    _rotateAnimation = Tween<double>(begin: beginRotate, end: endRotate).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut)
    );

    _controller.forward(from: 0);
  }

  Future<void> _loadAndProcessImage() async {
    _lastProvider = widget.imageProvider;
    if (widget.imageProvider == null) {
      if (mounted) setState(() => _processedImage = null);
      return;
    }

    try {
      final stream = widget.imageProvider!.resolve(const ImageConfiguration());
      final completer = Completer<ui.Image>();
      
      final listener = ImageStreamListener((info, _) {
        completer.complete(info.image);
      });
      
      stream.addListener(listener);
      final rawImage = await completer.future;
      stream.removeListener(listener);

      // Process in a microtask or isolate ideally, but here we do async gaps
      // Since DynamicBgProcessor uses GPU/Canvas, it must be on main thread (mostly).
      // If it's too slow, we might see a frame drop. The operations are relatively cheap on GPU though.
      // But readPixels (calculateBrightness) is slow.
      
      
      final processed = widget.useDesktopProcessing 
          ? await DynamicBgProcessor.processImageDesktop(rawImage)
          : await DynamicBgProcessor.processImage(rawImage);

      if (mounted && widget.imageProvider == _lastProvider) {
        setState(() {
          _processedImage = processed;
        });
      }
    } catch (e) {
      debugPrint('Error processing background image: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background Image
        if (_processedImage != null)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.rotate(
                angle: _rotateAnimation.value,
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  alignment: _alignmentAnimation.value,
                  child: RawImage(
                    image: _processedImage!,
                    fit: BoxFit.cover,
                  ),
                ),
              );
            },
          )
        else
          Container(color: Colors.grey[900]), // Placeholder - use opaque grey

        // Overlay Child
        if (widget.child != null) widget.child!,
      ],
    );
  }
}
