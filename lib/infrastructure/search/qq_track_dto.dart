import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';

/// QQ 音乐搜索结果项 DTO（对应 searchService.ts searchQQ 的字段映射）。
class QqTrackDto {
  const QqTrackDto(this._json);

  final Map<String, Object?> _json;

  Track toTrack() => Track(
    id: _json['mid']?.toString() ?? '',
    name: _json['name']?.toString() ?? '',
    artists: _json['singer']?.toString() ?? '',
    album: _json['album']?.toString() ?? '',
    picUrl: _json['pic']?.toString() ?? '',
    source: MusicSource.qq,
  );
}
