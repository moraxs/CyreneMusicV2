/// 播放历史分页查询参数（对应 Next.js listeningStatsService.fetchPlayHistory 的 options）。
class PlayHistoryOptions {
  const PlayHistoryOptions({
    this.page,
    this.limit,
    this.startDate,
    this.endDate,
  });

  final int? page;
  final int? limit;
  final String? startDate;
  final String? endDate;

  /// 拼接为 URL 查询串（与 Next.js URLSearchParams 行为一致）。
  String toQueryString() {
    final params = <String, String>{};
    if (page != null) params['page'] = page.toString();
    if (limit != null) params['limit'] = limit.toString();
    if (startDate != null && startDate!.isNotEmpty) {
      params['startDate'] = startDate!;
    }
    if (endDate != null && endDate!.isNotEmpty) {
      params['endDate'] = endDate!;
    }
    if (params.isEmpty) return '';
    return params.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
  }
}

/// 「清空服务器播放历史」结果（对应 Next.js clearServerHistory 返回值）。
class ClearHistoryResult {
  const ClearHistoryResult({required this.success, required this.message});

  final bool success;
  final String message;
}

/// 单条播放排行项（对应 Next.js `stats.playCounts[i]` / TopRankingSection 的 item）。
///
/// 后端字段为下划线命名（track_id / track_name / pic_url / play_count），此处兼容
/// 驼峰与下划线两种写法。
class TopPlayItem {
  const TopPlayItem({
    required this.trackId,
    required this.trackName,
    required this.artists,
    required this.album,
    required this.picUrl,
    required this.source,
    required this.playCount,
  });

  final String trackId;
  final String trackName;
  final String artists;
  final String album;
  final String picUrl;
  final String source;
  final int playCount;

  factory TopPlayItem.fromJson(Map<String, Object?> json) => TopPlayItem(
    trackId:
        (json['track_id'] ?? json['trackId'] ?? json['id'])?.toString() ?? '',
    trackName:
        (json['track_name'] ?? json['trackName'] ?? json['name'])?.toString() ??
        '',
    artists: json['artists']?.toString() ?? '',
    album: json['album']?.toString() ?? '',
    picUrl: (json['pic_url'] ?? json['picUrl'])?.toString() ?? '',
    source: json['source']?.toString() ?? 'netease',
    playCount:
        ((json['play_count'] ?? json['playCount']) as num?)?.toInt() ?? 0,
  );
}

/// 用户累计统计数据（对应 Next.js `fetchStats()` 返回的 `data`）。
class ListeningStatsData {
  const ListeningStatsData({
    required this.totalListeningTime,
    required this.totalPlayCount,
    required this.playCounts,
  });

  /// 总听歌时长（秒）。
  final int totalListeningTime;

  /// 总播放次数。
  final int totalPlayCount;

  /// 播放排行（后端已按次数倒序）。
  final List<TopPlayItem> playCounts;

  factory ListeningStatsData.fromJson(Map<String, Object?> json) {
    final raw = json['playCounts'];
    return ListeningStatsData(
      totalListeningTime: ((json['totalListeningTime'] as num?) ?? 0).toInt(),
      totalPlayCount: ((json['totalPlayCount'] as num?) ?? 0).toInt(),
      playCounts: raw is List
          ? raw
                .whereType<Map>()
                .map((e) => TopPlayItem.fromJson(Map<String, Object?>.from(e)))
                .toList(growable: false)
          : const [],
    );
  }
}

/// 本周播放的单首歌曲（对应 Next.js WeeklyAlbumWall 的 song 元素）。
class WeeklyPlayItem {
  const WeeklyPlayItem({
    required this.trackId,
    required this.trackName,
    required this.artists,
    required this.picUrl,
    required this.source,
  });

  final String trackId;
  final String trackName;
  final String artists;
  final String picUrl;
  final String source;

  factory WeeklyPlayItem.fromJson(Map<String, Object?> json) => WeeklyPlayItem(
    trackId:
        (json['track_id'] ?? json['trackId'] ?? json['id'])?.toString() ?? '',
    trackName:
        (json['track_name'] ?? json['trackName'] ?? json['name'])?.toString() ??
        '',
    artists: json['artists']?.toString() ?? '',
    picUrl: (json['pic_url'] ?? json['picUrl'])?.toString() ?? '',
    source: json['source']?.toString() ?? 'netease',
  );
}

/// 单条听歌语言统计（对应 Next.js LanguageStatItem）。
class LanguageStatItem {
  const LanguageStatItem({
    required this.language,
    required this.playCount,
    required this.songCount,
  });

  final String language;
  final int playCount;
  final int songCount;

  factory LanguageStatItem.fromJson(Map<String, Object?> json) =>
      LanguageStatItem(
        language: json['language']?.toString() ?? '',
        playCount: ((json['playCount'] as num?) ?? 0).toInt(),
        songCount: ((json['songCount'] as num?) ?? 0).toInt(),
      );
}

/// 听歌语言统计聚合（对应 Next.js LanguageStatsSection 的 languageStats）。
class LanguageStatsData {
  const LanguageStatsData({
    required this.languages,
    required this.totalPlayCount,
    required this.totalSongCount,
  });

  final List<LanguageStatItem> languages;
  final int totalPlayCount;
  final int totalSongCount;

  factory LanguageStatsData.fromJson(Map<String, Object?> json) {
    final raw = json['languages'];
    return LanguageStatsData(
      languages: raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (e) =>
                      LanguageStatItem.fromJson(Map<String, Object?>.from(e)),
                )
                .toList(growable: false)
          : const [],
      totalPlayCount: ((json['totalPlayCount'] as num?) ?? 0).toInt(),
      totalSongCount: ((json['totalSongCount'] as num?) ?? 0).toInt(),
    );
  }
}
