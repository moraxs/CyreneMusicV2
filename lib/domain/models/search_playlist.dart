import 'music_source.dart';

/// 第三方平台歌单搜索结果（网易云 / 酷狗歌单搜索）。
class SearchPlaylist {
  const SearchPlaylist({
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.trackCount,
    required this.source,
    this.playCount = 0,
    this.creator,
  });

  final String id;
  final String name;
  final String coverUrl;
  final int trackCount;
  final int playCount;
  final String? creator;
  final MusicSource source;

  /// 平台展示名（用于结果卡片上的来源角标）。
  String get sourceLabel => switch (source) {
    MusicSource.netease => '网易云',
    MusicSource.kugou => '酷狗',
    _ => source.wireName,
  };

  factory SearchPlaylist.fromJson(
    Map<String, Object?> json, {
    required MusicSource source,
  }) => SearchPlaylist(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    coverUrl: json['coverUrl']?.toString() ?? '',
    trackCount: _parseInt(json['trackCount']),
    playCount: _parseInt(json['playCount']),
    creator: _parseCreator(
      json['creator'] ??
          json['creatorNickname'] ??
          json['nickname'] ??
          json['userName'] ??
          json['username'] ??
          json['author'],
    ),
    source: source,
  );

  /// 创建者名称容错解析：处理字符串、Map 或空字符。
  static String? _parseCreator(Object? value) {
    if (value == null) return null;
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is Map) {
      final nick = value['nickname'] ??
          value['name'] ??
          value['username'] ??
          value['userName'];
      if (nick != null) {
        final trimmed = nick.toString().trim();
        if (trimmed.isNotEmpty) return trimmed;
      }
    }
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// 数字字段容错解析：酷狗等平台可能返回字符串形式的数字。
  static int _parseInt(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }
}
