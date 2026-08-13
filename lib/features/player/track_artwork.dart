import 'dart:convert';
import 'dart:typed_data';

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

    // 本地音轨的封面是内嵌 `data:image/...;base64,...` URI（由
    // AudioMetadataReader 解析得到），CachedNetworkImage 无法渲染该 scheme，
    // 需改为 base64 解码后经 Image.memory 显示，否则本地歌曲始终是占位图标。
    final dataImage = _decodeDataUri(track.picUrl);
    if (dataImage != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.memory(
          dataImage,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, error) {
            debugPrint('[TrackArtwork] 本地封面解码失败 -> $error');
            return fallback;
          },
        ),
      );
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

  /// 解析 `data:image/<mime>;base64,<payload>` 封面，返回解码后的图片字节。
  ///
  /// 非 data URI 或解析失败返回 null（调用方回退到网络图片加载路径）。
  static Uint8List? _decodeDataUri(String url) {
    if (!url.startsWith('data:')) return null;
    final comma = url.indexOf(',');
    if (comma <= 0) return null;
    final header = url.substring(0, comma);
    final payload = url.substring(comma + 1);
    if (payload.isEmpty) return null;
    if (!header.toLowerCase().contains(';base64')) return null;
    try {
      return base64Decode(payload);
    } catch (_) {
      return null;
    }
  }
}
