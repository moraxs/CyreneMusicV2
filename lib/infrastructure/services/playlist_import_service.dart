import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/music_source.dart';
import '../../domain/models/playlist_import.dart';
import '../../domain/models/track.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';

/// 外部歌单导入服务（对应 Next.js demo/lib/services/playlistImportService.ts）。
///
/// 单例。解析各平台歌单 ID 并拉取歌单详情。
class PlaylistImportService {
  PlaylistImportService._();
  static final PlaylistImportService instance = PlaylistImportService._();

  Map<String, Object?> _decode(http.Response response) {
    try {
      final payload = jsonDecode(response.body);
      return payload is Map ? Map<String, Object?>.from(payload) : const {};
    } catch (e) {
      debugPrint('[PlaylistImportService] decode failed: $e');
      return const {};
    }
  }

  /// 解析歌单 ID：纯数字（非 Apple）直接返回，否则按平台从 URL 中提取。
  String? parsePlaylistId(MusicPlatform platform, String input) {
    final trimmed = input.trim();
    if (RegExp(r'^\d+$').hasMatch(trimmed) && platform != MusicPlatform.apple) {
      return trimmed;
    }
    try {
      switch (platform) {
        case MusicPlatform.netease:
          return _parseNeteaseId(trimmed);
        case MusicPlatform.qq:
          return _parseQQId(trimmed);
        case MusicPlatform.kuwo:
          return _parseKuwoId(trimmed);
        case MusicPlatform.apple:
          return _parseAppleId(trimmed);
        case MusicPlatform.kugou:
          return null;
      }
    } catch (e) {
      return null;
    }
  }

  String? _parseNeteaseId(String url) {
    final match = RegExp(r'[?&]id=(\d+)').firstMatch(url);
    if (match != null) return match.group(1);
    if (url.contains('music.163.com/playlist/')) {
      final parts = url.split('/playlist/');
      final id = parts.length > 1 ? parts[1].split('?')[0] : null;
      if (id != null && RegExp(r'^\d+$').hasMatch(id)) return id;
    }
    return null;
  }

  String? _parseQQId(String url) {
    // Example: https://y.qq.com/n/ryqq/playlist/8522515502
    final match =
        RegExp(r'[?&](?:id=|playlist/)(\d+)').firstMatch(url) ??
        RegExp(r'/playlist/(\d+)').firstMatch(url);
    return match?.group(1);
  }

  String? _parseKuwoId(String url) {
    final match = RegExp(r'playlist_detail/(\d+)').firstMatch(url);
    return match?.group(1);
  }

  String? _parseAppleId(String url) {
    if (url.startsWith('pl.')) return url;
    final match = RegExp(r'(pl\.[a-zA-Z0-9\-]+)').firstMatch(url);
    return match?.group(1);
  }

  /// 拉取外部平台歌单详情。[token] 可选，存在时携带鉴权头。
  Future<ExternalPlaylist?> fetchExternalPlaylist(
    MusicPlatform platform,
    String playlistId, {
    String? token,
  }) async {
    String apiUrl;
    switch (platform) {
      case MusicPlatform.netease:
        apiUrl =
            '${UrlService.instance.baseUrl}/playlist?id=$playlistId&limit=1000';
        break;
      case MusicPlatform.qq:
        apiUrl =
            '${UrlService.instance.baseUrl}/qq/playlist?id=$playlistId&limit=1000';
        break;
      case MusicPlatform.kuwo:
        apiUrl =
            '${UrlService.instance.baseUrl}/kuwo/playlist?pid=$playlistId&limit=500';
        break;
      case MusicPlatform.apple:
        apiUrl = '${UrlService.instance.baseUrl}/apple/playlist?id=$playlistId';
        break;
      case MusicPlatform.kugou:
        return null;
    }

    try {
      final headers = <String, String>{};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      final response = await ApiClient.instance.apiFetch(
        apiUrl,
        headers: headers,
      );
      final result = _decode(response);
      if (result['success'] == true ||
          (result['status'] == 200 && result['data'] != null)) {
        final dataRoot = result['data'];
        if (dataRoot is! Map) return null;
        final data = dataRoot['playlist'] is Map
            ? Map<String, Object?>.from(dataRoot['playlist'] as Map)
            : Map<String, Object?>.from(dataRoot);
        final tracksRaw = data['tracks'];
        return ExternalPlaylist(
          id: playlistId,
          name: data['name']?.toString() ?? '',
          coverImgUrl:
              (data['coverImgUrl'] ?? data['picUrl'] ?? data['pic'])
                  ?.toString() ??
              '',
          creator: _creatorNickname(data['creator']),
          trackCount:
              (data['trackCount'] as num?)?.toInt() ??
              (data['tracks'] is List ? (data['tracks'] as List).length : 0),
          description: (data['description'] ?? data['intro'])?.toString(),
          tracks: (tracksRaw is List ? tracksRaw : const <Object>[])
              .whereType<Map>()
              .map(
                (t) => _convertToTrack(Map<String, Object?>.from(t), platform),
              )
              .toList(),
          platform: platform,
        );
      }
      return null;
    } catch (e) {
      debugPrint(
        '[PlaylistImportService] fetchExternalPlaylist failed for $platform: $e',
      );
      return null;
    }
  }

  String? _creatorNickname(Object? creator) {
    if (creator is Map) {
      final nick = creator['nickname'];
      if (nick != null && nick.toString().isNotEmpty) {
        return nick.toString();
      }
      return null;
    }
    return creator?.toString();
  }

  /// 复用 discoveryService.convertToTrack 的逻辑，按平台转换原始歌曲为 [Track]。
  Track _convertToTrack(Map<String, Object?> song, MusicPlatform platform) {
    final artistsData = song['ar'] ?? song['artists'];
    String artists;
    if (artistsData is List) {
      artists = artistsData
          .map(
            (a) => a is String
                ? a
                : (a is Map ? (a['name']?.toString() ?? '') : a.toString()),
          )
          .join(' / ');
    } else {
      artists = artistsData?.toString() ?? '';
    }

    final al = song['al'];
    final alb = song['album'];
    String album = '';
    if (al is Map && al['name'] != null && al['name'].toString().isNotEmpty) {
      album = al['name'].toString();
    } else if (alb is Map &&
        alb['name'] != null &&
        alb['name'].toString().isNotEmpty) {
      album = alb['name'].toString();
    } else {
      album = song['albumName']?.toString() ?? '';
    }

    String picUrl = '';
    if (al is Map && al['picUrl'] != null) {
      picUrl = al['picUrl'].toString();
    } else if (alb is Map && alb['picUrl'] != null) {
      picUrl = alb['picUrl'].toString();
    } else if (song['picUrl'] != null) {
      picUrl = song['picUrl'].toString();
    } else if (song['pic'] != null) {
      picUrl = song['pic'].toString();
    }

    final dt = song['dt'];
    final durationRaw = song['duration'];
    final double seconds;
    if (dt != null) {
      final ms = dt is num ? dt.toDouble() : (num.tryParse(dt.toString()) ?? 0);
      seconds = ms / 1000;
    } else if (durationRaw != null) {
      seconds = durationRaw is num
          ? durationRaw.toDouble()
          : (num.tryParse(durationRaw.toString()) ?? 0).toDouble();
    } else {
      seconds = 0;
    }

    return Track(
      id: (song['id'] ?? song['trackId'] ?? song['hash'])?.toString() ?? '',
      name: (song['name'] ?? song['trackName'])?.toString() ?? '',
      artists: artists,
      album: album,
      picUrl: picUrl,
      source: _mapPlatformToSource(platform),
      duration: Duration(milliseconds: (seconds * 1000).round()),
    );
  }

  MusicSource _mapPlatformToSource(MusicPlatform platform) {
    switch (platform) {
      case MusicPlatform.netease:
        return MusicSource.netease;
      case MusicPlatform.qq:
        return MusicSource.qq;
      case MusicPlatform.kugou:
        return MusicSource.kugou;
      default:
        return MusicSource.netease;
    }
  }

  /// 批量添加曲目到本地歌单。
  ///
  /// 后端暂无批量接口，留作占位（与 TS 源一致）。
  Future<int> addTracksToLocalPlaylist(
    int playlistId,
    List<Track> tracks,
  ) async {
    return 0;
  }
}
