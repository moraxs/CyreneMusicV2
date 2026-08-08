import 'music_source.dart';

/// 榜单内曲目项（对应 Next.js demo/lib/services/discoveryService.ts 的 Toplist.tracks 元素）。
class ToplistTrack {
  const ToplistTrack({
    required this.id,
    required this.name,
    required this.artists,
    required this.album,
    required this.picUrl,
    this.mid,
    this.duration,
    this.source,
  });

  /// 平台内部 ID。
  final String id;
  final String name;
  final String artists;
  final String album;
  final String picUrl;

  /// QQ 音乐特有：songmid，用于获取播放链接。
  final String? mid;

  /// 原始时长数值（单位由后端约定）。
  final int? duration;
  final MusicSource? source;

  factory ToplistTrack.fromJson(Map<String, Object?> json) => ToplistTrack(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    artists: json['artists']?.toString() ?? '',
    album: json['album']?.toString() ?? '',
    picUrl: json['picUrl']?.toString() ?? '',
    mid: json['mid']?.toString(),
    duration: (json['duration'] as num?)?.toInt(),
    source: json['source'] == null
        ? null
        : MusicSource.fromWireName(json['source'].toString()),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'artists': artists,
    'album': album,
    'picUrl': picUrl,
    'mid': mid,
    'duration': duration,
    'source': source?.wireName,
  };

  ToplistTrack copyWith({
    String? id,
    String? name,
    String? artists,
    String? album,
    String? picUrl,
    String? mid,
    int? duration,
    MusicSource? source,
  }) => ToplistTrack(
    id: id ?? this.id,
    name: name ?? this.name,
    artists: artists ?? this.artists,
    album: album ?? this.album,
    picUrl: picUrl ?? this.picUrl,
    mid: mid ?? this.mid,
    duration: duration ?? this.duration,
    source: source ?? this.source,
  );
}

/// 排行榜（对应 Next.js Toplist）。
class Toplist {
  const Toplist({
    required this.id,
    required this.name,
    required this.coverImgUrl,
    required this.description,
    required this.tracks,
    this.source,
    this.externalId,
  });

  final int id;
  final String name;
  final String coverImgUrl;
  final String description;
  final List<ToplistTrack> tracks;
  final MusicSource? source;
  final String? externalId;

  factory Toplist.fromJson(Map<String, Object?> json) => Toplist(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: json['name']?.toString() ?? '',
    coverImgUrl: json['coverImgUrl']?.toString() ?? '',
    description: json['description']?.toString() ?? '',
    tracks:
        (json['tracks'] as List?)
            ?.whereType<Map>()
            .map((e) => ToplistTrack.fromJson(Map<String, Object?>.from(e)))
            .toList() ??
        const [],
    source: json['source'] == null
        ? null
        : MusicSource.fromWireName(json['source'].toString()),
    externalId: json['externalId']?.toString(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'coverImgUrl': coverImgUrl,
    'description': description,
    'tracks': tracks.map((t) => t.toJson()).toList(),
    'source': source?.wireName,
    'externalId': externalId,
  };

  Toplist copyWith({
    int? id,
    String? name,
    String? coverImgUrl,
    String? description,
    List<ToplistTrack>? tracks,
    MusicSource? source,
    String? externalId,
  }) => Toplist(
    id: id ?? this.id,
    name: name ?? this.name,
    coverImgUrl: coverImgUrl ?? this.coverImgUrl,
    description: description ?? this.description,
    tracks: tracks ?? this.tracks,
    source: source ?? this.source,
    externalId: externalId ?? this.externalId,
  );
}

/// 推荐数据（对应 Next.js RecommendData）。
///
/// 各字段为后端原始数组，结构由具体来源决定，故保留为动态列表。
class RecommendData {
  const RecommendData({
    required this.dailySongs,
    required this.fm,
    required this.dailyPlaylists,
    required this.personalizedPlaylists,
    required this.radarPlaylists,
    required this.personalizedNewsongs,
  });

  final List<dynamic> dailySongs;
  final List<dynamic> fm;
  final List<dynamic> dailyPlaylists;
  final List<dynamic> personalizedPlaylists;
  final List<dynamic> radarPlaylists;
  final List<dynamic> personalizedNewsongs;

  factory RecommendData.fromJson(Map<String, Object?> json) => RecommendData(
    dailySongs: _asList(json['dailySongs']),
    fm: _asList(json['fm']),
    dailyPlaylists: _asList(json['dailyPlaylists']),
    personalizedPlaylists: _asList(json['personalizedPlaylists']),
    radarPlaylists: _asList(json['radarPlaylists']),
    personalizedNewsongs: _asList(json['personalizedNewsongs']),
  );

  Map<String, Object?> toJson() => {
    'dailySongs': dailySongs,
    'fm': fm,
    'dailyPlaylists': dailyPlaylists,
    'personalizedPlaylists': personalizedPlaylists,
    'radarPlaylists': radarPlaylists,
    'personalizedNewsongs': personalizedNewsongs,
  };

  static List<dynamic> _asList(Object? v) =>
      v is List ? List<dynamic>.from(v) : const [];
}

/// 发现页分类标签（对应 Next.js DiscoveryTag）。
class DiscoveryTag {
  const DiscoveryTag({
    required this.id,
    required this.name,
    required this.category,
  });

  final int id;
  final String name;
  final int category;

  factory DiscoveryTag.fromJson(Map<String, Object?> json) => DiscoveryTag(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: json['name']?.toString() ?? '',
    category: (json['category'] as num?)?.toInt() ?? 0,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'category': category,
  };
}

/// 发现页歌单条目（对应 Next.js DiscoveryPlaylist）。
class DiscoveryPlaylist {
  const DiscoveryPlaylist({
    required this.id,
    required this.name,
    required this.coverImgUrl,
    required this.creatorNickname,
    required this.playCount,
    required this.trackCount,
  });

  final int id;
  final String name;
  final String coverImgUrl;
  final String creatorNickname;
  final int playCount;
  final int trackCount;

  factory DiscoveryPlaylist.fromJson(Map<String, Object?> json) =>
      DiscoveryPlaylist(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? '',
        coverImgUrl: json['coverImgUrl']?.toString() ?? '',
        creatorNickname: json['creatorNickname']?.toString() ?? '',
        playCount: (json['playCount'] as num?)?.toInt() ?? 0,
        trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'coverImgUrl': coverImgUrl,
    'creatorNickname': creatorNickname,
    'playCount': playCount,
    'trackCount': trackCount,
  };
}

/// 歌单/榜单详情（对应 Next.js PlaylistDetail，继承自 Toplist）。
class PlaylistDetail {
  const PlaylistDetail({
    required this.id,
    required this.name,
    required this.coverImgUrl,
    required this.description,
    required this.tracks,
    required this.playCount,
    required this.creator,
    required this.trackCount,
    required this.createTime,
    required this.updateTime,
    required this.tags,
    this.source,
  });

  final int id;
  final String name;
  final String coverImgUrl;
  final String description;
  final List<ToplistTrack> tracks;
  final MusicSource? source;
  final int playCount;
  final String creator;
  final int trackCount;
  final int createTime;
  final int updateTime;
  final List<String> tags;

  factory PlaylistDetail.fromJson(Map<String, Object?> json) => PlaylistDetail(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: json['name']?.toString() ?? '',
    coverImgUrl: json['coverImgUrl']?.toString() ?? '',
    description: json['description']?.toString() ?? '',
    tracks:
        (json['tracks'] as List?)
            ?.whereType<Map>()
            .map((e) => ToplistTrack.fromJson(Map<String, Object?>.from(e)))
            .toList() ??
        const [],
    source: json['source'] == null
        ? null
        : MusicSource.fromWireName(json['source'].toString()),
    playCount: (json['playCount'] as num?)?.toInt() ?? 0,
    creator: json['creator']?.toString() ?? '',
    trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
    createTime: (json['createTime'] as num?)?.toInt() ?? 0,
    updateTime: (json['updateTime'] as num?)?.toInt() ?? 0,
    tags:
        (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'coverImgUrl': coverImgUrl,
    'description': description,
    'tracks': tracks.map((t) => t.toJson()).toList(),
    'source': source?.wireName,
    'playCount': playCount,
    'creator': creator,
    'trackCount': trackCount,
    'createTime': createTime,
    'updateTime': updateTime,
    'tags': tags,
  };
}

/// 歌单评论结果（对应 getPlaylistComments 返回结构）。
class PlaylistComments {
  const PlaylistComments({
    required this.code,
    required this.total,
    required this.more,
    required this.moreHot,
    required this.hotComments,
    required this.comments,
  });

  final int code;
  final int total;
  final bool more;
  final bool moreHot;
  final List<dynamic> hotComments;
  final List<dynamic> comments;

  factory PlaylistComments.fromJson(Map<String, Object?> json) =>
      PlaylistComments(
        code: (json['code'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 0,
        more: json['more'] == true,
        moreHot: json['moreHot'] == true,
        hotComments: json['hotComments'] is List
            ? List<dynamic>.from(json['hotComments'] as List)
            : const [],
        comments: json['comments'] is List
            ? List<dynamic>.from(json['comments'] as List)
            : const [],
      );

  Map<String, Object?> toJson() => {
    'code': code,
    'total': total,
    'more': more,
    'moreHot': moreHot,
    'hotComments': hotComments,
    'comments': comments,
  };
}
