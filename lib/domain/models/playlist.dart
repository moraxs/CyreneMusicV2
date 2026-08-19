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
class PlaylistSyncResult {
  const PlaylistSyncResult({
    required this.insertedCount,
    required this.removedCount,
    required this.newTracks,
    required this.message,
  });

  final int insertedCount;
  final int removedCount;
  final List<PlaylistTrack> newTracks;
  final String message;
}
