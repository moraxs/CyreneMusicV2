import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/discovery/discover_repository.dart';
import '../../domain/models/discovery.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';

/// Spotify 专辑预览（用于首页「收录你最喜爱的专辑」）。
typedef SpotifyAlbumPreview = ({
  String id,
  String name,
  String artists,
  String coverImgUrl,
});

/// Spotify 歌单预览（用于首页「你的热门合辑」）。
///
/// [itemKind] 是**这张卡片自己**的类型，不一定等于所在分区的 kind —— pathfinder
/// 首页里「More like 乌托邦P」这类分区会把歌单/专辑/艺术家混在一排（分区 kind 为
/// `mixed`），点开时必须按每张卡片自己的类型分流。
typedef SpotifyPlaylistPreview = ({
  String id,
  String name,
  String description,
  String coverImgUrl,
  int trackCount,
  SpotifyPersonalizedKind itemKind,
});

/// 个性化首页分区的类型，决定卡片形态与点开后的去处。
enum SpotifyPersonalizedKind {
  /// 歌单（Daily Mix / Discover Weekly 之类），点开走歌单详情。
  playlist,

  /// 单曲电台，点开时才用种子曲目现拉推荐。
  radio,

  /// 专辑，点开走专辑曲目。
  album,

  /// 可直接播放的曲目。
  track,

  /// 艺术家，点开走 [DiscoveryService.getSpotifyArtist] 拉热门曲目后进详情页。
  artist,

  /// 一个分区里混排多种类型，按每张卡片自己的 [SpotifyPlaylistPreview.itemKind]
  /// 渲染与分流。只有 pathfinder 首页（`/spotify/home`）会出现。
  mixed;

  static SpotifyPersonalizedKind? fromWireName(String? value) =>
      SpotifyPersonalizedKind.values
          .where((kind) => kind.name == value)
          .firstOrNull;
}

/// Spotify 艺术家详情。
///
/// [tracks] 是热门曲目，**顺序即热度排名**，渲染时不要重排。
typedef SpotifyArtistDetail = ({
  String id,
  String name,
  String coverImgUrl,
  int followers,
  int monthlyListeners,
  String biography,
  List<ToplistTrack> tracks,
  List<SpotifyPlaylistPreview> albums,
});

/// Spotify 首页分区标题本地化。
///
/// 后端给的是**号池账号视角**的英文原标题，直接显示有两个问题：
/// 1. 「Made For Morax Morax」会把号池账号的用户名暴露到每个用户的界面上；
/// 2. 「Your top mixes」「Based on your recent listening」这类第二人称说法是误导——
///    内容来自号池账号，不是用户自己的收听记录。
///
/// 因此统一换成不声称归属的中文说法。带变量的标题（艺术家名）保留变量部分。
/// **未收录的标题原样返回**，Spotify 改词或新增分区时不至于出现空标题。
String localizeSpotifySectionTitle(String title) {
  final trimmed = title.trim();
  if (trimmed.isEmpty) return trimmed;

  for (final rule in _spotifySectionTitlePatterns) {
    final match = rule.pattern.firstMatch(trimmed);
    if (match != null) return rule.format(match.group(1)?.trim() ?? '');
  }
  return _spotifySectionTitles[trimmed] ?? trimmed;
}

/// 带变量的标题：括号里捕获的是艺术家名等动态部分。
///
/// `Made For` 放在最前且**必须**命中——它后面跟的是号池账号的用户名，
/// 绝不能漏到界面上。
final _spotifySectionTitlePatterns =
    <({RegExp pattern, String Function(String) format})>[
      (
        pattern: RegExp(r'^Made For\b(.*)$', caseSensitive: false),
        format: (_) => '专属合辑',
      ),
      (
        pattern: RegExp(r'^More like (.+)$', caseSensitive: false),
        format: (name) => name.isEmpty ? '相似推荐' : '相似推荐 · $name',
      ),
      (
        pattern: RegExp(r'^Discover more from (.+)$', caseSensitive: false),
        format: (name) => name.isEmpty ? '探索更多' : '探索更多 · $name',
      ),
      (
        pattern: RegExp(r'^For fans of (.+)$', caseSensitive: false),
        format: (name) => name.isEmpty ? '同好推荐' : '$name 的乐迷也在听',
      ),
      (
        pattern: RegExp(r'^Best of (.+)$', caseSensitive: false),
        format: (name) => name.isEmpty ? '精选集' : '$name 精选',
      ),
      (
        pattern: RegExp(r'^Soundtrack your\b(.*)$', caseSensitive: false),
        format: (_) => '此刻的配乐',
      ),
    ];

const _spotifySectionTitles = <String, String>{
  'Your top mixes': '热门合辑',
  'Your playlists': '精选歌单',
  'Your favorite artists': '热门艺人',
  'Recently played': '近期热播',
  'Recommended for today': '今日推荐',
  'Recommended Stations': '推荐电台',
  'Albums featuring songs you like': '收录热门单曲的专辑',
  'Popular radio': '热门电台',
  'Popular albums and singles': '热门专辑与单曲',
  'Popular artists': '热门艺人',
  'Album picks': '专辑精选',
  'Fresh new music': '新鲜出炉',
  'Based on your recent listening': '近期口味推荐',
  'New releases for you': '新歌新碟',
  'Top picks in new music': '新音乐精选',
  'More of what you like': '你可能也喜欢',
  'Throwback': '时光回廊',
  'Winding down...': '夜深了',
  'Party': '派对时刻',
  "Today's biggest hits": '今日热榜',
  'Sing-along': '跟着一起唱',
  'Chill': '放松一下',
  'Instrumental': '纯音乐',
  'Jump back in': '继续听',
};

/// 分区副标题本地化。口径同 [localizeSpotifySectionTitle]：未收录的原样返回。
String localizeSpotifySectionDescription(String description) {
  final trimmed = description.trim();
  if (trimmed.isEmpty) return trimmed;
  return _spotifySectionDescriptions[trimmed] ?? trimmed;
}

const _spotifySectionDescriptions = <String, String>{
  'Inspired by your recent activity': '根据近期收听生成',
  'Albums for you based on what you like to listen to.': '依据收听口味挑选的专辑',
  'Brand new music from artists you love.': '热门艺人的最新作品',
  'Playlists full of favorites, still going strong.': '经典老歌，常听常新',
  'Unwind with these calming playlists.': '舒缓下来，慢慢听',
  'Non-stop music based on your favorite songs and artists.': '从热门歌曲与艺人出发，源源不断',
  'Bringing together the top songs from an artist.': '汇集艺人最具代表性的作品',
  'Hear a little bit of everything you love.': '各种风格都听一点',
};

/// 艺术家副标题：「726.3 万粉丝 · 每月 407.6 万听众」。
///
/// 两个数字都为 0（后端没给统计）时返回空串，让调用方退回简介或留空。
String formatSpotifyArtistStats(SpotifyArtistDetail artist) {
  String count(int value) {
    if (value >= 100000000) {
      return '${(value / 100000000).toStringAsFixed(1)} 亿';
    }
    if (value >= 10000) return '${(value / 10000).toStringAsFixed(1)} 万';
    return '$value';
  }

  final parts = <String>[
    if (artist.followers > 0) '${count(artist.followers)}粉丝',
    if (artist.monthlyListeners > 0) '每月 ${count(artist.monthlyListeners)}听众',
  ];
  return parts.join(' · ');
}

/// 个性化首页的一个分区。
typedef SpotifyPersonalizedSection = ({
  String id,
  String title,
  String description,
  SpotifyPersonalizedKind kind,
  /// [kind] 为 playlist / radio / album 时非空。radio 的 id 即种子曲目 id。
  List<SpotifyPlaylistPreview> collections,
  /// [kind] 为 track 时非空。
  List<ToplistTrack> tracks,
});

/// 发现页服务（对应 Next.js demo/lib/services/discoveryService.ts）。
///
/// 单例。榜单 / 推荐 / 歌单详情 / 发现页标签与歌单 / 评论 / 曲目转换。
/// 原 TS 的 localStorage 缓存未移植（交由 store 层处理），故 [forceRefresh]
/// 参数仅为保留签名兼容，不再产生副作用。
class DiscoveryService implements DiscoverRepository {
  DiscoveryService._();
  static final DiscoveryService instance = DiscoveryService._();

  /// 后端在 context-resolve 兜底且没读到歌单名时返回的占位值，对应
  /// `spotify-streamer` 的 `PLAYLIST_NAME_PLACEHOLDER`。收到它说明名字不可信，
  /// 应改用本地已知的榜单标题。两边字符串必须一致。
  static const _backendPlaylistNamePlaceholder = 'Spotify 歌单';

  static const _spotifyStandardCharts =
      <({String id, String title, String description})>[
        (
          id: '37i9dQZEVXbMDoHDwVN2tF',
          title: '全球热门 50',
          description: 'Spotify 全球播放热度最高的歌曲',
        ),
        (
          id: '37i9dQZEVXbNG2KDcFcKOF',
          title: '全球单曲周榜',
          description: 'Spotify 全球单曲周播放量排行',
        ),
        (
          id: '37i9dQZEVXbLRQDuF5jeBp',
          title: '美国热门 50',
          description: 'Spotify 美国地区热门歌曲',
        ),
        (
          id: '37i9dQZF1DXcBWIGoYBM5M',
          title: '今日热播',
          description: 'Spotify 官方编辑的全球热门曲目',
        ),
        (
          id: '37i9dQZF1DWUa8ZRTfalHk',
          title: '流行崛起',
          description: '正在上升的流行音乐新作',
        ),
        (
          id: '37i9dQZF1DX0XUsuxWHRQd',
          title: '说唱焦点',
          description: 'Spotify 嘻哈与说唱精选',
        ),
      ];

  static const _spotifyChineseCharts =
      <({String id, String title, String description})>[
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
    final allCharts = [..._spotifyStandardCharts, ..._spotifyChineseCharts];
    final standardCount = _spotifyStandardCharts.length;
    final results = await Future.wait(
      allCharts.indexed.map((entry) async {
        final (index, chart) = entry;
        try {
          final response = await ApiClient.instance.apiFetch(
            UrlService.instance.spotifyPlaylistUrl(chart.id, limit: limit),
          );
          final result = _decode(response);
          final data = result['data'];
          if (result['status'] != 200 || data is! Map) return null;
          final payload = Map<String, Object?>.from(data);
          final tracks = _parseSpotifyTracks(
            (payload['tracks'] as List? ?? const [])
                .whereType<Map>()
                .map((raw) => Map<String, Object?>.from(raw))
                .toList(growable: false),
          );
          return Toplist(
            id: -(index + 1),
            externalId: chart.id,
            name:
                payload['name']?.toString().isNotEmpty == true &&
                    payload['name']?.toString() !=
                        _backendPlaylistNamePlaceholder
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
        .where((chart) => chart.id >= -standardCount)
        .toList(growable: false);
    final chineseSources = available
        .where((chart) => chart.id < -standardCount)
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

  /// 从 Spotify Web API 的 images 数组里取第一张可用封面。
  String _firstImageUrl(Object? images) {
    if (images is! List) return '';
    for (final image in images) {
      if (image is! Map) continue;
      final url = image['url']?.toString();
      if (url != null && url.isNotEmpty) return url;
    }
    return '';
  }

  /// 解析后端统一的 Spotify 曲目结构（歌单 / 榜单 / 电台 / 个性化分区共用）。
  ///
  /// 后端 `normalizeTrack` 输出的形状固定：`artists` 是 `[{id,name}]`，
  /// `album` 是 `{id,name,coverArt}`，封面另有扁平的 `picUrl` 兜底。
  List<ToplistTrack> _parseSpotifyTracks(List<Map<String, Object?>> raw) {
    return raw
        .map((track) {
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
  }

  /// 获取号池 Spotify 账号的「官方同款」首页分区。
  ///
  /// 对应后端 `/spotify/home`，数据来自 Spotify 内部 GraphQL 网关 pathfinder
  /// （open.spotify.com 网页播放器自己用的那套）。实测能拿到 21 个分区、180+ 张
  /// 卡片：Daily Mix、Your top mixes、Release Radar、daylist 这些**算法生成、
  /// 不收藏就枚举不到**的合辑都在里面。
  ///
  /// 后端已带三层降级（pathfinder → `/personalized` → 落盘快照），所以这里拿到空
  /// 列表基本只意味着整条后端链路都不可用，调用方据此隐藏整段即可。
  Future<List<SpotifyPersonalizedSection>> getSpotifyHome({
    int limit = 20,
  }) => _fetchSpotifySections(
    UrlService.instance.spotifyHomeUrl(limit: limit),
    label: 'getSpotifyHome',
  );

  /// 获取号池账号基于**收藏**派生的首页分区。
  ///
  /// 对应后端 `/spotify/personalized`：全程走 librespot spclient。它只能看见账号
  /// 收藏过的东西，内容远不如 [getSpotifyHome] 丰富，保留作为后者的降级路径与
  /// 调试入口。原来的「新碟上架 / Hip Hop 分类」走 Web API `/v1/browse/*`，
  /// 自 2024-11 起对第三方应用一律 404，已整体删除。
  Future<List<SpotifyPersonalizedSection>> getSpotifyPersonalized({
    int limit = 20,
  }) => _fetchSpotifySections(
    UrlService.instance.spotifyPersonalizedUrl(limit: limit),
    label: 'getSpotifyPersonalized',
  );

  /// `/spotify/home` 与 `/spotify/personalized` 的共用解析。
  ///
  /// 两个端点的响应形状完全一致（后端刻意对齐的），所以只维护这一份解析。
  /// 任一分区解析不出内容就跳过该分区；整体失败返回空列表。
  Future<List<SpotifyPersonalizedSection>> _fetchSpotifySections(
    String url, {
    required String label,
  }) async {
    try {
      final response = await ApiClient.instance.apiFetch(url);
      final result = _decode(response);
      final data = result['data'];
      if (result['status'] != 200 || data is! Map) return const [];
      final sections = (data['sections'] as List? ?? const []);
      return sections
          .whereType<Map>()
          .map<SpotifyPersonalizedSection?>((raw) {
            final section = Map<String, Object?>.from(raw);
            final kind = SpotifyPersonalizedKind.fromWireName(
              section['kind']?.toString(),
            );
            if (kind == null) return null;
            final items = (section['items'] as List? ?? const [])
                .whereType<Map>()
                .map((item) => Map<String, Object?>.from(item))
                .toList(growable: false);
            final tracks = kind == SpotifyPersonalizedKind.track
                ? _parseSpotifyTracks(items)
                : const <ToplistTrack>[];
            final collections = kind == SpotifyPersonalizedKind.track
                ? const <SpotifyPlaylistPreview>[]
                : _parseCollectionItems(items, sectionKind: kind);
            if (tracks.isEmpty && collections.isEmpty) return null;
            return (
              id: section['id']?.toString() ?? '',
              // 后端给的是号池账号视角的英文原标题，这里换成面向用户的中文说法。
              title: localizeSpotifySectionTitle(
                section['title']?.toString() ?? '',
              ),
              description: localizeSpotifySectionDescription(
                section['description']?.toString() ?? '',
              ),
              kind: kind,
              collections: collections,
              tracks: tracks,
            );
          })
          .whereType<SpotifyPersonalizedSection>()
          .toList(growable: false);
    } catch (e) {
      debugPrint('[DiscoveryService] $label failed: $e');
      return const [];
    }
  }

  /// 把分区里的卡片解析成 [SpotifyPlaylistPreview]。
  ///
  /// 每张卡片的类型优先取它自己的 `type` 字段（pathfinder 才有），没有就沿用分区
  /// 的 kind（`/personalized` 的分区内类型是统一的）。
  ///
  /// `mixed` 只可能是分区级的类型，落到单张卡片上说明后端给错了，跳过。
  List<SpotifyPlaylistPreview> _parseCollectionItems(
    List<Map<String, Object?>> items, {
    required SpotifyPersonalizedKind sectionKind,
  }) {
    final previews = <SpotifyPlaylistPreview>[];
    for (final item in items) {
      final id = item['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final itemKind =
          SpotifyPersonalizedKind.fromWireName(item['type']?.toString()) ??
          sectionKind;
      if (itemKind == SpotifyPersonalizedKind.mixed) continue;
      // 电台/专辑用艺术家当副标题，歌单用它自己的简介。
      final artists = item['artists']?.toString() ?? '';
      previews.add((
        id: id,
        name: item['name']?.toString() ?? '',
        description: artists.isNotEmpty
            ? artists
            : (item['description']?.toString() ?? ''),
        coverImgUrl: item['coverImgUrl']?.toString() ?? '',
        trackCount: (item['trackCount'] as num?)?.toInt() ?? 0,
        itemKind: itemKind,
      ));
    }
    return List.unmodifiable(previews);
  }

  /// 拉取 Spotify 艺术家详情。
  ///
  /// 对应后端 `/spotify/artist/:id`（pathfinder `queryArtistOverview`）。Web API 的
  /// `/v1/artists/:id/top-tracks` 对应用级 token 已停用，这是唯一的路径，所以拿不到
  /// 就是真拿不到，调用方该提示用户而不是静默留空。
  Future<SpotifyArtistDetail?> getSpotifyArtist(String artistId) async {
    if (artistId.isEmpty) return null;
    try {
      final response = await ApiClient.instance.apiFetch(
        UrlService.instance.spotifyArtistUrl(artistId),
      );
      final result = _decode(response);
      final data = result['data'];
      if (result['status'] != 200 || data is! Map) return null;
      final payload = Map<String, Object?>.from(data);
      final name = payload['name']?.toString() ?? '';
      if (name.isEmpty) return null;
      final tracks = _parseSpotifyTracks(
        (payload['tracks'] as List? ?? const [])
            .whereType<Map>()
            .map((raw) => Map<String, Object?>.from(raw))
            .toList(growable: false),
      );
      final albums = _parseCollectionItems(
        (payload['albums'] as List? ?? const [])
            .whereType<Map>()
            .map((raw) => Map<String, Object?>.from(raw))
            .toList(growable: false),
        sectionKind: SpotifyPersonalizedKind.album,
      );
      return (
        id: payload['id']?.toString() ?? artistId,
        name: name,
        coverImgUrl: payload['coverImgUrl']?.toString() ?? '',
        followers: (payload['followers'] as num?)?.toInt() ?? 0,
        monthlyListeners: (payload['monthlyListeners'] as num?)?.toInt() ?? 0,
        biography: payload['biography']?.toString() ?? '',
        tracks: tracks,
        albums: albums,
      );
    } catch (e) {
      debugPrint('[DiscoveryService] getSpotifyArtist failed: $e');
      return null;
    }
  }

  /// 以某首歌为种子拉取 Spotify 单曲电台。
  Future<List<ToplistTrack>> getSpotifyRadio(
    String seedTrackId, {
    int limit = 30,
  }) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        UrlService.instance.spotifyRecommendationsUrl(
          seedTrackId,
          limit: limit,
        ),
      );
      final result = _decode(response);
      final data = result['data'];
      if (result['status'] != 200 || data is! Map) return const [];
      return _parseSpotifyTracks(
        (data['tracks'] as List? ?? const [])
            .whereType<Map>()
            .map((raw) => Map<String, Object?>.from(raw))
            .toList(growable: false),
      );
    } catch (e) {
      debugPrint('[DiscoveryService] getSpotifyRadio failed: $e');
      return const [];
    }
  }

  /// 获取 Spotify 专辑曲目。
  Future<List<ToplistTrack>> getSpotifyAlbumTracks(
    String albumId, {
    int limit = 50,
    int offset = 0,
    String country = 'US',
  }) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        UrlService.instance.spotifyAlbumTracksUrl(
          albumId,
          limit: limit,
          offset: offset,
          country: country,
        ),
      );
      final result = _decode(response);
      final items = result['items'];
      if (items is! List) return const [];
      final albumMeta = result['album'];
      final albumMap = albumMeta is Map
          ? Map<String, Object?>.from(albumMeta)
          : const <String, Object?>{};
      final albumName = albumMap['name']?.toString() ?? '';
      // Web API 的 /albums/:id/tracks 精简曲目里没有专辑封面，只有外层 album
      // 带图；streamer 走 context-resolve 兜底时曲目自带 album.images，两种都吃。
      final albumCover = _firstImageUrl(albumMap['images']);
      return items
          .whereType<Map>()
          .map<ToplistTrack>((raw) {
            final track = Map<String, Object?>.from(raw);
            final artists = (track['artists'] as List? ?? const [])
                .whereType<Map>()
                .map((a) => a['name']?.toString() ?? '')
                .where((name) => name.isNotEmpty)
                .join(' / ');
            final trackAlbum = track['album'];
            final trackCover = trackAlbum is Map
                ? _firstImageUrl(trackAlbum['images'])
                : '';
            return ToplistTrack(
              id: track['id']?.toString() ?? '',
              name: track['name']?.toString() ?? '',
              artists: artists,
              album: albumName,
              picUrl: trackCover.isNotEmpty ? trackCover : albumCover,
              duration: (track['duration_ms'] as num?)?.toInt(),
              source: MusicSource.spotify,
            );
          })
          .where((track) => track.id.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      debugPrint('[DiscoveryService] getSpotifyAlbumTracks failed: $e');
      return const [];
    }
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
        final tracks = _parseSpotifyTracks(
          (payload['tracks'] as List? ?? const [])
              .whereType<Map>()
              .map((raw) => Map<String, Object?>.from(raw))
              .toList(growable: false),
        );
        return PlaylistDetail(
          id: 0,
          name:
              payload['name']?.toString() ?? _backendPlaylistNamePlaceholder,
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
