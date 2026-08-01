import 'track.dart';

/// 歌手信息（对应 Next.js demo/lib/services/artistService.ts 的 ArtistDetailInfo.artist）。
class ArtistInfo {
  const ArtistInfo({
    required this.id,
    required this.name,
    this.picUrl,
    this.img1v1Url,
    this.briefDesc,
    this.alias,
    this.musicSize,
    this.albumSize,
    this.mvSize,
  });

  final int id;
  final String name;
  final String? picUrl;
  final String? img1v1Url;
  final String? briefDesc;
  final List<String>? alias;
  final int? musicSize;
  final int? albumSize;
  final int? mvSize;

  factory ArtistInfo.fromJson(Map<String, Object?> json) => ArtistInfo(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: json['name']?.toString() ?? '',
    picUrl: json['picUrl']?.toString(),
    img1v1Url: json['img1v1Url']?.toString(),
    briefDesc: json['briefDesc']?.toString(),
    alias: (json['alias'] as List?)?.map((e) => e.toString()).toList(),
    musicSize: (json['musicSize'] as num?)?.toInt(),
    albumSize: (json['albumSize'] as num?)?.toInt(),
    mvSize: (json['mvSize'] as num?)?.toInt(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'picUrl': picUrl,
    'img1v1Url': img1v1Url,
    'briefDesc': briefDesc,
    'alias': alias,
    'musicSize': musicSize,
    'albumSize': albumSize,
    'mvSize': mvSize,
  };

  ArtistInfo copyWith({
    int? id,
    String? name,
    String? picUrl,
    String? img1v1Url,
    String? briefDesc,
    List<String>? alias,
    int? musicSize,
    int? albumSize,
    int? mvSize,
  }) => ArtistInfo(
    id: id ?? this.id,
    name: name ?? this.name,
    picUrl: picUrl ?? this.picUrl,
    img1v1Url: img1v1Url ?? this.img1v1Url,
    briefDesc: briefDesc ?? this.briefDesc,
    alias: alias ?? this.alias,
    musicSize: musicSize ?? this.musicSize,
    albumSize: albumSize ?? this.albumSize,
    mvSize: mvSize ?? this.mvSize,
  );
}

/// 歌手专辑条目（对应 ArtistDetailInfo.albums 元素）。
class ArtistAlbum {
  const ArtistAlbum({
    required this.id,
    required this.name,
    this.picUrl,
    this.company,
    this.publishTime,
  });

  final int id;
  final String name;
  final String? picUrl;
  final String? company;
  final int? publishTime;

  factory ArtistAlbum.fromJson(Map<String, Object?> json) => ArtistAlbum(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: json['name']?.toString() ?? '',
    picUrl: json['picUrl']?.toString(),
    company: json['company']?.toString(),
    publishTime: (json['publishTime'] as num?)?.toInt(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'picUrl': picUrl,
    'company': company,
    'publishTime': publishTime,
  };

  ArtistAlbum copyWith({
    int? id,
    String? name,
    String? picUrl,
    String? company,
    int? publishTime,
  }) => ArtistAlbum(
    id: id ?? this.id,
    name: name ?? this.name,
    picUrl: picUrl ?? this.picUrl,
    company: company ?? this.company,
    publishTime: publishTime ?? this.publishTime,
  );
}

/// 歌手详情结果（对应 Next.js ArtistDetailInfo）。
class ArtistDetailInfo {
  const ArtistDetailInfo({
    required this.artist,
    required this.songs,
    required this.albums,
  });

  final ArtistInfo artist;
  final List<Track> songs;
  final List<ArtistAlbum> albums;

  factory ArtistDetailInfo.fromJson(Map<String, Object?> json) =>
      ArtistDetailInfo(
        artist: json['artist'] is Map
            ? ArtistInfo.fromJson(
                Map<String, Object?>.from(json['artist'] as Map),
              )
            : const ArtistInfo(id: 0, name: ''),
        songs:
            (json['songs'] as List?)
                ?.whereType<Map>()
                .map((e) => Track.fromJson(Map<String, Object?>.from(e)))
                .toList() ??
            const [],
        albums:
            (json['albums'] as List?)
                ?.whereType<Map>()
                .map((e) => ArtistAlbum.fromJson(Map<String, Object?>.from(e)))
                .toList() ??
            const [],
      );

  Map<String, Object?> toJson() => {
    'artist': artist.toJson(),
    'songs': songs.map((t) => t.toJson()).toList(),
    'albums': albums.map((a) => a.toJson()).toList(),
  };

  ArtistDetailInfo copyWith({
    ArtistInfo? artist,
    List<Track>? songs,
    List<ArtistAlbum>? albums,
  }) => ArtistDetailInfo(
    artist: artist ?? this.artist,
    songs: songs ?? this.songs,
    albums: albums ?? this.albums,
  );
}
