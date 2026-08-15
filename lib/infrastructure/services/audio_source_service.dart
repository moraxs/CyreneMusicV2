import '../../domain/models/audio_quality.dart';
import '../../domain/models/audio_source_config.dart';
import '../../domain/models/music_source.dart';

/// 音源服务（对应 Next.js demo/lib/services/audioSourceService.ts）。
///
/// 单例。**纯 URL 拼接逻辑**，不依赖平台 API / 网络。
/// 根据 [AudioSourceConfig.type] 与 [MusicSource] 构造各后端的播放 URL。
class AudioSourceService {
  AudioSourceService._();
  static final AudioSourceService instance = AudioSourceService._();

  /// 洛雪音源来源代码映射
  final Map<MusicSource, String> lxSourceCodeMap = {
    MusicSource.netease: 'wy',
    MusicSource.qq: 'tx',
    MusicSource.kugou: 'kg',
    MusicSource.kuwo: 'kw',
  };

  /// 各音源类型默认支持的搜索平台
  final Map<AudioSourceType, List<String>> defaultSupportedPlatforms = {
    AudioSourceType.omniParse: [
      'netease',
      'qq',
      'kugou',
      'kuwo',
      'apple',
      'spotify',
    ],
    AudioSourceType.lxMusic: const [], // 动态从脚本获取
  };

  /// 将 [AudioQuality] 映射为 LxMusic 音质字符串。
  ///
  /// 网易云专属音质（higher/dolby/jyeffect/sky/jymaster）在 LxMusic 侧没有
  /// 对应档位，统一回落到极高音质 320k。
  String getLxQuality(AudioQuality quality) {
    switch (quality) {
      case AudioQuality.standard:
        return '128k';
      case AudioQuality.exHigh:
        return '320k';
      case AudioQuality.lossless:
        return 'flac';
      case AudioQuality.hiRes:
        return 'flac24bit';
      case AudioQuality.higher:
      case AudioQuality.dolby:
      case AudioQuality.jyeffect:
      case AudioQuality.sky:
      case AudioQuality.jymaster:
        return '320k';
    }
  }

  /// 将 [AudioQuality] 映射为酷狗 /v5/url 的音质字符串。
  /// 网易云专属音质先回落；hiRes 在酷狗侧无 24bit 档位，回落 flac。
  String _kugouQuality(AudioQuality quality) {
    final q = quality.effectiveFor(MusicSource.kugou);
    return switch (q) {
      AudioQuality.standard => '128',
      AudioQuality.exHigh => '320',
      AudioQuality.lossless => 'flac',
      AudioQuality.hiRes => 'flac',
      _ => '128',
    };
  }

  String _cleanUrl(String url) {
    if (url.isEmpty) return '';
    var result = url.trim();
    result = result.replaceAll(RegExp(r'''^["']|["']$'''), '');
    result = result.replaceAll(RegExp(r'/$'), '');
    return result;
  }

  /// 构建播放 URL。
  ///
  /// [songId] 对应 TS 的 `string | number`，Flutter 侧用 [Object] 表达，
  /// 内部通过 [toString] 拼接。
  String buildPlaybackUrl(
    AudioSourceConfig config,
    MusicSource source,
    Object songId,
    AudioQuality quality,
  ) {
    final baseUrl = _cleanUrl(config.url);
    if (baseUrl.isEmpty) return '';

    switch (config.type) {
      case AudioSourceType.omniParse:
        return _buildOmniParseUrl(baseUrl, source, songId, quality);
      case AudioSourceType.lxMusic:
        return _buildLxMusicUrl(baseUrl, config, source, songId, quality);
    }
  }

  String _buildOmniParseUrl(
    String baseUrl,
    MusicSource source,
    Object songId,
    AudioQuality quality,
  ) {
    // 映射源到 API 路径
    final sourcePathMap = <MusicSource, String>{
      MusicSource.netease: 'song',
      MusicSource.qq: 'qq/song',
      MusicSource.kugou: 'kugou/song',
      MusicSource.kuwo: 'kuwo/song',
      MusicSource.apple: 'apple/stream',
      MusicSource.spotify: 'spotify/stream',
      MusicSource.qishui: 'qishui',
    };

    final path = sourcePathMap[source];
    if (path == null) return '';

    final base = '$baseUrl/$path';
    final qualityStr = quality.wireName;

    switch (source) {
      case MusicSource.netease:
        return '$base?id=$songId&quality=$qualityStr&type=json';
      case MusicSource.qq:
        // 后端期望 ids 或 url 参数
        return '$base?ids=$songId&quality=$qualityStr';
      case MusicSource.kugou:
        // 搜索返回的 id 格式为 "hash:albumId"；对齐开源项目，取链仅用 hash，
        // 不传 album_audio_id（后端默认 0）。
        final kugouQuality = _kugouQuality(quality);
        final idStr = songId.toString();
        final hash = idStr.contains(':') ? idStr.split(':').first : idStr;
        return '$base?hash=$hash&quality=$kugouQuality';
      case MusicSource.kuwo:
        // 后端期望 mid 参数
        return '$base?mid=$songId&quality=$qualityStr';
      case MusicSource.apple:
        // Apple Music 使用 Widevine 解密流，参数为 salableAdamId
        return '$base?salableAdamId=$songId';
      case MusicSource.qishui:
        // 汽水音乐通过 url 参数传入完整链接
        return '$base?url=https://music.douyin.com/track/$songId';
      case MusicSource.spotify:
      case MusicSource.local:
        return '$base?id=$songId&quality=$qualityStr';
    }
  }

  String _buildLxMusicUrl(
    String baseUrl,
    AudioSourceConfig config,
    MusicSource source,
    Object songId,
    AudioQuality quality,
  ) {
    final sourceCode = lxSourceCodeMap[source];
    if (sourceCode == null) return '';

    final lxQuality = getLxQuality(quality);

    if (config.urlPathTemplate.isNotEmpty) {
      final path = config.urlPathTemplate
          .replaceAll('{source}', sourceCode)
          .replaceAll('{songId}', songId.toString())
          .replaceAll('{quality}', lxQuality);
      return '$baseUrl$path';
    }

    return '$baseUrl/url/$sourceCode/$songId/$lxQuality';
  }
}
