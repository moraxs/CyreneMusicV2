import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../infrastructure/platform/audio_analyser_service.dart';

/// 6 条频谱竖条音频可视化（对应 Next.js demo/components/player/AudioVisualizer.tsx）。
///
/// 从 [AudioAnalyserService.getBarData] 拉取实时频段能量，白色竖条。
/// 非紧凑模式包裹在圆角胶囊容器中；平滑插值与 Next.js 一致
/// （上升 0.4 / 下降 0.12）。数据源未接入平台 FFT 时全零，竖条静止。
class AudioVisualizer extends StatefulWidget {
  const AudioVisualizer({
    super.key,
    required this.isPlaying,
    this.compact = false,
  });

  final bool isPlaying;
  final bool compact;

  static const int barCount = 6;

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _display = List<double>.filled(AudioVisualizer.barCount, 0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration _) {
    final targets = widget.isPlaying
        ? AudioAnalyserService.instance.getBarData(AudioVisualizer.barCount)
        : const <double>[];
    var changed = false;
    for (var i = 0; i < AudioVisualizer.barCount; i++) {
      final target = i < targets.length ? targets[i] : 0.0;
      final current = _display[i];
      final factor = target > current ? 0.4 : 0.12;
      final next = current + (target - current) * factor;
      if ((next - current).abs() > 0.001) changed = true;
      _display[i] = next;
    }
    if (changed && mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final bars = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < AudioVisualizer.barCount; i++) ...[
          if (i > 0) SizedBox(width: compact ? 3 : 5),
          _bar(_display[i], compact),
        ],
      ],
    );

    if (compact) {
      return bars;
    }

    return Container(
      width: 120,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: bars,
    );
  }

  Widget _bar(double value, bool compact) {
    final maxHeight = compact ? 18.0 : 22.0;
    final minHeight = compact ? 3.0 : 4.0;
    final height = minHeight + value * (maxHeight - minHeight);
    return Container(
      width: compact ? 3 : 4,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8 * (0.6 + value * 0.4)),
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(color: Colors.white.withValues(alpha: 0.4), blurRadius: 6),
        ],
      ),
    );
  }
}
