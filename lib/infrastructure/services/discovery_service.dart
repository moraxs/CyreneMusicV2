import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/discovery/discover_repository.dart';
import '../../domain/models/discovery.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';

/// 发现页服务（对应 Next.js demo/lib/services/discoveryService.ts）。
///
/// 单例。榜单 / 推荐 / 歌单详情 / 发现页标签与歌单 / 评论 / 曲目转换。
/// 原 TS 的 localStorage 缓存未移植（交由 store 层处理），故 [forceRefresh]
/// 参数仅为保留签名兼容，不再产生副作用。
class DiscoveryService implements DiscoverRepository {
  DiscoveryService._();
  static final DiscoveryService instance = DiscoveryService._();

  static const _spotifyCharts =
      <({String id, String title, String description})>[
        (
          id: '37i9dQZEVXbMDoHDwVN2tF',
          title: '全球热门 50',
          description: 'Spotify 全球播放热度最高的歌曲',
        ),
        (
          id: '37i9dQZEVXbLiRSasKsNU9',
          title: '全球飙升 50',
          description: '正在 Spotify 快速走红的歌曲',
        ),
        (
          id: '37i9dQZEVXbLRQDuF5jeBp',
          title: '美国热门 50',
          description: 'Spotify 美国地区热门歌曲',
        ),
        (
          id: '37i9dQZEVXbLwpL8TjsxOG',
          title: '香港热门 50',
          description: 'Spotify 香港地区热门歌曲',
        ),
        (
          id: '37i9dQZEVXbMnZEatlMSiu',
          title: '台湾热门 50',
          description: 'Spotify 台湾地区热门歌曲',
        ),
      ];

  Map<String, String> _headers(String? token) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Map<String, Object?> _decode(http.Response response) {
    try {
      final payload = jsonDecode(response.body);
      return payload is Map ? Map<String, Object?>.from(payload) : const {};
    } catch (e) {
      debugPrint('[DiscoveryService] decode failed: $e');
      return const {};
    }
  }

  /// 获取榜单列表。QQ 榜单会把歌曲 id 替换为可播放的 songmid（字段 mid）。
  Future<List<Toplist>> getToplists({
    bool forceRefresh = false,
    String source = 'netease',
  }) async {
    final isQQ = source == 'qq';
    try {
      final endpoint = isQQ
          ? '${UrlService.instance.baseUrl}/qq/toplists'
          : UrlService.instance.toplistsUrl;
      final response = await ApiClient.instance.apiFetch(endpoint);
      final result = _decode(response);
      final rawList = result['toplists'];
      if (rawList is! List) return const [];
      var toplists = rawList
          .whereType<Map>()
          .map((e) => Toplist.fromJson(Map<String, Object?>.from(e)))
          .toList();
      if (isQQ) {
        // QQ 榜单歌曲 id 默认是数字 songid，需要改用可播放的 songmid（字段名为 mid）
        toplists = toplists
            .map(
              (list) => list.copyWith(
                source: MusicSource.qq,
                tracks: list.tracks
                    .map(
                      (t) => t.copyWith(
                        id: (t.mid != null && t.mid!.isNotEmpty)
                            ? t.mid!
                            : t.id,
                        source: MusicSource.qq,
                      ),
                    )
                    .toList(),
              ),
            )
            .toList();
      }
      return toplists;
    } catch (e) {
      debugPrint('[DiscoveryService] getToplists failed: $e');
      return const [];
    }
  }

  /// 桌面榜单页使用的 Spotify 精选榜单。每个榜单由后端 librespot
  /// `/spotify/playlist/:id` 接口读取；移动端不会调用此方法。
  Future<List<Toplist>> getSpotifyToplists({int limit = 50}) async {
    final results = await Future.wait(
      _spotifyCharts.indexed.map((entry) async {
        final (index, chart) = entry;
        try {
          final response = await ApiClient.instance.apiFetch(
            UrlService.instance.spotifyPlaylistUrl(chart.id, limit: limit),
          );
          final result = _decode(response);
          final data = result['data'];
          if (result['status'] != 200 || data is! Map) return null;
          final payload = Map<String, Object?>.from(data);
          final tracks = (payload['tracks'] as List? ?? const [])
              .whereType<Map>()
              .map((raw) {
                final track = Map<String, Object?>.from(raw);
                final artistsRaw = track['artists'];
                final artists = artistsRaw is List
                    ? artistsRaw
                          .whereType<Map>()
                          .map((artist) => artist['name']?.toString() ?? '')
                          .where((name) => name.isNotEmpty)
                          .join(' / ')
                    : track['artist']?.toString() ?? '';
                final album = track['album'];
                final albumMap = album is Map
                    ? Map<String, Object?>.from(album)
                    : const <String, Object?>{};
                return ToplistTrack(
                  id: track['id']?.toString() ?? '',
                  name: track['name']?.toString() ?? '',
                  artists: artists,
                  album: albumMap['name']?.toString() ?? '',
                  picUrl:
                      track['picUrl']?.toString() ??
                      albumMap['coverArt']?.toString() ??
                      '',
                  duration: (track['duration'] as num?)?.toInt(),
                  source: MusicSource.spotify,
                );
              })
              .where((track) => track.id.isNotEmpty)
              .toList(growable: false);
          return Toplist(
            id: -(index + 1),
            externalId: chart.id,
            name:
                payload['name']?.toString().isNotEmpty == true &&
                    payload['name']?.toString() != 'Spotify 榜单'
                ? payload['name'].toString()
                : chart.title,
            coverImgUrl:
                payload['coverImgUrl']?.toString() ??
                (tracks.isEmpty ? '' : tracks.first.picUrl),
            description: chart.description,
            tracks: tracks,
            source: MusicSource.spotify,
          );
        } catch (e) {
          debugPrint('[DiscoveryService] Spotify chart ${chart.id} failed: $e');
          return null;
        }
      }),
    );
    final available = results.whereType<Toplist>().toList(growable: false);
    final standardCharts = available
        .where((chart) => chart.id >= -3)
        .toList(growable: false);
    final chineseSources = available
        .where((chart) => chart.id < -3)
        .toList(growable: false);
    if (chineseSources.isEmpty) return standardCharts;

    // 香港与台湾榜单交错合并，避免其中一个地区的前排歌曲完全占满结果；
    // 同一 Spotify track id 只保留一次。
    final mergedTracks = <ToplistTrack>[];
    final seenIds = <String>{};
    final maxLength = chineseSources.fold<int>(
      0,
      (length, chart) =>
          chart.tracks.length > length ? chart.tracks.length : length,
    );
    for (
      var index = 0;
      index < maxLength && mergedTracks.length < limit;
      index++
    ) {
      for (final chart in chineseSources) {
        if (index >= chart.tracks.length) continue;
        final track = chart.tracks[index];
        if (seenIds.add(track.id)) mergedTracks.add(track);
        if (mergedTracks.length >= limit) break;
      }
    }
    final chineseChart = Toplist(
      id: -100,
      name: '华语热门',
      coverImgUrl: mergedTracks.isEmpty ? '' : mergedTracks.first.picUrl,
      description: '聚合 Spotify 香港与台湾热门榜单，每日发现流行华语音乐',
      tracks: mergedTracks,
      source: MusicSource.spotify,
    );
    return [...standardCharts, chineseChart];
  }

  /// 获取「推荐」聚合数据（每日歌曲 / 私人 FM / 推荐歌单等）。
  Future<RecommendData?> getRecommendForYou(
    String token, {
    bool forceRefresh = false,
    String source = 'netease',
  }) async {
    final isQQ = source == 'qq';
    final endpoint = isQQ
        ? '${UrlService.instance.baseUrl}/qq/recommend/for_you'
        : '${UrlService.instance.baseUrl}/recommend/for_you';
    try {
      final response = await ApiClient.instance.apiFetch(
        endpoint,
        headers: _headers(token),
      );
      final result = _decode(response);
      if (result['success'] == true) {
        final data = result['data'];
        return data is Map
            ? RecommendData.fromJson(Map<String, Object?>.from(data))
            : null;
      }
      return null;
    } catch (e) {
      debugPrint('[DiscoveryService] getRecommendForYou failed: $e');
      return null;
    }
  }

  /// 获取歌单/榜单详情。
  ///
  /// [source] 'netease' | 'qq'：数据来源平台。
  /// [qqKind] 'toplist' | 'playlist'：仅当 source='qq' 时生效。
  ///   - 'toplist'（默认）：id 是榜单 topId（如 3/4/26），走 /qq/toplist/:topId
  ///   - 'playlist'：id 是歌单 dissid（如推荐歌单），走 /qq/playlist?id=
  Future<PlaylistDetail?> getPlaylistDetail(
    Object id, {
    int limit = 200,
    String? token,
    String source = 'netease',
    String qqKind = 'toplist',
  }) async {
    final idStr = id.toString();
    if (source == 'spotify') {
      try {
        final response = await ApiClient.instance.apiFetch(
          UrlService.instance.spotifyPlaylistUrl(idStr, limit: limit),
        );
        final result = _decode(response);
        final data = result['data'];
        if (result['status'] != 200 || data is! Map) return null;
        final payload = Map<String, Object?>.from(data);
        final tracks = (payload['tracks'] as List? ?? const [])
            .whereType<Map>()
            .map((raw) {
              final track = Map<String, Object?>.from(raw);
              final artistsRaw = track['artists'];
              final artists = artistsRaw is List
                  ? artistsRaw
                        .whereType<Map>()
                        .map((artist) => artist['name']?.toString() ?? '')
                        .where((name) => name.isNotEmpty)
                        .join(' / ')
                  : track['artist']?.toString() ?? '';
              final albumRaw = track['album'];
              final album = albumRaw is Map
                  ? Map<String, Object?>.from(albumRaw)
                  : const <String, Object?>{};
              return ToplistTrack(
                id: track['id']?.toString() ?? '',
                name: track['name']?.toString() ?? '',
                artists: artists,
                album: album['name']?.toString() ?? '',
                picUrl:
                    track['picUrl']?.toString() ??
                    album['coverArt']?.toString() ??
                    '',
                duration: (track['duration'] as num?)?.toInt(),
                source: MusicSource.spotify,
              );
            })
            .where((track) => track.id.isNotEmpty)
            .toList(growable: false);
        return PlaylistDetail(
          id: 0,
          name: payload['name']?.toString() ?? 'Spotify 歌单',
          coverImgUrl:
              payload['coverImgUrl']?.toString() ??
              (tracks.isEmpty ? '' : tracks.first.picUrl),
          description: payload['description']?.toString() ?? '来自 Spotify 的歌单',
          source: MusicSource.spotify,
          tracks: tracks,
          playCount: 0,
          creator: 'Spotify',
          trackCount: (payload['total'] as num?)?.toInt() ?? tracks.length,
          createTime: 0,
          updateTime: 0,
          tags: const ['Spotify'],
        );
      } catch (e) {
        debugPrint('[DiscoveryService] getSpotifyPlaylistDetail failed: $e');
        return null;
      }
    }
    if (source == 'qq') {
      if (qqKind == 'playlist') {
        // QQ 歌单详情走 /qq/playlist?id=<dissid>，后端返回结构（data.playlist）与网易云一致
        try {
          final response = await ApiClient.instance.apiFetch(
            '${UrlService.instance.baseUrl}/qq/playlist?id=$idStr&limit=$limit',
          );
          final result = _decode(response);
          if (result['success'] == true) {
            final data = result['data'];
            if (data is Map) {
              final playlist = data['playlist'];
              if (playlist is Map) {
                return PlaylistDetail.fromJson(
                  Map<String, Object?>.from(playlist),
                );
              }
            }
          }
          return null;
        } catch (e) {
          debugPrint('[DiscoveryService] getQQPlaylistDetail failed: $e');
          return null;
        }
      }
      // QQ 榜单「查看全部」走 /qq/toplist/:topId，返回扁平结构，需适配为 PlaylistDetail
      try {
        final response = await ApiClient.instance.apiFetch(
          '${UrlService.instance.baseUrl}/qq/toplist/$idStr?limit=$limit',
        );
        final result = _decode(response);
        if (result['status'] == 200) {
          final tracksRaw = result['tracks'];
          final tracks = (tracksRaw is List ? tracksRaw : const <Object>[])
              .whereType<Map>()
              .map((t) {
                final m = Map<String, Object?>.from(t);
                final mid = m['mid']?.toString();
                return ToplistTrack.fromJson(m).copyWith(
                  id: (mid != null && mid.isNotEmpty)
                      ? mid
                      : (m['id']?.toString() ?? ''),
                  source: MusicSource.qq,
                );
              })
              .toList();
          return PlaylistDetail(
            id: (result['id'] as num?)?.toInt() ?? 0,
            name: result['name']?.toString() ?? '',
            coverImgUrl: result['coverImgUrl']?.toString() ?? '',
            description: result['description']?.toString() ?? '',
            source: MusicSource.qq,
            tracks: tracks,
            playCount: (result['playCount'] as num?)?.toInt() ?? 0,
            creator: result['creator']?.toString() ?? 'QQ音乐',
            trackCount:
                (result['trackCount'] as num?)?.toInt() ?? tracks.length,
            createTime: (result['createTime'] as num?)?.toInt() ?? 0,
            updateTime: (result['updateTime'] as num?)?.toInt() ?? 0,
            tags:
                (result['tags'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
          );
        }
        return null;
      } catch (e) {
        debugPrint('[DiscoveryService] getQQToplistDetail failed: $e');
        return null;
      }
    }

    if (source == 'kugou') {
      try {
        final response = await ApiClient.instance.apiFetch(
          '${UrlService.instance.baseUrl}/kugou/public/playlist?id=$idStr',
        );
        final result = _decode(response);
        final data = result['data'];
        if (result['code'] == 200 && data is Map) {
          final payload = Map<String, Object?>.from(data);
          final tracks = (payload['tracks'] as List? ?? const [])
              .whereType<Map>()
              .map((raw) {
                final track = Map<String, Object?>.from(raw);
                return ToplistTrack(
                  id: track['hash']?.toString() ?? '',
                  name: track['title']?.toString() ?? '',
                  artists: track['author']?.toString() ?? '',
                  album: '',
                  picUrl: track['cover']?.toString() ?? '',
                  duration: (track['duration'] as num?)?.toInt(),
                  source: MusicSource.kugou,
                );
              })
              .where((track) => track.id.isNotEmpty)
              .toList(growable: false);
          return PlaylistDetail(
            id: (payload['id'] as num?)?.toInt() ?? (int.tryParse(idStr) ?? 0),
            name: payload['name']?.toString() ??
                payload['title']?.toString() ??
                '',
            coverImgUrl: payload['pic']?.toString() ??
                payload['cover']?.toString() ??
                payload['coverImgUrl']?.toString() ??
                '',
            description: payload['intro']?.toString() ??
                payload['description']?.toString() ??
                '',
            source: MusicSource.kugou,
            tracks: tracks,
            playCount: (payload['play_count'] as num?)?.toInt() ?? 0,
            creator: payload['creator']?.toString() ??
                payload['author']?.toString() ??
                '',
            trackCount: (payload['total'] as num?)?.toInt() ?? tracks.length,
            createTime: 0,
            updateTime: 0,
            tags: const ['酷狗'],
          );
        }
        return null;
      } catch (e) {
        debugPrint('[DiscoveryService] getKugouPlaylistDetail failed: $e');
        return null;
      }
    }

    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/playlist?id=$idStr&limit=$limit',
        headers: _headers(token),
      );
      final result = _decode(response);
      if (result['success'] == true) {
        final data = result['data'];
        if (data is Map) {
          final playlist = data['playlist'];
          if (playlist is Map) {
            return PlaylistDetail.fromJson(Map<String, Object?>.from(playlist));
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('[DiscoveryService] getPlaylistDetail failed: $e');
      return null;
    }
  }

  @override
  Future<List<DiscoveryTag>> getTags() => getDiscoverTags();

  /// 获取网易精选歌单分类标签。
  Future<List<DiscoveryTag>> getDiscoverTags() async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/netease/playlist/highquality/tags',
      );
      final result = _decode(response);
      if (result['status'] == 200) {
        final tags = result['tags'];
        if (tags is List) {
          return tags
              .whereType<Map>()
              .map((e) => DiscoveryTag.fromJson(Map<String, Object?>.from(e)))
              .toList();
        }
      }
      return const [];
    } catch (e) {
      debugPrint('[DiscoveryService] getDiscoverTags failed: $e');
      return const [];
    }
  }

  @override
  Future<List<DiscoveryPlaylist>> getPlaylists({
    String category = '全部歌单',
    bool forceRefresh = false,
  }) => getDiscoverPlaylists(cat: category, forceRefresh: forceRefresh);

  /// 按分类获取发现页歌单。
  Future<List<DiscoveryPlaylist>> getDiscoverPlaylists({
    String cat = '全部歌单',
    bool forceRefresh = false,
  }) async {
    try {
      final encodedCat = Uri.encodeQueryComponent(cat);
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/netease/top/playlist?cat=$encodedCat',
      );
      final result = _decode(response);
      if (result['status'] == 200) {
        final list = result['playlists'];
        if (list is List) {
          return list.whereType<Map>().map((item) {
            final m = Map<String, Object?>.from(item);
            final creator = m['creator'];
            return DiscoveryPlaylist(
              id: (m['id'] as num?)?.toInt() ?? 0,
              name: m['name']?.toString() ?? '',
              coverImgUrl: m['coverImgUrl']?.toString() ?? '',
              creatorNickname: creator is Map
                  ? (creator['nickname']?.toString() ?? '')
                  : (creator?.toString() ?? ''),
              playCount: (m['playCount'] as num?)?.toInt() ?? 0,
              trackCount: (m['trackCount'] as num?)?.toInt() ?? 0,
            );
          }).toList();
        }
      }
      return const [];
    } catch (e) {
      debugPrint('[DiscoveryService] getDiscoverPlaylists failed: $e');
      return const [];
    }
  }

  /// 将后端原始歌曲对象转换为 [Track]。
  ///
  /// QQ 音乐歌曲：id 必须用 songmid（非数字），否则后端会按数字 songid 处理导致播放失败。
  Track convertToTrack(Map<String, Object?> song) {
    final albumData = song['al'] ?? song['album'];
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

    String album = '';
    String picUrl = song['picUrl']?.toString() ?? '';
    if (albumData is String) {
      album = albumData;
    } else if (albumData is Map) {
      album = albumData['name']?.toString() ?? '';
      final albumPic = albumData['picUrl'];
      if (albumPic != null) picUrl = albumPic.toString();
    }
    // 时长：dt 为毫秒，duration 为秒，统一换算为秒
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

    final isQQ =
        song['source'] == MusicSource.qq.wireName || song['mid'] != null;
    if (isQQ) {
      return Track(
        id: (song['mid'] ?? song['id'])?.toString() ?? '',
        name: song['name']?.toString() ?? '',
        artists: artists,
        album: album,
        picUrl: picUrl,
        source: MusicSource.qq,
        duration: Duration(milliseconds: (seconds * 1000).round()),
      );
    }

    return Track(
      id: song['id']?.toString() ?? '',
      name: song['name']?.toString() ?? '',
      artists: artists,
      album: album,
      picUrl: picUrl,
      source: song['source'] != null
          ? MusicSource.fromWireName(song['source'].toString())
          : MusicSource.netease,
      duration: Duration(milliseconds: (seconds * 1000).round()),
    );
  }

  /// 获取歌单评论。
  ///
  /// [sortType] 0=按时间（默认），1=按热度。
  Future<PlaylistComments?> getPlaylistComments(
    Object playlistId, {
    int limit = 20,
    int offset = 0,
    int before = 0,
    int sortType = 0,
  }) async {
    try {
      final params =
          'id=$playlistId&limit=$limit&offset=$offset&before=$before&sortType=$sortType';
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/comment/playlist?$params',
      );
      final result = _decode(response);
      if (result['status'] == 200) {
        return PlaylistComments.fromJson(result);
      }
      return null;
    } catch (e) {
      debugPrint('[DiscoveryService] getPlaylistComments failed: $e');
      return null;
    }
  }
}
