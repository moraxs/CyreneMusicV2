import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/audio_source_config.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/search.dart';
import '../../domain/models/search_playlist.dart';
import '../../domain/models/track.dart';
import '../../domain/playback/audio_source_preferences_store.dart';
import '../../domain/search/search_repository.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';
import '../search/apple_track_dto.dart';
import '../search/kugou_track_dto.dart';
import '../search/kuwo_track_dto.dart';
import '../search/netease_track_dto.dart';
import '../search/qq_track_dto.dart';
import '../search/spotify_track_dto.dart';

typedef _PlatformOutcome = ({List<Track> tracks, String? error});
typedef _ArtistOutcome = ({List<NeteaseArtistBrief> artists, String? error});
typedef _PlaylistOutcome = ({List<SearchPlaylist> playlists, String? error});

/// 多平台并行搜索仓储（对应 Next.js demo/lib/services/searchService.ts）。
///
/// 网络与偏好均通过构造参数注入；每次搜索返回独立快照，不持有 UI 状态。
class SearchService implements SearchRepository {
  factory SearchService({
    ApiClient? apiClient,
    UrlService? urls,
    AudioSourcePreferencesStore? preferences,
  }) => SearchService._(
    apiClient ?? ApiClient.instance,
    urls ?? UrlService.instance,
    preferences,
  );

  SearchService._(this._apiClient, this._urls, this._preferences);

  final ApiClient _apiClient;
  final UrlService _urls;
  final AudioSourcePreferencesStore? _preferences;

  /// Spotify 搜索超时阈值（对应 TS SPOTIFY_SEARCH_TIMEOUT_MS）。
  static const Duration _spotifySearchTimeout = Duration(seconds: 7);

  Map<String, Object?> _decode(http.Response response) {
    try {
      final payload = jsonDecode(response.body);
      return payload is Map ? Map<String, Object?>.from(payload) : const {};
    } catch (_) {
      return const {};
    }
  }

  List<Map<String, Object?>> _asListOfMaps(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, Object?>.from(e))
        .toList(growable: false);
  }

  /// 根据当前音源类型解析其支持的平台列表（对应 TS search() 中的 switch）。
  List<String> supportedPlatformsFor(AudioSourceType? type) {
    switch (type) {
      case AudioSourceType.omniParse:
        return const [
          'netease',
          'qq',
          'kugou',
          'kuwo',
          'apple',
          'spotify',
        ];
      case AudioSourceType.lxMusic:
        // TODO: 从脚本内容中解析支持的平台，暂时默认四大平台
        return const ['netease', 'qq', 'kugou', 'kuwo'];
      case null:
        return const [];
    }
  }

  /// 执行搜索。并行发起各平台搜索 + 歌手搜索，返回聚合结果。
  @override
  Future<SearchResult> search(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return SearchResult.initial;

    final preferences = await _preferences?.read();
    final configuredSources =
        preferences?.sources ?? const <AudioSourceConfig>[];
    final supported = configuredSources.isEmpty
        ? supportedPlatformsFor(AudioSourceType.omniParse)
        : configuredSources
              .where((source) => source.isEnabled)
              .expand(
                (source) => source.supportedPlatforms.isEmpty
                    ? supportedPlatformsFor(source.type)
                    : source.supportedPlatforms,
              )
              .toSet()
              .toList(growable: false);

    // 各平台并行搜索 + 歌手搜索（Future 创建即开始执行，await 顺序不影响并发）。
    final neteaseFuture = supported.contains('netease')
        ? _searchNetease(trimmed)
        : Future<_PlatformOutcome?>.value();
    final qqFuture = supported.contains('qq')
        ? _searchQq(trimmed)
        : Future<_PlatformOutcome?>.value();
    final kugouFuture = supported.contains('kugou')
        ? _searchKugou(trimmed)
        : Future<_PlatformOutcome?>.value();
    final kuwoFuture = supported.contains('kuwo')
        ? _searchKuwo(trimmed)
        : Future<_PlatformOutcome?>.value();
    final appleFuture = supported.contains('apple')
        ? _searchApple(trimmed)
        : Future<_PlatformOutcome?>.value();
    final spotifyFuture = supported.contains('spotify')
        ? _searchSpotify(trimmed)
        : Future<_PlatformOutcome?>.value();
    final artistFuture = _searchArtists(trimmed); // 总是搜索歌手
    final playlistsFuture = _searchPlaylists(trimmed);

    final netease = await neteaseFuture;
    final qq = await qqFuture;
    final kugou = await kugouFuture;
    final kuwo = await kuwoFuture;
    final apple = await appleFuture;
    final spotify = await spotifyFuture;
    final artists = await artistFuture;
    final playlists = await playlistsFuture;

    final result = SearchResult(
      neteaseResults: netease?.tracks ?? const <Track>[],
      qqResults: qq?.tracks ?? const <Track>[],
      kugouResults: kugou?.tracks ?? const <Track>[],
      kuwoResults: kuwo?.tracks ?? const <Track>[],
      appleResults: apple?.tracks ?? const <Track>[],
      spotifyResults: spotify?.tracks ?? const <Track>[],
      artistResults: artists.artists,
      playlists: playlists.playlists,
      neteaseError: netease?.error,
      qqError: qq?.error,
      kugouError: kugou?.error,
      kuwoError: kuwo?.error,
      appleError: apple?.error,
      spotifyError: spotify?.error,
      artistError: artists.error,
      playlistsError: playlists.error,
    );
    return result;
  }

  // --- 各平台搜索 ---

  Future<_PlatformOutcome> _searchNetease(String keyword) async {
    try {
      final response = await _apiClient.apiFetch(
        _urls.searchUrl,
        method: 'POST',
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'keywords': keyword, 'limit': '20'},
      );
      final data = _decode(response);
      if (data['status'] == 200) {
        final tracks = _asListOfMaps(
          data['result'],
        ).map((e) => NeteaseTrackDto(e).toTrack()).toList(growable: false);
        return (tracks: tracks, error: null);
      }
      return (
        tracks: const <Track>[],
        error: data['message']?.toString() ?? 'Search failed',
      );
    } catch (e) {
      debugPrint('[SearchService] netease search failed: $e');
      return (tracks: const <Track>[], error: e.toString());
    }
  }

  Future<_PlatformOutcome> _searchQq(String keyword) async {
    try {
      final response = await _apiClient.apiFetch(
        '${_urls.qqSearchUrl}?keywords=${Uri.encodeQueryComponent(keyword)}&limit=20',
      );
      final data = _decode(response);
      if (data['status'] == 200) {
        final tracks = _asListOfMaps(
          data['result'],
        ).map((e) => QqTrackDto(e).toTrack()).toList(growable: false);
        return (tracks: tracks, error: null);
      }
      return (
        tracks: const <Track>[],
        error: data['message']?.toString() ?? 'Search failed',
      );
    } catch (e) {
      debugPrint('[SearchService] qq search failed: $e');
      return (tracks: const <Track>[], error: e.toString());
    }
  }

  Future<_PlatformOutcome> _searchKugou(String keyword) async {
    try {
      // 酷狗搜索通常需要特殊处理，参考 Flutter 实现
      final response = await _apiClient.apiFetch(
        '${_urls.kugouSearchUrl}?keywords=${Uri.encodeQueryComponent(keyword)}&limit=30',
      );
      final data = _decode(response);
      if (data['status'] == 200) {
        final tracks = _asListOfMaps(
          data['result'],
        ).map((e) => KugouTrackDto(e).toTrack()).toList(growable: false);
        return (tracks: tracks, error: null);
      }
      return (
        tracks: const <Track>[],
        error: data['message']?.toString() ?? 'Search failed',
      );
    } catch (e) {
      debugPrint('[SearchService] kugou search failed: $e');
      return (tracks: const <Track>[], error: e.toString());
    }
  }

  Future<_PlatformOutcome> _searchKuwo(String keyword) async {
    try {
      final response = await _apiClient.apiFetch(
        '${_urls.kuwoSearchUrl}?keywords=${Uri.encodeQueryComponent(keyword)}',
      );
      final data = _decode(response);
      if (data['status'] == 200) {
        final dataMap = data['data'];
        final songs = dataMap is Map ? dataMap['songs'] : null;
        final tracks = _asListOfMaps(
          songs,
        ).map((e) => KuwoTrackDto(e).toTrack()).toList(growable: false);
        return (tracks: tracks, error: null);
      }
      return (
        tracks: const <Track>[],
        error: data['message']?.toString() ?? 'Search failed',
      );
    } catch (e) {
      debugPrint('[SearchService] kuwo search failed: $e');
      return (tracks: const <Track>[], error: e.toString());
    }
  }

  Future<_PlatformOutcome> _searchApple(String keyword) async {
    try {
      final response = await _apiClient.apiFetch(
        '${_urls.appleSearchUrl}?keywords=${Uri.encodeQueryComponent(keyword)}&limit=20',
      );
      final data = _decode(response);
      if (data['status'] == 200) {
        final tracks = _asListOfMaps(
          data['result'],
        ).map((e) => AppleTrackDto(e).toTrack()).toList(growable: false);
        return (tracks: tracks, error: null);
      }
      return (
        tracks: const <Track>[],
        error: data['message']?.toString() ?? 'Search failed',
      );
    } catch (e) {
      debugPrint('[SearchService] apple search failed: $e');
      return (tracks: const <Track>[], error: e.toString());
    }
  }

  Future<_PlatformOutcome> _searchSpotify(String keyword) async {
    try {
      final response = await _apiClient
          .apiFetch(
            '${_urls.spotifySearchUrl}?keywords=${Uri.encodeQueryComponent(keyword)}',
          )
          .timeout(_spotifySearchTimeout);
      final data = _decode(response);
      if (data['status'] == 200) {
        final resultMap = data['result'];
        final tracksRaw = resultMap is Map ? resultMap['tracks'] : null;
        final tracks = _asListOfMaps(
          tracksRaw,
        ).map((e) => SpotifyTrackDto(e).toTrack()).toList(growable: false);
        return (tracks: tracks, error: null);
      }
      return (
        tracks: const <Track>[],
        error: (data['msg'] ?? data['message'])?.toString() ?? 'Search failed',
      );
    } on TimeoutException {
      return (tracks: const <Track>[], error: 'Spotify 搜索超时，请重试');
    } catch (e) {
      debugPrint('[SearchService] spotify search failed: $e');
      return (tracks: const <Track>[], error: e.toString());
    }
  }

  Future<_ArtistOutcome> _searchArtists(String keyword) async {
    try {
      final response = await _apiClient.apiFetch(
        '${_urls.baseUrl}/artist/search',
        method: 'POST',
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'keywords': keyword, 'limit': '20'},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return (
          artists: const <NeteaseArtistBrief>[],
          error: 'HTTP ${response.statusCode}',
        );
      }
      final data = _decode(response);
      if (data['status'] == 200) {
        final artists = _asListOfMaps(
          data['result'],
        ).map((e) => NeteaseArtistBrief.fromJson(e)).toList(growable: false);
        return (artists: artists, error: null);
      }
      return (
        artists: const <NeteaseArtistBrief>[],
        error: data['message']?.toString() ?? 'Server error',
      );
    } catch (e) {
      debugPrint('[SearchService] artist search failed: $e');
      return (artists: const <NeteaseArtistBrief>[], error: e.toString());
    }
  }

  // --- 歌单搜索（网易云 + 酷狗并行，聚合） ---

  Future<_PlaylistOutcome> _searchPlaylists(String keyword) async {
    final results = await Future.wait([
      _searchNeteasePlaylists(keyword),
      _searchKugouPlaylists(keyword),
    ]);
    final playlists = <SearchPlaylist>[
      ...results[0].playlists,
      ...results[1].playlists,
    ]..shuffle();
    final errors = [
      results[0].error,
      results[1].error,
    ].whereType<String>().toList();
    return (
      playlists: playlists,
      error: errors.isEmpty ? null : errors.join('；'),
    );
  }

  Future<_PlaylistOutcome> _searchNeteasePlaylists(String keyword) async {
    try {
      final response = await _apiClient.apiFetch(
        _urls.neteasePlaylistSearchUrl,
        method: 'POST',
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'keywords': keyword, 'limit': '30'},
      );
      final data = _decode(response);
      if (data['status'] == 200) {
        final playlists = _asListOfMaps(
          data['result'],
        ).map((e) => SearchPlaylist.fromJson(e, source: MusicSource.netease)).toList(growable: false);
        return (playlists: playlists, error: null);
      }
      return (
        playlists: const <SearchPlaylist>[],
        error: data['msg']?.toString() ?? 'Search failed',
      );
    } catch (e) {
      debugPrint('[SearchService] netease playlist search failed: $e');
      return (playlists: const <SearchPlaylist>[], error: e.toString());
    }
  }

  Future<_PlaylistOutcome> _searchKugouPlaylists(String keyword) async {
    try {
      final response = await _apiClient.apiFetch(
        '${_urls.kugouPlaylistSearchUrl}?keywords=${Uri.encodeQueryComponent(keyword)}&limit=30',
      );
      final data = _decode(response);
      if (data['status'] == 200) {
        final playlists = _asListOfMaps(
          data['result'],
        ).map((e) => SearchPlaylist.fromJson(e, source: MusicSource.kugou)).toList(growable: false);
        return (playlists: playlists, error: null);
      }
      return (
        playlists: const <SearchPlaylist>[],
        error: data['msg']?.toString() ?? 'Search failed',
      );
    } catch (e) {
      debugPrint('[SearchService] kugou playlist search failed: $e');
      return (playlists: const <SearchPlaylist>[], error: e.toString());
    }
  }
}
