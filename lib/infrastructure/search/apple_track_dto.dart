import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';

/// Apple Music 搜索结果项 DTO（对应 searchService.ts searchApple 的字段映射）。
class AppleTrackDto {
  const AppleTrackDto(this._json);

  final Map<String, Object?> _json;

  Track toTrack() => Track(
    id: _json['id']?.toString() ?? '',
    name: _json['name']?.toString() ?? '',
    artists: _json['artists']?.toString() ?? '',
    album: _json['album']?.toString() ?? '',
    picUrl: _json['picUrl']?.toString() ?? '',
    source: MusicSource.apple,
  );
}
