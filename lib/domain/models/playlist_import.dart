import 'track.dart';

/// 外部歌单导入支持的平台（对应 Next.js MusicPlatform）。
enum MusicPlatform {
  netease('netease'),
  qq('qq'),
  kugou('kugou'),
  kuwo('kuwo'),
  apple('apple');

  const MusicPlatform(this.wireName);

  final String wireName;

  static MusicPlatform fromWireName(String? value) {
    if (value == null) return MusicPlatform.netease;
    for (final p in MusicPlatform.values) {
      if (p.wireName == value) return p;
    }
    return MusicPlatform.netease;
  }
}

/// 外部平台歌单（对应 Next.js ExternalPlaylist）。
class ExternalPlaylist {
  const ExternalPlaylist({
    required this.id,
    required this.name,
    required this.coverImgUrl,
    required this.trackCount,
    required this.tracks,
    required this.platform,
    this.creator,
    this.description,
  });

  final String id;
  final String name;
  final String coverImgUrl;
  final String? creator;
  final int trackCount;
  final String? description;
  final List<Track> tracks;
  final MusicPlatform platform;

  factory ExternalPlaylist.fromJson(Map<String, Object?> json) =>
      ExternalPlaylist(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        coverImgUrl: json['coverImgUrl']?.toString() ?? '',
        creator: json['creator']?.toString(),
        trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
        description: json['description']?.toString(),
        tracks:
            (json['tracks'] as List?)
                ?.whereType<Map>()
                .map((e) => Track.fromJson(Map<String, Object?>.from(e)))
                .toList() ??
            const [],
        platform: MusicPlatform.fromWireName(json['platform']?.toString()),
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'coverImgUrl': coverImgUrl,
    'creator': creator,
    'trackCount': trackCount,
    'description': description,
    'tracks': tracks.map((t) => t.toJson()).toList(),
    'platform': platform.wireName,
  };

  ExternalPlaylist copyWith({
    String? id,
    String? name,
    String? coverImgUrl,
    String? creator,
    int? trackCount,
    String? description,
    List<Track>? tracks,
    MusicPlatform? platform,
  }) => ExternalPlaylist(
    id: id ?? this.id,
    name: name ?? this.name,
    coverImgUrl: coverImgUrl ?? this.coverImgUrl,
    creator: creator ?? this.creator,
    trackCount: trackCount ?? this.trackCount,
    description: description ?? this.description,
    tracks: tracks ?? this.tracks,
    platform: platform ?? this.platform,
  );
}
