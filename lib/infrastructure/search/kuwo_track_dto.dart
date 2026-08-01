import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';

/// 酷我搜索结果项 DTO（对应 searchService.ts searchKuwo 的字段映射）。
class KuwoTrackDto {
  const KuwoTrackDto(this._json);

  final Map<String, Object?> _json;

  Track toTrack() => Track(
    id: _json['rid']?.toString() ?? '0',
    name: _json['name']?.toString() ?? '',
    artists: _json['artist']?.toString() ?? '',
    album: _json['album']?.toString() ?? '',
    picUrl: _json['pic']?.toString() ?? '',
    source: MusicSource.kuwo,
  );
}
