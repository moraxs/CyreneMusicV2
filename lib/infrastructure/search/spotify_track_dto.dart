import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';

/// Spotify 搜索结果项 DTO（对应 searchService.ts searchSpotify 的字段映射）。
///
/// `artists` 为对象数组，拼接为逗号分隔字符串；
/// `duration` 为毫秒，转为 [Duration]。
class SpotifyTrackDto {
  const SpotifyTrackDto(this._json);

  final Map<String, Object?> _json;

  Track toTrack() {
    final artistsRaw = _json['artists'];
    final artists = artistsRaw is List
        ? artistsRaw
              .map((a) => a is Map ? a['name']?.toString() ?? '' : a.toString())
              .where((s) => s.isNotEmpty)
              .join(', ')
        : '';
    final album = _json['album'];
    final albumName = album is Map ? album['name']?.toString() ?? '' : '';
    final coverArt = album is Map ? album['coverArt']?.toString() ?? '' : '';
    return Track(
      id: _json['id']?.toString() ?? '',
      name: _json['name']?.toString() ?? '',
      artists: artists,
      album: albumName,
      picUrl: coverArt,
      source: MusicSource.spotify,
      duration: _durationFromMilliseconds(_json['duration']),
    );
  }

  static Duration? _durationFromMilliseconds(Object? value) => switch (value) {
    final num milliseconds when milliseconds > 0 => Duration(
      milliseconds: milliseconds.round(),
    ),
    _ => null,
  };
}
