import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/url_service.dart';

/// Spotify Canvas（官方客户端播放页那段几秒的循环竖屏短视频）。
///
/// 后端 `/spotify/canvas/:trackId` 转 spotify-streamer 的 extended-metadata
/// CANVAZ 扩展，给回 canvaz.scdn.co 上的 mp4 直链（公网、无需鉴权）。
/// 大多数曲目没有 Canvas，「没有」也记进缓存，来回切歌不重复请求。
class SpotifyCanvasService {
  SpotifyCanvasService({ApiClient? apiClient, UrlService? urls})
    : _apiClient = apiClient ?? ApiClient.instance,
      _urls = urls ?? UrlService.instance;

  static final SpotifyCanvasService instance = SpotifyCanvasService();

  static const int _maxEntries = 300;

  final ApiClient _apiClient;
  final UrlService _urls;

  /// trackId → 视频地址；值为 null 表示确认没有 Canvas。
  final Map<String, String?> _cache = {};
  final Map<String, Future<String?>> _pending = {};

  /// 返回可直接播放的视频地址，没有 Canvas 或请求失败时返回 null。
  /// 只放行视频类型：极少数 Canvas 是静图/GIF，那还不如原封面。
  Future<String?> fetchVideoUrl(String trackId) {
    if (_cache.containsKey(trackId)) return Future.value(_cache[trackId]);
    // 回调必须是块体：写成 `=> _pending.remove(...)` 会把被移除的 Future——
    // 也就是 whenComplete 返回的这个 Future 自己——交给 whenComplete 去等，
    // 自己等自己，永远完成不了。
    return _pending[trackId] ??= _fetch(trackId).whenComplete(() {
      _pending.remove(trackId);
    });
  }

  Future<String?> _fetch(String trackId) async {
    try {
      final response = await _apiClient.apiFetch(
        '${_urls.baseUrl}/spotify/canvas/${Uri.encodeComponent(trackId)}',
      );
      if (response.statusCode == 404) {
        _remember(trackId, null);
        return null;
      }
      if (response.statusCode != 200) {
        debugPrint(
          '[SpotifyCanvasService] $trackId HTTP ${response.statusCode}: '
          '${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
        );
        return null;
      }
      final raw = jsonDecode(response.body);
      final data = raw is Map ? raw['data'] : null;
      final url = data is Map ? data['url']?.toString() : null;
      final type = data is Map ? data['type']?.toString() ?? '' : '';
      final playable = url != null && url.isNotEmpty && type.startsWith('VIDEO');
      _remember(trackId, playable ? url : null);
      return playable ? url : null;
    } catch (e) {
      // 网络错误不缓存，下次切回来再试。
      debugPrint('[SpotifyCanvasService] $trackId 获取失败: $e');
      return null;
    }
  }

  void _remember(String trackId, String? url) {
    if (_cache.length >= _maxEntries) _cache.remove(_cache.keys.first);
    _cache[trackId] = url;
  }
}
