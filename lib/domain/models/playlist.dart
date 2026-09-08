import 'music_source.dart';

/// 歌单（对应 Next.js demo/lib/models/playlist.ts 的 Playlist）。
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.trackCount,
    this.coverUrl,
    required this.createdAt,
    required this.updatedAt,
    this.source,
    this.sourcePlaylistId,
  });

  final int id;
  final String name;
  final bool isDefault;
  final int trackCount;
  final String? coverUrl;
  final String createdAt;
  final String updatedAt;
  final String? source;
  final String? sourcePlaylistId;

  factory Playlist.fromJson(Map<String, Object?> json) => Playlist(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: json['name']?.toString() ?? '',
    isDefault: json['isDefault'] == true,
    trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
    coverUrl: json['coverUrl']?.toString(),
    createdAt: json['createdAt']?.toString() ?? '',
    updatedAt: json['updatedAt']?.toString() ?? '',
    source: json['source']?.toString(),
    sourcePlaylistId: json['sourcePlaylistId']?.toString(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'isDefault': isDefault,
    'trackCount': trackCount,
    'coverUrl': coverUrl,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'source': source,
    'sourcePlaylistId': sourcePlaylistId,
  };
}

/// 歌单曲目项（对应 PlaylistTrack）。
class PlaylistTrack {
  const PlaylistTrack({
    required this.trackId,
    required this.name,
    required this.artists,
    required this.album,
    required this.picUrl,
    required this.source,
    required this.addedAt,
  });

  final String trackId;
  final String name;
  final String artists;
  final String album;
  final String picUrl;
  final MusicSource source;
  final String addedAt;

  factory PlaylistTrack.fromJson(Map<String, Object?> json) => PlaylistTrack(
    trackId: json['trackId']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    artists: json['artists']?.toString() ?? '',
    album: json['album']?.toString() ?? '',
    picUrl: json['picUrl']?.toString() ?? '',
    source: MusicSource.fromWireName(json['source']?.toString() ?? ''),
    addedAt: json['addedAt']?.toString() ?? '',
  );

  Map<String, Object?> toJson() => {
    'trackId': trackId,
    'name': name,
    'artists': artists,
    'album': album,
    'picUrl': picUrl,
    'source': source.wireName,
    'addedAt': addedAt,
  };
}

/// 歌单同步结果（对应 PlaylistSyncResult）。
/// 歌单同步结果。
///
/// 同步是**只增不删**的：从第三方导入过的歌单，用户往往还会在应用内手动加歌，
/// 所以「远端没有的本地曲目」一律保留，不存在移除数量这回事。
class PlaylistSyncResult {
  const PlaylistSyncResult({
    required this.insertedCount,
    required this.newTracks,
    required this.message,
    this.sourceIncomplete = false,
  });

  final int insertedCount;
  final List<PlaylistTrack> newTracks;
  final String message;

  /// 来源歌单没能完整取回（网易云分批拉取失败、或超出平台单页上限）。
  ///
  /// 意味着**有歌没被加进来**，得如实告诉用户可以稍后重试，
  /// 否则他会以为已经同步齐了。
  final bool sourceIncomplete;
}
