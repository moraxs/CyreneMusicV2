import 'dart:math' as math;
import 'package:flutter/material.dart';

class WavySplitProgressBar extends StatefulWidget {
  final double value; // 0.0 to 1.0
  final ValueChanged<double>? onChanged;
  final bool isPlaying;
  final Color? activeColor;
  final Color? inactiveColor;
  final double height;
  final double waveAmplitude;
  final double waveFrequency;
  final List<Map<String, int>>? chorusTimes;
  final double? durationMs;

  const WavySplitProgressBar({
    super.key,
    required this.value,
    this.onChanged,
    this.isPlaying = false,
    this.activeColor,
    this.inactiveColor,
    this.height = 40.0,
    this.waveAmplitude = 4.0,
    this.waveFrequency = 0.12, // 增加频率让波浪更多
    this.chorusTimes,
    this.durationMs,
  });

  @override
  State<WavySplitProgressBar> createState() => _WavySplitProgressBarState();
}

class _WavySplitProgressBarState extends State<WavySplitProgressBar>
    with TickerProviderStateMixin {
  late AnimationController _phaseController;
  late AnimationController _amplitudeController;

  @override
  void initState() {
    super.initState();
    _phaseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000), // 加快流动速度
    )..repeat();

    _amplitudeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: widget.isPlaying ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(WavySplitProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _amplitudeController.forward();
      } else {
        _amplitudeController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _phaseController.dispose();
    _amplitudeController.dispose();
    super.dispose();
  }

  void _handleDragUpdate(DragUpdateDetails details, double width) {
    if (widget.onChanged != null) {
      final newValue = (details.localPosition.dx / width).clamp(0.0, 1.0);
      widget.onChanged!(newValue);
    }
  }

  void _handleTapDown(TapDownDetails details, double width) {
    if (widget.onChanged != null) {
      final newValue = (details.localPosition.dx / width).clamp(0.0, 1.0);
      widget.onChanged!(newValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.activeColor ?? Theme.of(context).colorScheme.primary;
    final inactiveColor = widget.inactiveColor ?? Theme.of(context).colorScheme.surfaceContainerHighest;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onHorizontalDragUpdate: (d) => _handleDragUpdate(d, width),
          onTapDown: (d) => _handleTapDown(d, width),
          child: SizedBox(
            width: width,
            height: widget.height,
            child: AnimatedBuilder(
              animation: Listenable.merge([_phaseController, _amplitudeController]),
              builder: (context, child) {
                return CustomPaint(
                  painter: _WavySplitPainter(
                    value: widget.value,
                    phase: _phaseController.value * 2 * math.pi,
                    amplitudeFactor: _amplitudeController.value,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    waveAmplitude: widget.waveAmplitude,
                    waveFrequency: widget.waveFrequency,
                    chorusTimes: widget.chorusTimes,
                    durationMs: widget.durationMs,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _WavySplitPainter extends CustomPainter {
  final double value;
  final double phase;
  final double amplitudeFactor;
  final Color activeColor;
  final Color inactiveColor;
  final double waveAmplitude;
  final double waveFrequency;
  final List<Map<String, int>>? chorusTimes;
  final double? durationMs;

  _WavySplitPainter({
    required this.value,
    required this.phase,
    required this.amplitudeFactor,
    required this.activeColor,
    required this.inactiveColor,
    required this.waveAmplitude,
    required this.waveFrequency,
    this.chorusTimes,
    this.durationMs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final progressX = size.width * value;
    final trackHeight = 6.0;
    final thumbWidth = 4.0;
    final thumbHeight = 16.0;
    final gap = 6.0; // 分割间隙

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = trackHeight;

    // 0. 绘制副歌高亮区间 (在所有轨道底部)
    if (chorusTimes != null && chorusTimes!.isNotEmpty && durationMs != null && durationMs! > 0) {
      final Paint chorusPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;
        
      for (final chorus in chorusTimes!) {
        final startTimeMs = chorus['startTime']?.toDouble() ?? 0.0;
        final endTimeMs = chorus['endTime']?.toDouble() ?? 0.0;
        if (startTimeMs >= endTimeMs) continue;

        final startFraction = (startTimeMs / durationMs!).clamp(0.0, 1.0);
        final endFraction = (endTimeMs / durationMs!).clamp(0.0, 1.0);
        
        final startX = startFraction * size.width;
        final endX = endFraction * size.width;
        
        final chorusRect = RRect.fromRectAndRadius(
          Rect.fromLTRB(startX, centerY - trackHeight / 2, endX, centerY + trackHeight / 2),
          const Radius.circular(3.0),
        );

        canvas.drawRRect(chorusRect, chorusPaint);
      }
    }

    // 1. 绘制已播放部分 (左侧)
    if (progressX > 0) {
      canvas.save();
      // 裁剪区域，防止波浪由于 strokeWidth 或计算误差溢出到滑块右侧
      final clipRect = Rect.fromLTWH(0, centerY - waveAmplitude - 10, progressX - thumbWidth / 2, (waveAmplitude + 10) * 2);
      canvas.clipRect(clipRect);

      final playedPath = Path();
      const step = 1.0; 
      final endX = progressX; 
      
      final startY = centerY + math.sin((0 - progressX) * waveFrequency + phase) * waveAmplitude * amplitudeFactor;
      playedPath.moveTo(0, startY);
      
      for (double x = step; x <= endX; x += step) {
        final y = centerY + math.sin((x - progressX) * waveFrequency + phase) * waveAmplitude * amplitudeFactor;
        playedPath.lineTo(x, y);
      }
      
      paint.color = activeColor;
      paint.style = PaintingStyle.stroke;
      canvas.drawPath(playedPath, paint);
      canvas.restore();
    }

    // 2. 绘制分割线 (Thumb)
    final thumbPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;
    
    final thumbRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(progressX, centerY), width: thumbWidth, height: thumbHeight),
      const Radius.circular(2),
    );
    canvas.drawRRect(thumbRect, thumbPaint);

    // 绘制未播放部分 (右侧) - 保持 gap
    if (progressX < size.width - gap) {
      final startX = progressX + gap;
      paint.color = inactiveColor;
      paint.style = PaintingStyle.stroke;
      canvas.drawLine(Offset(startX, centerY), Offset(size.width, centerY), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavySplitPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.phase != phase ||
        oldDelegate.amplitudeFactor != amplitudeFactor ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.chorusTimes != chorusTimes ||
        oldDelegate.durationMs != durationMs;
  }
}
