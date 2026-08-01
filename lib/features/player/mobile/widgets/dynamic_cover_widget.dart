import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../compat/player_service.dart';
import '../compat/image_utils.dart';
import 'video_background_player.dart';

/// 动态封面组件
/// 如果当前歌曲有动态视频封面，自动播放视频并在加载完成后淡入替换图片封面
class DynamicCoverWidget extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final double width;
  final double height;
  final BorderRadiusGeometry? borderRadius;

  const DynamicCoverWidget({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  State<DynamicCoverWidget> createState() => _DynamicCoverWidgetState();
}

class _DynamicCoverWidgetState extends State<DynamicCoverWidget> {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      clipBehavior: widget.borderRadius != null ? Clip.hardEdge : Clip.none,
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius ?? BorderRadius.zero,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 始终渲染底层静态封面图以防视频加载慢或失败
          _buildStaticCover(),
          // 监听并层叠动态视频封面
          _buildDynamicCover(),
        ],
      ),
    );
  }

  Widget _buildStaticCover() {
    final player = PlayerService();
    final coverProvider = player.currentCoverImageProvider;

    return widget.imageUrl.isNotEmpty
        ? RepaintBoundary(
            child: Image(
              key: ValueKey('static_cover_${widget.imageUrl}'),
              image: coverProvider ?? CachedNetworkImageProvider(widget.imageUrl, headers: getImageHeaders(widget.imageUrl)),
              fit: widget.fit,
              width: widget.width,
              height: widget.height,
              gaplessPlayback: true, // 避免切换时的闪烁
            ),
          )
        : Container(
            color: Colors.grey[900],
            child: Icon(Icons.music_note, color: Colors.white54, size: widget.width * 0.4),
          );
  }

  Widget _buildDynamicCover() {
    return ValueListenableBuilder<String?>(
      valueListenable: PlayerService().dynamicCoverUrlNotifier,
      builder: (context, videoUrl, child) {
        final hasVideo = videoUrl != null && videoUrl.isNotEmpty;
        
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          switchInCurve: Curves.easeIn,
          switchOutCurve: Curves.easeOut,
          child: hasVideo
              ? RepaintBoundary(
                  key: ValueKey('dynamic_cover_$videoUrl'),
                  child: VideoBackgroundPlayer(
                    videoPath: videoUrl,
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('no_video')),
        );
      },
    );
  }
}
