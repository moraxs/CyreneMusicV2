import 'track.dart';

/// 网易云歌手简介（对应 NeteaseArtistBrief）。
class NeteaseArtistBrief {
  const NeteaseArtistBrief({
    required this.id,
    required this.name,
    required this.picUrl,
    this.alias,
  });

  final int id;
  final String name;
  final String picUrl;
  final List<String>? alias;

  factory NeteaseArtistBrief.fromJson(Map<String, Object?> json) =>
      NeteaseArtistBrief(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? '',
        picUrl: json['picUrl']?.toString() ?? '',
        alias: (json['alias'] as List?)?.map((e) => e.toString()).toList(),
      );
}

/// 跨平台搜索结果状态（对应 SearchResult）。
///
/// 各平台独立维护结果列表、loading、error，支持并行搜索与分别展示。
class SearchResult {
  const SearchResult({
    this.neteaseResults = const [],
    this.qqResults = const [],
    this.kugouResults = const [],
    this.kuwoResults = const [],
    this.appleResults = const [],
    this.spotifyResults = const [],
    this.qishuiResults = const [],
    this.artistResults = const [],
    this.neteaseLoading = false,
    this.qqLoading = false,
    this.kugouLoading = false,
    this.kuwoLoading = false,
    this.appleLoading = false,
    this.spotifyLoading = false,
    this.qishuiLoading = false,
    this.artistLoading = false,
    this.neteaseError,
    this.qqError,
    this.kugouError,
    this.kuwoError,
    this.appleError,
    this.spotifyError,
    this.qishuiError,
    this.artistError,
  });

  final List<Track> neteaseResults;
  final List<Track> qqResults;
  final List<Track> kugouResults;
  final List<Track> kuwoResults;
  final List<Track> appleResults;
  final List<Track> spotifyResults;
  final List<Track> qishuiResults;
  final List<NeteaseArtistBrief> artistResults;

  final bool neteaseLoading;
  final bool qqLoading;
  final bool kugouLoading;
  final bool kuwoLoading;
  final bool appleLoading;
  final bool spotifyLoading;
  final bool qishuiLoading;
  final bool artistLoading;

  final String? neteaseError;
  final String? qqError;
  final String? kugouError;
  final String? kuwoError;
  final String? appleError;
  final String? spotifyError;
  final String? qishuiError;
  final String? artistError;

  List<Track> get tracks => [
    ...neteaseResults,
    ...qqResults,
    ...kugouResults,
    ...kuwoResults,
    ...appleResults,
    ...spotifyResults,
    ...qishuiResults,
  ];

  /// 将同名同歌手的跨平台结果合并为一个可播放条目。
  ///
  /// 主条目保留第一个平台的数据，其余平台 ID 记录在 [Track.alternatives] 中，
  /// 供播放解析器在某个平台不可用时继续回退。
  ///
  /// [ordered] 的顺序决定主源与 alternatives 的顺序，即播放优先级序列。
  static List<Track> _mergeByPriority(List<Track> ordered) {
    final groups = <String, List<Track>>{};
    for (final track in ordered) {
      final key = '${_normalize(track.name)}|${_normalize(track.artists)}';
      groups.putIfAbsent(key, () => <Track>[]).add(track);
    }
    return groups.values
        .map((group) {
          final primary = group.first;
          return primary.copyWith(
            alternatives: group
                .skip(1)
                .map(TrackSourceRef.fromTrack)
                .toList(growable: false),
          );
        })
        .toList(growable: false);
  }

  /// 聚合分类结果：除 Spotify 外的平台按「网易云 > 酷狗 > QQ > 酷我 > Apple > 汽水」
  /// 优先级合并去重，主源与 alternatives 顺序即播放回退序列。
  List<Track> get aggregatedTracks => _mergeByPriority([
    ...neteaseResults,
    ...kugouResults,
    ...qqResults,
    ...kuwoResults,
    ...appleResults,
    ...qishuiResults,
  ]);

  /// 聚合分类中失败的平台提示，供 UI 顶部 inline alert 或失败空态使用。
  /// 无失败返回 null。顺序与 [aggregatedTracks] 一致，便于阅读。
  String? get aggregatedError {
    const labels = {
      'netease': '网易云',
      'kugou': '酷狗',
      'qq': 'QQ 音乐',
      'kuwo': '酷我',
      'apple': 'Apple Music',
      'qishui': '汽水音乐',
    };
    final failed = [
      ('netease', neteaseError),
      ('kugou', kugouError),
      ('qq', qqError),
      ('kuwo', kuwoError),
      ('apple', appleError),
      ('qishui', qishuiError),
    ].where((e) => e.$2 != null).map((e) => labels[e.$1]!).toList();
    return failed.isEmpty ? null : '${failed.join('、')}搜索失败';
  }

  bool get hasPartialFailure => [
    neteaseError,
    qqError,
    kugouError,
    kuwoError,
    appleError,
    spotifyError,
    qishuiError,
    artistError,
  ].any((error) => error != null);

  /// legacy 兼容 getter：按 [tracks] 原始顺序合并（含 Spotify）。
  /// UI 已改用 [aggregatedTracks]；保留供旧测试与外部消费者。
  List<Track> get mergedTracks => _mergeByPriority(tracks);

  static String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s'), '')
      .replaceAll(RegExp(r'[、/&，]'), ',');

  /// 空初始状态。
  static const SearchResult initial = SearchResult();
}
