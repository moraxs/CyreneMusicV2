import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../domain/models/music_source.dart';
import '../../../../domain/models/user.dart';
import '../../../../infrastructure/core/url_service.dart';
import '../../../../infrastructure/services/artist_service.dart';
import 'player_service.dart';
import 'song_detail.dart';

export 'netease_discover.dart';
export 'netease_discover_service.dart';

/// 原版 `NeteaseSongWikiService` 兼容层：返回原始 Map（原版面板按 Map 消费）。
class NeteaseSongWikiService {
  static final NeteaseSongWikiService _instance =
      NeteaseSongWikiService._internal();
  factory NeteaseSongWikiService() => _instance;
  NeteaseSongWikiService._internal();

  Future<Map<String, dynamic>?> _getJson(String path) async {
    try {
      final resp = await http
          .get(Uri.parse('${UrlService.instance.baseUrl}$path'))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final data = json.decode(utf8.decode(resp.bodyBytes));
      return data is Map<String, dynamic> ? data : null;
    } catch (e) {
      debugPrint('[NeteaseSongWikiService compat] $path 失败: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchSongWiki(dynamic id) async {
    final data = await _getJson('/song/wiki/summary?id=$id');
    return (data?['data'] as Map<String, dynamic>?) ?? data;
  }

  Future<Map<String, dynamic>?> fetchSongMusicDetail(dynamic id) async {
    final data = await _getJson('/song/music/detail/get?id=$id');
    return (data?['data'] as Map<String, dynamic>?) ?? data;
  }
}

/// 原版 `SongMemoryService` 兼容层（回忆坐标，需登录）。
class SongMemoryService {
  static final SongMemoryService _instance = SongMemoryService._internal();
  factory SongMemoryService() => _instance;
  SongMemoryService._internal();

  Future<Map<String, dynamic>?> fetchSongMemory(
    dynamic trackId,
    String source,
  ) async {
    final token = PlayerService().account?.token;
    if (token == null || token.isEmpty) return null;
    try {
      final resp = await http
          .get(
            Uri.parse(
              '${UrlService.instance.baseUrl}/stats/song-memory?trackId=$trackId&source=$source',
            ),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final data = json.decode(utf8.decode(resp.bodyBytes));
      if (data is! Map<String, dynamic> || data['code'] != 200) return null;
      return data['data'] as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[SongMemoryService compat] 获取回忆坐标失败: $e');
      return null;
    }
  }
}

/// 原版 `NeteaseArtistDetailService` 兼容层：桥接到新架构 ArtistService，
/// 详情/简介以原始 Map 形状返回（原版面板按 Map 消费）。
class NeteaseArtistDetailService {
  static final NeteaseArtistDetailService _instance =
      NeteaseArtistDetailService._internal();
  factory NeteaseArtistDetailService() => _instance;
  NeteaseArtistDetailService._internal();

  Future<int?> resolveArtistIdByName(String name) =>
      ArtistService.instance.resolveArtistIdByName(name);

  Future<Map<String, dynamic>?> fetchArtistDetail(int id) async {
    final detail = await ArtistService.instance.fetchArtistDetail(id);
    if (detail == null) return null;
    return {
      'artist': {
        'id': detail.artist.id,
        'name': detail.artist.name,
        'picUrl': detail.artist.picUrl,
        'img1v1Url': detail.artist.img1v1Url,
        'briefDesc': detail.artist.briefDesc,
        'alias': detail.artist.alias,
        'musicSize': detail.artist.musicSize,
        'albumSize': detail.artist.albumSize,
      },
      'songs': [
        for (final track in detail.songs)
          {
            'id': track.id,
            'name': track.name,
            'artists': track.artists,
            'album': track.album,
            'picUrl': track.picUrl,
          },
      ],
    };
  }

  Future<Map<String, dynamic>?> fetchArtistDesc(int id) async {
    final detail = await ArtistService.instance.fetchArtistDetail(id);
    final brief = detail?.artist.briefDesc;
    if (brief == null || brief.isEmpty) return null;
    return {'briefDesc': brief};
  }
}

/// 原版 `MusicService` 兼容层：歌曲详情直接由当前 Track 合成
/// （新架构在解析音源时已把歌词等随附在 Track 上）。
class MusicService {
  static final MusicService _instance = MusicService._internal();
  factory MusicService() => _instance;
  MusicService._internal();

  Future<SongDetail?> fetchSongDetail({
    required dynamic songId,
    Object? quality,
    MusicSource source = MusicSource.netease,
  }) async {
    final track = PlayerService().currentTrack;
    if (track != null &&
        track.id.toString() == songId.toString() &&
        track.source == source) {
      return SongDetail.fromTrack(track);
    }
    return null;
  }
}

/// 原版 `AuthService` 兼容层（currentUser / isLoggedIn）。
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  User? get currentUser => PlayerService().account?.state.user;

  bool get isLoggedIn {
    final token = PlayerService().account?.token;
    return token != null && token.isNotEmpty;
  }
}
