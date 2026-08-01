import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';

/// 酷狗搜索结果项 DTO（对应 searchService.ts searchKugou 的字段映射）。
///
/// id 取 `hash:album_id`；hash 缺失时回退到 `emixsongid`。
class KugouTrackDto {
  const KugouTrackDto(this._json);

  final Map<String, Object?> _json;

  Track toTrack() {
    final hash = _json['hash']?.toString() ?? '';
    final albumId = _json['album_id']?.toString() ?? '';
    final id = hash.isNotEmpty
        ? '$hash:$albumId'
        : (_json['emixsongid']?.toString() ?? '');
    return Track(
      id: id,
      name: _json['name']?.toString() ?? '',
      artists: _json['singer']?.toString() ?? '',
      album: _json['album']?.toString() ?? '',
      picUrl: _json['pic']?.toString() ?? '',
      source: MusicSource.kugou,
    );
  }
}
