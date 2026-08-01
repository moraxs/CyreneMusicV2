import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../domain/models/media_url.dart';
import '../../domain/models/track.dart';

class TrackArtwork extends StatelessWidget {
  const TrackArtwork({
    super.key,
    required this.track,
    this.size = 56,
    this.borderRadius = 12,
  });

  final Track track;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: size * .45,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
    if (track.picUrl.isEmpty) {
      return SizedBox(width: size, height: size, child: fallback);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CachedNetworkImage(
        imageUrl: track.picUrl,
        httpHeaders: imageHeaders(track.picUrl),
        width: size,
        height: size,
        fit: BoxFit.cover,
        // 按显示尺寸降采样解码:封面原图常达 ~1000²,直接解码全尺寸会在
        // 列表滚动时逐帧上传大位图拖垮帧率。屏幕像素不变,仅省掉多余分辨率。
        memCacheWidth: coverDecodeWidth(
          size,
          MediaQuery.devicePixelRatioOf(context),
        ),
        errorWidget: (_, _, error) {
          debugPrint('[TrackArtwork] 加载失败 ${track.picUrl} -> $error');
          return fallback;
        },
      ),
    );
  }
}
