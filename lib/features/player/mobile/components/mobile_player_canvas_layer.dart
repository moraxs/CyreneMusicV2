import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../widgets/video_background_player.dart';

/// 全屏 Spotify Canvas 层：铺满播放器的循环竖屏视频 + 保证文字可读的遮罩。
///
/// 叠在 [MobilePlayerBackground] 之上，所以优先级高于用户的背景设置。
/// 视频没就绪前本层透明（[VideoBackgroundPlayer] 自带淡入），底下的背景照常可见。
///
/// 遮罩随 [lyricsAmount] 在两种形态间插值：
/// - 0（封面模式）：只压顶部状态栏一带和底部信息/控制区，中间留给视频本身；
/// - 1（歌词模式）：整屏压暗，歌词要压在画面上读。
class MobilePlayerCanvasLayer extends StatelessWidget {
  const MobilePlayerCanvasLayer({
    super.key,
    required this.videoUrl,
    required this.paused,
    required this.lyricsAmount,
    required this.ready,
    this.onReady,
  });

  final String videoUrl;
  final bool paused;
  final double lyricsAmount;

  /// 视频已出画。遮罩跟着它淡入，免得视频还在加载时就把底下的背景压暗。
  final bool ready;
  final VoidCallback? onReady;

  @override
  Widget build(BuildContext context) {
    final l = lyricsAmount.clamp(0.0, 1.0);
    // 歌词模式整屏底色；封面模式下为 0，只剩上下两条渐变。
    final dim = lerpDouble(0, 0.55, l)!;
    final top = lerpDouble(0.45, 0.55, l)!;
    final bottom = lerpDouble(0.85, 0.7, l)!;

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: VideoBackgroundPlayer(
            // 换视频整个重建，onReady 才对得上是哪一路视频。
            key: ValueKey(videoUrl),
            videoPath: videoUrl,
            paused: paused,
            onReady: onReady,
          ),
        ),
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: ready ? 1 : 0,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.18, 0.45, 1.0],
                  colors: [
                    Colors.black.withValues(alpha: top),
                    Colors.black.withValues(alpha: dim),
                    Colors.black.withValues(alpha: dim),
                    Colors.black.withValues(alpha: bottom),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
