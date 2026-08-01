import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';

/// Qishui 搜索结果项 DTO（对应 searchService.ts searchQishui 的字段映射）。
///
/// `title` → name，`duration` 为毫秒，转为 [Duration]。
class QishuiTrackDto {
  const QishuiTrackDto(this._json);

  final Map<String, Object?> _json;

  Track toTrack() => Track(
    id: _json['id']?.toString() ?? '',
    name: _json['title']?.toString() ?? '',
    artists: _json['artist']?.toString() ?? '',
    album: _json['album']?.toString() ?? '',
    picUrl: _json['pic']?.toString() ?? '',
    source: MusicSource.qishui,
    duration: _durationFromMilliseconds(_json['duration']),
  );

  static Duration? _durationFromMilliseconds(Object? value) => switch (value) {
    final num milliseconds when milliseconds > 0 => Duration(
      milliseconds: milliseconds.round(),
    ),
    _ => null,
  };
}
