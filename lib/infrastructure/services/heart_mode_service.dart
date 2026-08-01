import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';

/// 心动模式服务（对应 Next.js demo/lib/services/heartModeService.ts）。
///
/// 单例。基于网易云「我喜欢的音乐」歌单与 `/playmode/intelligence/list` 接口，
/// 以当前歌曲为种子智能续播，队列耗尽时自动以最后一首歌为种子续拉。
///
/// **职责边界**：原 Next.js 版本直接读取 `useAuthStore`。Flutter 端 service 层不
/// 持有 store，token 由调用方传入。
class HeartModeService {
  HeartModeService._();
  static final HeartModeService instance = HeartModeService._();

  final List<Track> _queue = [];
  int _currentIndex = 0;
  bool _isFetching = false;

  /// 上一首作为种子的歌曲 ID。
  String? _lastSeedId;

  /// 上一次使用的歌单 ID。
  String? _lastPlaylistId;

  /// 缓存的「我喜欢的音乐」歌单 ID。
  String? _cachedFavoritesPlaylistId;

  bool get isLoading => _isFetching;

  Map<String, String> _jsonHeaders(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  Map<String, Object?> _decode(http.Response response) {
    try {
      final payload = jsonDecode(response.body);
      return payload is Map ? Map<String, Object?>.from(payload) : const {};
    } catch (_) {
      return const {};
    }
  }

  bool _ok(http.Response response) =>
      response.statusCode >= 200 && response.statusCode < 300;

  /// 获取用户「我喜欢的音乐」歌单 ID（缓存）。
  Future<String> getFavoritesPlaylistId(String token) async {
    final cached = _cachedFavoritesPlaylistId;
    if (cached != null) return cached;

    if (token.isEmpty) throw StateError('请先登录后再使用心动模式');

    final response = await ApiClient.instance.apiFetch(
      '${UrlService.instance.baseUrl}/netease/user/playlists?limit=1',
      headers: {'Authorization': 'Bearer $token'},
    );
    if (!_ok(response)) throw StateError('获取用户歌单失败');

    final result = _decode(response);
    final data = result['data'];
    final playlists = data is Map ? data['playlists'] : null;
    if (playlists is! List || playlists.isEmpty) {
      throw StateError('未找到可用歌单，请先创建或收藏歌单');
    }

    final first = playlists.first;
    final id = first is Map ? first['id']?.toString() : null;
    if (id == null || id.isEmpty) {
      throw StateError('未找到可用歌单，请先创建或收藏歌单');
    }
    _cachedFavoritesPlaylistId = id;
    return id;
  }

  /// 调用后端心动模式接口，获取智能播放列表并填充内部队列。
  Future<List<Track>> fetchIntelligenceList(
    Object songId,
    String playlistId,
    String token, {
    Object? startMusicId,
  }) async {
    if (token.isEmpty) {
      throw StateError('请先登录后再使用心动模式');
    }

    final params = <String, String>{'id': songId.toString(), 'pid': playlistId};
    if (startMusicId != null) {
      params['sid'] = startMusicId.toString();
    }
    final qs = params.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');

    final response = await ApiClient.instance.apiFetch(
      '${UrlService.instance.baseUrl}/playmode/intelligence/list?$qs',
      headers: _jsonHeaders(token),
    );

    if (!_ok(response)) {
      throw StateError('心动模式请求失败 (HTTP ${response.statusCode})');
    }

    final result = _decode(response);
    if (result['code'] != 200 || result['data'] == null) {
      throw StateError(result['message']?.toString() ?? '获取心动模式列表失败');
    }

    final Object itemsRaw = result['data']!;
    List<Object?> items;
    if (itemsRaw is List) {
      items = itemsRaw;
    } else if (itemsRaw is Map) {
      final inner = itemsRaw['data'];
      items = inner is List ? inner : const [];
    } else {
      items = const [];
    }
    return _convertItemsToTracks(items);
  }

  /// 将心动模式 API 返回的歌曲数据转换为 [Track] 对象。
  List<Track> _convertItemsToTracks(List<Object?> items) {
    final tracks = <Track>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final item = Map<String, Object?>.from(raw);
      final songRaw = item['songInfo'] ?? item['song'] ?? item;
      if (songRaw is! Map) continue;
      final song = Map<String, Object?>.from(songRaw);
      final songId = song['id'];
      if (songId == null) continue;

      final artistsData = song['ar'] ?? song['artists'];
      String artists;
      if (artistsData is List) {
        artists = artistsData
            .map(
              (a) => a is String ? a : (a is Map ? a['name']?.toString() : ''),
            )
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join(' / ');
      } else {
        artists = artistsData?.toString() ?? '';
      }

      final albumRaw = song['al'] ?? song['album'];
      String album;
      String picUrl = song['picUrl']?.toString() ?? '';
      if (albumRaw is String) {
        album = albumRaw;
      } else if (albumRaw is Map) {
        album = albumRaw['name']?.toString() ?? '';
        if (picUrl.isEmpty) {
          picUrl = albumRaw['picUrl']?.toString() ?? '';
        }
      } else {
        album = '';
      }
      // URL 原样使用，不做 http→https 改写（见封面加载约定）：
      // 明文 HTTP 由 network_security_config 放行。

      final dt = song['dt'];
      final durationValue = song['duration'];
      double durationSec = 0;
      if (dt is num) {
        durationSec = dt.toDouble() / 1000;
      } else if (durationValue is num) {
        durationSec = durationValue > 1000
            ? durationValue.toDouble() / 1000
            : durationValue.toDouble();
      }

      tracks.add(
        Track(
          id: songId.toString(),
          name: song['name']?.toString() ?? '',
          artists: artists,
          album: album,
          picUrl: picUrl,
          source: MusicSource.netease,
          duration: Duration(milliseconds: (durationSec * 1000).round()),
        ),
      );
    }
    return tracks;
  }

  /// 开启心动模式：以当前歌曲为种子获取智能播放列表。
  Future<void> start(Object songId, String token, {String? playlistId}) async {
    final pid = await getFavoritesPlaylistId(token);
    _lastSeedId = songId.toString();
    _lastPlaylistId = pid;
    _queue.clear();
    _currentIndex = 0;

    final tracks = await fetchIntelligenceList(
      songId,
      pid,
      token,
      startMusicId: songId,
    );
    // 过滤掉种子歌曲本身（它正在播放）。
    final seedStr = songId.toString();
    _queue
      ..clear()
      ..addAll(tracks.where((t) => t.id != seedStr));
    debugPrint('[HeartMode] 已开启心动模式，种子歌曲: $songId，获取到 ${_queue.length} 首推荐');
  }

  /// 关闭心动模式，清空内部队列。
  void stop() {
    _queue.clear();
    _currentIndex = 0;
    _lastSeedId = null;
    _lastPlaylistId = null;
    _isFetching = false;
  }

  /// 获取下一首心动模式歌曲，队列耗尽时自动以最后一首歌为种子续拉。
  Future<Track?> getNextTrack(String token) async {
    if (_currentIndex < _queue.length) {
      final track = _queue[_currentIndex];
      _currentIndex++;
      return track;
    }

    // 队列耗尽，尝试以最后一首播放的歌为种子续拉。
    final seedId = _lastSeedId;
    if (seedId == null || _isFetching) return null;

    _isFetching = true;
    try {
      final refillPid = _lastPlaylistId ?? await getFavoritesPlaylistId(token);
      final newTracks = await fetchIntelligenceList(
        seedId,
        refillPid,
        token,
        startMusicId: seedId,
      );
      // 过滤掉刚刚播放过的种子歌曲。
      _queue
        ..clear()
        ..addAll(newTracks.where((t) => t.id != seedId));
      _currentIndex = 0;

      if (_queue.isNotEmpty) {
        final track = _queue[_currentIndex];
        _currentIndex++;
        return track;
      }
      return null;
    } catch (e) {
      debugPrint('[HeartMode] 续拉失败: $e');
      return null;
    } finally {
      _isFetching = false;
    }
  }

  /// 更新种子歌曲（每次播放新歌时调用，用于续拉时作为上下文）。
  void updateSeed(Object songId) {
    _lastSeedId = songId.toString();
  }
}
