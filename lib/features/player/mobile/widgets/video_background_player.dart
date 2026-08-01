import 'package:flutter/material.dart';

/// 原版视频背景播放器的占位实现：新版暂未移植视频背景/动态封面，
/// 保持构造签名一致，渲染纯黑底避免布局差异。
class VideoBackgroundPlayer extends StatelessWidget {
  const VideoBackgroundPlayer({
    super.key,
    required this.videoPath,
    this.blurAmount = 0.0,
    this.opacity = 1.0,
  });

  final String videoPath;
  final double blurAmount;
  final double opacity;

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}
