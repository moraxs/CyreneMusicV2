/// 专辑详情结果（对应 Next.js demo/lib/services/albumService.ts 的 AlbumDetailInfo）。
///
/// [album] 为后端原始对象（保留全部字段，已规范化 picUrl 与 artist），
/// [songs] 为从 album 中提取出的原始歌曲列表。
class AlbumDetailInfo {
  const AlbumDetailInfo({required this.album, required this.songs});

  final Map<String, Object?> album;
  final List<Map<String, Object?>> songs;

  factory AlbumDetailInfo.fromJson(Map<String, Object?> json) =>
      AlbumDetailInfo(
        album: json['album'] is Map
            ? Map<String, Object?>.from(json['album'] as Map)
            : const {},
        songs:
            (json['songs'] as List?)
                ?.whereType<Map>()
                .map((e) => Map<String, Object?>.from(e))
                .toList() ??
            const [],
      );

  Map<String, Object?> toJson() => {'album': album, 'songs': songs};

  AlbumDetailInfo copyWith({
    Map<String, Object?>? album,
    List<Map<String, Object?>>? songs,
  }) => AlbumDetailInfo(album: album ?? this.album, songs: songs ?? this.songs);
}
