/// 播放记录数据库条目（对应 Next.js demo/lib/services/historyService.ts 的 HistoryEntry）。
class HistoryEntry {
  HistoryEntry({
    required this.id,
    required this.source,
    required this.name,
    required this.artists,
    required this.album,
    required this.picUrl,
    required this.playCount,
    required this.listeningTime,
    required this.lastPlayedAt,
    this.firstPlayedAt,
  });

  /// 歌曲ID（字符串形式，避免平台间类型差异）。
  final String id;

  /// 播放平台 (netease, qq, kugou, etc.)。
  final String source;

  /// 歌曲名称。
  final String name;

  /// 歌手。
  final String artists;

  /// 专辑。
  final String album;

  /// 封面。
  final String picUrl;

  /// 播放次数。
  final int playCount;

  /// 累计播放时长 (秒)。
  final int listeningTime;

  /// 最后播放时间戳（毫秒）。
  final int lastPlayedAt;

  /// 第一次播放时间戳（毫秒）。
  final int? firstPlayedAt;

  /// 内部键，以 id 与 source 的组合逻辑标识歌曲。
  String get key => '$id:$source';

  HistoryEntry copyWith({
    String? name,
    String? artists,
    String? album,
    String? picUrl,
    int? playCount,
    int? listeningTime,
    int? lastPlayedAt,
    int? firstPlayedAt,
  }) => HistoryEntry(
    id: id,
    source: source,
    name: name ?? this.name,
    artists: artists ?? this.artists,
    album: album ?? this.album,
    picUrl: picUrl ?? this.picUrl,
    playCount: playCount ?? this.playCount,
    listeningTime: listeningTime ?? this.listeningTime,
    lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    firstPlayedAt: firstPlayedAt ?? this.firstPlayedAt,
  );

  factory HistoryEntry.fromJson(Map<String, Object?> json) => HistoryEntry(
    id: json['id']?.toString() ?? '',
    source: json['source']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    artists: json['artists']?.toString() ?? '',
    album: json['album']?.toString() ?? '',
    picUrl: json['picUrl']?.toString() ?? '',
    playCount: ((json['playCount'] as num?) ?? 0).toInt(),
    listeningTime: ((json['listeningTime'] as num?) ?? 0).toInt(),
    lastPlayedAt: ((json['lastPlayedAt'] as num?) ?? 0).toInt(),
    firstPlayedAt: (json['firstPlayedAt'] as num?)?.toInt(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'source': source,
    'name': name,
    'artists': artists,
    'album': album,
    'picUrl': picUrl,
    'playCount': playCount,
    'listeningTime': listeningTime,
    'lastPlayedAt': lastPlayedAt,
    'firstPlayedAt': firstPlayedAt,
  };
}

/// 总体统计数据（对应 Next.js OverallStats）。
class OverallStats {
  const OverallStats({
    required this.totalListeningTime,
    required this.totalPlayCount,
  });

  /// 总听歌时长（秒）。
  final int totalListeningTime;

  /// 总播放次数。
  final int totalPlayCount;

  factory OverallStats.fromJson(Map<String, Object?> json) => OverallStats(
    totalListeningTime: ((json['totalListeningTime'] as num?) ?? 0).toInt(),
    totalPlayCount: ((json['totalPlayCount'] as num?) ?? 0).toInt(),
  );

  Map<String, Object?> toJson() => {
    'totalListeningTime': totalListeningTime,
    'totalPlayCount': totalPlayCount,
  };
}
