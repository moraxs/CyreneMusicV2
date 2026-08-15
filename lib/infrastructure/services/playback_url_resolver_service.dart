import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/audio_quality.dart';
import '../../domain/models/audio_source_config.dart';
import '../../domain/models/lyric_data.dart';
import '../../domain/models/lx_music_config.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';
import 'audio_source_service.dart';
import 'lx_music_runtime_service.dart';

/// 音源解析失败（对应 Next.js AudioSourceError）。
class AudioSourceError implements Exception {
  AudioSourceError(this.message, {this.status, this.rawText, this.rawJson});

  final String message;
  final int? status;
  final String? rawText;
  final Object? rawJson;

  @override
  String toString() => message;
}

/// 单次音源解析结果。
class ResolvedPlayback {
  const ResolvedPlayback({required this.url, this.fallbackUrl, this.lyrics});

  final String url;
  final String? fallbackUrl;
  final LyricData? lyrics;
}

abstract interface class PlaybackSourceClient {
  Future<ResolvedPlayback> resolveUrlFromSource(
    Track track,
    AudioSourceConfig configSource,
    AudioQuality quality,
  );

  Future<LyricData?> fetchLyrics(Track track);
}

/// 播放地址解析服务（对应 Next.js demo/lib/services/playerService.ts 的
/// `resolveUrlFromSource` + `fetchAndApplyLyrics` 的 HTTP 部分）。
///
/// 仅承载**数据层**：根据 [AudioSourceConfig] 与 [Track] 请求对应音源后端，
/// 解析出真实播放地址与（可能的）歌词。不涉及 Howler / 播放器状态 / UI。
///
/// 多音源回退、并发请求过期（requestId）控制交由上层 controller / store。
class PlaybackUrlResolverService implements PlaybackSourceClient {
  PlaybackUrlResolverService({ApiClient? apiClient, UrlService? urls})
    : _apiClient = apiClient ?? ApiClient.instance,
      _urls = urls ?? UrlService.instance;

  final ApiClient _apiClient;
  final UrlService _urls;

  static const List<MusicSource> _omniParseGetSources = [
    MusicSource.qq,
    MusicSource.kuwo,
    MusicSource.qishui,
  ];

  static const Map<MusicSource, String> _lxSourceMap = {
    MusicSource.netease: 'wy',
    MusicSource.qq: 'tx',
    MusicSource.kugou: 'kg',
    MusicSource.kuwo: 'kw',
  };

  Map<String, Object?> _decode(http.Response response) {
    try {
      final payload = jsonDecode(response.body);
      return payload is Map ? Map<String, Object?>.from(payload) : const {};
    } catch (_) {
      return const {};
    }
  }

  bool _ok(http.Response r) => r.statusCode >= 200 && r.statusCode < 300;

  String _snippet(String text) =>
      text.length > 80 ? text.substring(0, 80) : text;

  String _stripTrailingSlash(String url) =>
      url.replaceFirst(RegExp(r'/+$'), '');

  /// 对单个音源尝试解析播放 URL，成功返回 [ResolvedPlayback]，失败抛 [AudioSourceError]。
  @override
  Future<ResolvedPlayback> resolveUrlFromSource(
    Track track,
    AudioSourceConfig configSource,
    AudioQuality quality,
  ) async {
    var url = AudioSourceService.instance.buildPlaybackUrl(
      configSource,
      track.source,
      track.id,
      quality,
    );
    if (url.isEmpty) {
      throw AudioSourceError('无法为 ${track.source.wireName} 构建播放 URL');
    }

    // ─── LxMusic 音源 ───
    if (configSource.type == AudioSourceType.lxMusic) {
      final loaded = await LxMusicRuntimeService.instance.loadScript(
        _toScriptInfo(configSource),
      );
      if (!loaded) {
        throw AudioSourceError('Android 当前未启用 LxMusic 脚本运行时');
      }
      final lxSource = _lxSourceMap[track.source] ?? track.source.wireName;
      final realUrl = await LxMusicRuntimeService.instance.getMusicUrl(
        lxSource,
        track.id,
        AudioSourceService.instance.getLxQuality(quality),
      );
      if (realUrl.isEmpty) throw AudioSourceError('LxMusic Runtime 返回空 URL');
      return ResolvedPlayback(url: realUrl);
    }

    // ─── OmniParse 网易云 (POST /song) ───
    if (configSource.type == AudioSourceType.omniParse &&
        track.source == MusicSource.netease) {
      final apiUrl = '${_stripTrailingSlash(configSource.url)}/song';
      // 原 TS neteaseQualityMap 对 standard/exhigh/lossless/hires 映射为自身，
      // 并兼容 128k/320k/flac/flac24bit 及 jyeffect/sky/jymaster 等扩展音质。
      // Dart 侧 quality 为枚举，直接使用 wireName。
      final mappedQuality = quality.wireName;
      final response = await _apiClient.apiFetch(
        apiUrl,
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-API-Key': configSource.apiKey,
        },
        body: {
          'ids': track.id.toString(),
          'url': '',
          'level': mappedQuality,
          'type': 'json',
        },
      );
      if (!_ok(response)) {
        throw AudioSourceError(
          '网易云音源响应异常 (HTTP ${response.statusCode}): '
          '${_snippet(response.body)}',
          status: response.statusCode,
          rawText: response.body,
        );
      }
      final result = _decode(response);
      if (result['status'] == 200 && result['url'] != null) {
        LyricData? lyricData;
        if (result['lyric'] != null || result['yrc'] != null) {
          lyricData = LyricData(
            lyric: result['lyric']?.toString() ?? '',
            tlyric: result['tlyric']?.toString() ?? '',
            yrc: result['yrc']?.toString() ?? '',
            ytlrc: result['ytlrc']?.toString() ?? '',
          );
        }
        return ResolvedPlayback(
          url: result['url'].toString(),
          lyrics: lyricData,
        );
      }
      throw AudioSourceError(
        '网易云解析失败: ${result['msg'] ?? 'Unknown error'}',
        rawJson: result,
      );
    }

    // ─── OmniParse 酷狗（权限解析 + 音质降级链）───
    if (configSource.type == AudioSourceType.omniParse &&
        track.source == MusicSource.kugou) {
      return _resolveKugouUrl(track, configSource, quality);
    }

    // ─── OmniParse GET (QQ / 酷我 / 汽水) ───
    if (configSource.type == AudioSourceType.omniParse &&
        _omniParseGetSources.contains(track.source)) {
      final response = await _apiClient.apiFetch(
        url,
        headers: {'X-API-Key': configSource.apiKey},
      );
      if (!_ok(response)) {
        throw AudioSourceError(
          '音源服务器解析失败 (HTTP ${response.statusCode}): '
          '${_snippet(response.body)}',
          status: response.statusCode,
          rawText: response.body,
        );
      }
      final result = _decode(response);
      if (result['status'] == 200) {
        String extractedUrl = '';
        String? fallbackUrl;
        LyricData? lyricData;

        if (track.source == MusicSource.qq) {
          final musicUrls = (result['music_urls'] is Map)
              ? Map<String, Object?>.from(result['music_urls'] as Map)
              : const <String, Object?>{};
          extractedUrl =
              _qqUrl(musicUrls, 'flac') ??
              _qqUrl(musicUrls, '320') ??
              _qqUrl(musicUrls, '128') ??
              '';
          final backup =
              _qqUrl(musicUrls, '320') ?? _qqUrl(musicUrls, '128') ?? '';
          if (backup.isNotEmpty && backup != extractedUrl) {
            fallbackUrl = backup;
          }
        } else {
          final songData = result['song'] is Map
              ? Map<String, Object?>.from(result['song'] as Map)
              : result;
          extractedUrl = songData['url']?.toString() ?? '';
          if (track.source == MusicSource.qishui && songData['lyric'] != null) {
            lyricData = LyricData(
              lyric: songData['lyric']?.toString() ?? '',
              tlyric: songData['tlyric']?.toString() ?? '',
            );
          }
        }

        if (extractedUrl.isEmpty) {
          throw AudioSourceError(
            '${track.source.wireName} 解析成功但未返回播放链接',
            rawJson: result,
          );
        }
        // 汽水音乐：Next.js 通过 audioProxyService（Tauri Rust 代理）绕过 CDN 防盗链。
        // Flutter 侧 audioProxyService 尚未移植，此处保留原始 URL，
        // 后续若出现防盗链播放失败，需在平台层实现代理。
        return ResolvedPlayback(
          url: extractedUrl,
          fallbackUrl: fallbackUrl,
          lyrics: lyricData,
        );
      }
      throw AudioSourceError(
        '${track.source.wireName} 解析失败: ${result['msg'] ?? 'Unknown error'}',
        rawJson: result,
      );
    }

    // ─── OmniParse Spotify ───
    if (configSource.type == AudioSourceType.omniParse &&
        track.source == MusicSource.spotify) {
      final response = await _apiClient.apiFetch(
        url,
        headers: {'X-API-Key': configSource.apiKey},
      );
      if (!_ok(response)) {
        throw AudioSourceError(
          'Spotify 音源响应异常 (HTTP ${response.statusCode}): '
          '${_snippet(response.body)}',
          status: response.statusCode,
          rawText: response.body,
        );
      }
      final result = _decode(response);
      final data = result['data'] is Map
          ? Map<String, Object?>.from(result['data'] as Map)
          : null;
      if (result['status'] == 200 && data != null && data['url'] != null) {
        // data.url 是相对路径，需拼接后端 baseUrl
        final baseUrl = _stripTrailingSlash(configSource.url);
        return ResolvedPlayback(url: '$baseUrl${data['url']}');
      }
      throw AudioSourceError(
        'Spotify 解析失败: ${result['msg'] ?? data?['msg'] ?? 'Unknown error'}',
        rawJson: result,
      );
    }

    // ─── OmniParse Apple Music ───
    // /apple/stream 直接返回音频流（audio/mpeg），非 JSON；URL 原样使用。
    if (configSource.type == AudioSourceType.omniParse &&
        track.source == MusicSource.apple) {
      return ResolvedPlayback(url: url);
    }

    // 其余 OmniParse 类型直接使用 buildPlaybackUrl 构建的 URL。
    return ResolvedPlayback(url: url);
  }

  /// 酷狗播放地址解析：先解析各音质独立 hash，再按降级链取链
  /// （对齐开源项目 OnlineMusicQueue.js 的 privilege + fallback 流程）。
  Future<ResolvedPlayback> _resolveKugouUrl(
    Track track,
    AudioSourceConfig configSource,
    AudioQuality quality,
  ) async {
    final base = _stripTrailingSlash(configSource.url);
    final idStr = track.id.toString();
    final hash = idStr.contains(':') ? idStr.split(':').first : idStr;
    if (hash.isEmpty) {
      throw AudioSourceError('酷狗歌曲缺少 hash');
    }

    // 与设置-音源设置中的音质结合，只请求用户指定的对应音质档位
    final targetQuality = switch (quality.effectiveFor(MusicSource.kugou)) {
      AudioQuality.standard => '128',
      AudioQuality.exHigh => '320',
      AudioQuality.lossless => 'flac',
      AudioQuality.hiRes => 'high',
      _ => '128',
    };

    return await _fetchKugouSong(base, configSource, hash, targetQuality);
  }

  Future<Map<String, String>> _fetchKugouPrivilege(
    String base,
    AudioSourceConfig configSource,
    String hash,
  ) async {
    try {
      final resp = await _apiClient.apiFetch(
        '$base/kugou/privilege?hash=${Uri.encodeQueryComponent(hash)}',
        headers: {'X-API-Key': configSource.apiKey},
      );
      if (!_ok(resp)) return {};
      final result = _decode(resp);
      if (result['status'] != 200) return {};
      final items = result['data'];
      if (items is! List) return {};
      final map = <String, String>{};
      for (final item in items) {
        if (item is! Map) continue;
        final m = Map<Object?, Object?>.from(item);
        final related = m['relate_goods'];
        final variants = <Map<Object?, Object?>>[m];
        if (related is List) {
          for (final r in related) {
            if (r is Map) variants.add(Map<Object?, Object?>.from(r));
          }
        }
        for (final variant in variants) {
          final q = variant['quality']?.toString();
          final h = variant['hash']?.toString();
          final level = variant['level'];
          if (q == null || h == null || h.isEmpty) continue;
          if (level == 0 || level == '0') continue;
          map.putIfAbsent(q, () => h);
        }
      }
      return map;
    } catch (e) {
      debugPrint('[PlaybackUrlResolverService] kugou privilege failed: $e');
      return {};
    }
  }

  Future<ResolvedPlayback> _fetchKugouSong(
    String base,
    AudioSourceConfig configSource,
    String hash,
    String quality,
  ) async {
    final resp = await _apiClient.apiFetch(
      '$base/kugou/song?hash=${Uri.encodeQueryComponent(hash)}&quality=$quality',
      headers: {'X-API-Key': configSource.apiKey},
    );
    final result = _decode(resp);
    if (!_ok(resp) || result['status'] != 200) {
      throw AudioSourceError(
        '酷狗解析失败: ${result['msg'] ?? 'HTTP ${resp.statusCode}'}',
        status: resp.statusCode,
        rawText: resp.body,
        rawJson: result,
      );
    }
    final songData = result['song'] is Map
        ? Map<String, Object?>.from(result['song'] as Map)
        : result;
    final extractedUrl = songData['url']?.toString() ?? '';
    if (extractedUrl.isEmpty) {
      throw AudioSourceError('酷狗解析成功但未返回播放链接', rawJson: result);
    }
    return ResolvedPlayback(url: extractedUrl);
  }

  /// 酷狗音质降级链（对齐开源项目 QUALITY_LEVELS 的 getFallbackChain）。
  List<String> _kugouQualityChain(AudioQuality quality) {
    const levels = [
      '128',
      '320',
      'flac',
      'high',
      'viper_atmos',
      'viper_clear',
      'viper_tape',
    ];
    final q = quality.effectiveFor(MusicSource.kugou);
    final target = switch (q) {
      AudioQuality.standard => '128',
      AudioQuality.exHigh => '320',
      AudioQuality.lossless => 'flac',
      AudioQuality.hiRes => 'flac',
      _ => '128',
    };
    final idx = levels.indexOf(target);
    final available = idx < 0 ? const ['128'] : levels.sublist(0, idx + 1);
    return available.reversed.toList();
  }

  String? _qqUrl(Map<String, Object?> musicUrls, String key) {
    final entry = musicUrls[key];
    if (entry is Map) {
      final u = entry['url']?.toString();
      if (u != null && u.isNotEmpty) return u;
    }
    return null;
  }

  LxScriptInfo _toScriptInfo(AudioSourceConfig config) => LxScriptInfo(
    name: config.name,
    version: config.version,
    author: config.author,
    description: config.description,
    homepage: '',
    script: config.scriptContent,
    supportedSources: const [],
    supportedQualities: const [],
    platformQualities: const {},
  );

  /// 异步加载歌词（对应 playerService.fetchAndApplyLyrics 的 HTTP 部分）。
  ///
  /// 仅发起请求并解析，不更新播放器状态（由上层 controller 应用到当前曲目）。
  @override
  Future<LyricData?> fetchLyrics(Track track) async {
    try {
      final base = _urls.baseUrl;
      switch (track.source) {
        case MusicSource.netease:
          final r = await _apiClient.apiFetch(
            '$base/lyrics/netease?id=${Uri.encodeQueryComponent(track.id)}',
          );
          return _parseStdLyric(_decode(r));
        case MusicSource.qq:
          final r = await _apiClient.apiFetch(
            '$base/lyrics/qq?id=${Uri.encodeQueryComponent(track.id)}',
          );
          final data = _unwrap(_decode(r));
          if (data == null) return null;
          // QQ 用 qrc / qrcTrans 字段，映射到 yrc / ytlrc
          return LyricData(
            lyric: data['lyric']?.toString() ?? '',
            tlyric: data['tlyric']?.toString() ?? '',
            yrc: data['qrc']?.toString() ?? '',
            ytlrc: data['qrcTrans']?.toString() ?? '',
          );
        case MusicSource.kugou:
          final hash = track.id.split(':').first;
          if (hash.isEmpty) return null;
          final r = await _apiClient.apiFetch(
            '$base/lyrics/kugou?hash=${Uri.encodeQueryComponent(hash)}',
          );
          final data = _unwrap(_decode(r));
          if (data == null || data['lyric'] == null) return null;
          return LyricData(
            lyric: data['lyric']?.toString() ?? '',
            tlyric: data['tlyric']?.toString() ?? '',
          );
        case MusicSource.apple:
          final r = await _apiClient.apiFetch(
            '$base/apple/lyric?id=${Uri.encodeQueryComponent(track.id)}',
          );
          final raw = _decode(r);
          if (raw['lyric'] == null) return null;
          return LyricData(
            lyric: raw['lyric']?.toString() ?? '',
            tlyric: raw['tlyric']?.toString() ?? '',
          );
        case MusicSource.spotify:
          final r = await _apiClient.apiFetch(
            '$base/spotify/lyrics/${Uri.encodeQueryComponent(track.id)}',
          );
          final raw = _decode(r);
          final data = raw['data'] is Map
              ? Map<String, Object?>.from(raw['data'] as Map)
              : null;
          if (data == null || data['lyric'] == null) return null;
          return LyricData(
            lyric: data['lyric']?.toString() ?? '',
            tlyric: data['tlyric']?.toString() ?? '',
          );
        case MusicSource.kuwo:
        case MusicSource.qishui:
        case MusicSource.local:
          return null;
      }
    } catch (e) {
      debugPrint('[PlaybackUrlResolverService] fetchLyrics failed: $e');
      return null;
    }
  }

  /// 取 `data` 字段（若存在），否则返回原始 map。
  Map<String, Object?>? _unwrap(Map<String, Object?> raw) {
    final data = raw['data'];
    if (data is Map) return Map<String, Object?>.from(data);
    return raw;
  }

  LyricData? _parseStdLyric(Map<String, Object?> raw) {
    final data = _unwrap(raw);
    if (data == null) return null;
    if (data['lyric'] == null && data['yrc'] == null) return null;
    return LyricData(
      lyric: data['lyric']?.toString() ?? '',
      tlyric: data['tlyric']?.toString() ?? '',
      yrc: data['yrc']?.toString() ?? '',
      ytlrc: data['ytlrc']?.toString() ?? '',
    );
  }
}
