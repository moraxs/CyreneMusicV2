import 'dart:math';

import 'package:flutter/material.dart';

import '../../infrastructure/services/discovery_service.dart';
import '../player/mobile/compat/color_extraction_service.dart';

/// 桌面首页推荐卡的动态视觉：从对应歌单里随机抽一首歌的封面 + 该封面的主题色。
///
/// [gradient] 为 null 表示取色失败（下载/解码出错），此时调用方应回退到卡片
/// 自带的设计配色，但封面本身依然可用。
class RecommendArtwork {
  const RecommendArtwork({required this.coverUrl, required this.gradient});

  final String coverUrl;
  final List<Color>? gradient;
}

/// 推荐卡视觉解析器。
///
/// **刻意不做结果缓存**：每次调用都重新随机，这样首页「刷新」就能换一张封面。
/// 重复取色的开销由 [ColorExtractionService] 自身的 URL 级缓存吸收，图片字节
/// 由 CachedNetworkImage 的磁盘缓存吸收；页面态负责在一次会话内保持稳定
/// （见 `desktop_home_page.dart` 的 `_artwork`）。
abstract final class RecommendArtworkResolver {
  static final _random = Random();

  /// 歌单内曲目采样上限。只为随机抽一张封面，不必拉全量。
  static const _sampleLimit = 60;

  /// 拉取歌单详情，从其曲目封面里随机取一张。
  static Future<RecommendArtwork?> fromPlaylist(int playlistId) async {
    if (playlistId == 0) return null;
    final detail = await DiscoveryService.instance.getPlaylistDetail(
      playlistId,
      limit: _sampleLimit,
    );
    final tracks = detail?.tracks;
    if (tracks == null) return null;
    return fromCovers([for (final track in tracks) track.picUrl]);
  }

  /// 从调用方已持有的封面列表里随机取一张（如每日推荐，曲目已在本地）。
  static Future<RecommendArtwork?> fromCovers(List<String> covers) async {
    final unique = <String>{
      for (final url in covers)
        if (url.isNotEmpty) url,
    }.toList(growable: false);
    if (unique.isEmpty) return null;
    final coverUrl = unique[_random.nextInt(unique.length)];
    // sampleSize 取 24：卡片只需要一个主色调，缩到 24² 已足够且更快。
    final extracted = await ColorExtractionService().extractColorsFromUrl(
      coverUrl,
      sampleSize: 24,
    );
    final seed = extracted?.themeColor;
    return RecommendArtwork(
      coverUrl: coverUrl,
      gradient: seed == null ? null : recommendGradientFromSeed(seed),
    );
  }
}

/// 把封面提取色收进「能承托白色文字」的区间，并派生出更亮的第二个端点，
/// 形成与原设计稿同构的两段式渐变（深 → 浅）。
List<Color> recommendGradientFromSeed(Color seed) {
  final hsl = HSLColor.fromColor(seed);
  // 近乎无彩的封面（黑白照、纯灰底）不强行提饱和：HSLColor 对无彩色给出的
  // hue 恒为 0，加饱和会把它染成红色。这类封面只压亮度，保留冷灰。
  final saturation = hsl.saturation < 0.14
      ? hsl.saturation
      : hsl.saturation.clamp(0.30, 0.72);
  final lightness = hsl.lightness.clamp(0.33, 0.50);
  final base = hsl.withSaturation(saturation).withLightness(lightness);
  return [
    base.toColor(),
    base.withLightness((lightness + 0.11).clamp(0.0, 0.62)).toColor(),
  ];
}
