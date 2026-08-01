import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/playlist.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';

/// 待加入歌单的曲目输入（对应 addTracksToPlaylist 的 tracks 元素）。
typedef PlaylistTrackInput = ({
  Object trackId,
  String name,
  String artists,
  String album,
  String picUrl,
  String source,
});

/// checkTrackInPlaylists 的返回结构。
class CheckTrackResult {
  const CheckTrackResult({
    required this.inPlaylist,
    required this.playlistIds,
    required this.playlistNames,
  });

  final bool inPlaylist;
  final List<int> playlistIds;
  final List<String> playlistNames;

  factory CheckTrackResult.fromJson(Map<String, Object?> json) =>
      CheckTrackResult(
        inPlaylist: json['inPlaylist'] == true,
        playlistIds:
            (json['playlistIds'] as List?)
                ?.map(
                  (e) =>
                      e is num ? e.toInt() : (int.tryParse(e.toString()) ?? 0),
                )
                .toList() ??
            const [],
        playlistNames:
            (json['playlistNames'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}

/// 用户歌单服务（对应 Next.js demo/lib/services/playlistService.ts）。
///
/// 单例。所有方法需鉴权，调用方传入 [token]。
class PlaylistService {
  PlaylistService._();
  static final PlaylistService instance = PlaylistService._();

  Map<String, String> _headers(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  Map<String, Object?> _decode(http.Response response) {
    try {
      final payload = jsonDecode(response.body);
      return payload is Map ? Map<String, Object?>.from(payload) : const {};
    } catch (e) {
      debugPrint('[PlaylistService] decode failed: $e');
      return const {};
    }
  }

  bool _ok(http.Response response) =>
      response.statusCode >= 200 && response.statusCode < 300;

  /// 获取当前用户的全部歌单。
  Future<List<Playlist>> getPlaylists(String token) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/playlists',
        headers: _headers(token),
      );
      if (_ok(response)) {
        final result = _decode(response);
        final list = result['playlists'];
        if (list is List) {
          return list
              .whereType<Map>()
              .map((e) => Playlist.fromJson(Map<String, Object?>.from(e)))
              .toList();
        }
      }
      return const [];
    } catch (e) {
      debugPrint('[PlaylistService] getPlaylists failed: $e');
      return const [];
    }
  }

  /// 创建歌单。可携带来源信息用于第三方歌单导入。
  Future<Playlist?> createPlaylist(
    String token,
    String name, {
    String? source,
    String? sourcePlaylistId,
  }) async {
    try {
      final body = <String, Object?>{'name': name};
      if (source != null) body['source'] = source;
      if (sourcePlaylistId != null) body['sourcePlaylistId'] = sourcePlaylistId;
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/playlists',
        method: 'POST',
        headers: _headers(token),
        body: jsonEncode(body),
      );
      if (_ok(response)) {
        final result = _decode(response);
        final playlist = result['playlist'];
        if (playlist is Map) {
          return Playlist.fromJson(Map<String, Object?>.from(playlist));
        }
      }
      return null;
    } catch (e) {
      debugPrint('[PlaylistService] createPlaylist failed: $e');
      return null;
    }
  }

  /// 删除歌单。
  Future<bool> deletePlaylist(String token, Object playlistId) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/playlists/$playlistId/delete',
        method: 'POST',
        headers: _headers(token),
      );
      return _ok(response);
    } catch (e) {
      debugPrint('[PlaylistService] deletePlaylist failed: $e');
      return false;
    }
  }

  /// 获取歌单内全部曲目。
  Future<List<PlaylistTrack>> getPlaylistTracks(
    String token,
    Object playlistId,
  ) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/playlists/$playlistId/tracks',
        headers: _headers(token),
      );
      if (_ok(response)) {
        final result = _decode(response);
        final list = result['tracks'];
        if (list is List) {
          return list.whereType<Map>().map((t) {
            final m = Map<String, Object?>.from(t);
            return PlaylistTrack.fromJson({
              'trackId': m['trackId'] ?? m['track_id'] ?? m['id'],
              'name': m['name'] ?? m['track_name'],
              'artists': m['artists'],
              'album': m['album'],
              'picUrl': m['picUrl'] ?? m['pic_url'],
              'source': m['source'],
              'addedAt': m['addedAt'] ?? m['added_at'],
            });
          }).toList();
        }
      }
      return const [];
    } catch (e) {
      debugPrint('[PlaylistService] getPlaylistTracks failed: $e');
      return const [];
    }
  }

  /// 批量添加曲目到歌单。
  Future<bool> addTracksToPlaylist(
    String token,
    Object playlistId,
    List<PlaylistTrackInput> tracks,
  ) async {
    try {
      final body = jsonEncode({
        'tracks': tracks
            .map(
              (t) => {
                'trackId': t.trackId.toString(),
                'name': t.name,
                'artists': t.artists,
                'album': t.album,
                'picUrl': t.picUrl,
                'source': t.source,
              },
            )
            .toList(),
      });
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/playlists/$playlistId/tracks/batch',
        method: 'POST',
        headers: _headers(token),
        body: body,
      );
      return _ok(response);
    } catch (e) {
      debugPrint('[PlaylistService] addTracksToPlaylist failed: $e');
      return false;
    }
  }

  /// 添加单首曲目到歌单。
  Future<bool> addTrackToPlaylist(
    String token,
    Object playlistId,
    Object trackId,
    String name,
    String artists,
    String album,
    String picUrl,
    String source,
  ) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/playlists/$playlistId/tracks',
        method: 'POST',
        headers: _headers(token),
        body: jsonEncode({
          'trackId': trackId.toString(),
          'name': name,
          'artists': artists,
          'album': album,
          'picUrl': picUrl,
          'source': source,
        }),
      );
      return _ok(response);
    } catch (e) {
      debugPrint('[PlaylistService] addTrackToPlaylist failed: $e');
      return false;
    }
  }

  /// 从歌单移除曲目。
  Future<bool> removeTrackFromPlaylist(
    String token,
    Object playlistId,
    Object trackId,
    String source,
  ) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/playlists/$playlistId/tracks/remove',
        method: 'POST',
        headers: _headers(token),
        body: jsonEncode({'trackId': trackId.toString(), 'source': source}),
      );
      return _ok(response);
    } catch (e) {
      debugPrint('[PlaylistService] removeTrackFromPlaylist failed: $e');
      return false;
    }
  }

  /// 同步第三方歌单：重新拉取远端歌单数据，增量更新本地歌单。
  /// 绑定歌单的外部来源（如网易云歌单），之后可反复 [syncPlaylist] 增量同步。
  Future<bool> bindImportConfig(
    String token,
    Object playlistId, {
    required String source,
    required String sourcePlaylistId,
  }) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/playlists/$playlistId/import-config',
        method: 'PUT',
        headers: _headers(token),
        body: jsonEncode({
          'source': source,
          'sourcePlaylistId': sourcePlaylistId,
        }),
      );
      return _ok(response);
    } catch (e) {
      debugPrint('[PlaylistService] bindImportConfig failed: $e');
      return false;
    }
  }

  Future<PlaylistSyncResult?> syncPlaylist(
    String token,
    Object playlistId,
  ) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/playlists/$playlistId/sync',
        method: 'POST',
        headers: _headers(token),
      );
      if (_ok(response)) {
        final result = _decode(response);
        return PlaylistSyncResult(
          insertedCount: (result['insertedCount'] as num?)?.toInt() ?? 0,
          newTracks:
              (result['newTracks'] as List?)
                  ?.whereType<Map>()
                  .map(
                    (e) => PlaylistTrack.fromJson(Map<String, Object?>.from(e)),
                  )
                  .toList() ??
              const [],
          message: result['message']?.toString() ?? '',
        );
      }
      return null;
    } catch (e) {
      debugPrint('[PlaylistService] syncPlaylist failed: $e');
      return null;
    }
  }

  /// 检查歌曲是否在用户的任何歌单中。
  Future<CheckTrackResult> checkTrackInPlaylists(
    String token,
    Object trackId,
    String source,
  ) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/playlists/check-track?trackId=${trackId.toString()}&source=$source',
        headers: _headers(token),
      );
      if (_ok(response)) {
        return CheckTrackResult.fromJson(_decode(response));
      }
      return const CheckTrackResult(
        inPlaylist: false,
        playlistIds: [],
        playlistNames: [],
      );
    } catch (e) {
      debugPrint('[PlaylistService] checkTrackInPlaylists failed: $e');
      return const CheckTrackResult(
        inPlaylist: false,
        playlistIds: [],
        playlistNames: [],
      );
    }
  }
}
