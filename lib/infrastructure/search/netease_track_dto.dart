import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';

class NeteaseTrackDto {
  const NeteaseTrackDto(this._json);

  final Map<String, Object?> _json;

  Track toTrack() => Track(
    id: _json['id'].toString(),
    name: _json['name']?.toString() ?? '',
    artists: _json['artists']?.toString() ?? '',
    album: _json['album']?.toString() ?? '',
    picUrl: _json['picUrl']?.toString() ?? '',
    source: MusicSource.netease,
    duration: _durationFromMilliseconds(_json['duration']),
  );

  static Duration? _durationFromMilliseconds(Object? value) => switch (value) {
    final num milliseconds when milliseconds > 0 => Duration(
      milliseconds: milliseconds.round(),
    ),
    _ => null,
  };
}
