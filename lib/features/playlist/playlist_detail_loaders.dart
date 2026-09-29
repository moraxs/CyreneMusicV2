import '../../domain/models/discovery.dart';
import '../../domain/models/music_source.dart';
import '../../infrastructure/services/discovery_service.dart';

/// 给 [PlaylistDetailPage.loader] 用的取数函数：专辑与电台没有可复用的歌单 id，
/// 由详情页打开后自己调用，调用方不再先 await 曲目再跳转。
///
/// 取回空曲目时返回 null，详情页据此显示「加载失败 + 重试」。
Future<PlaylistDetail?> Function() spotifyAlbumLoader({
  required String albumId,
  required String name,
  required String coverUrl,
  String artists = '',
}) => () async {
  final tracks = await DiscoveryService.instance.getSpotifyAlbumTracks(albumId);
  return _assemble(
    tracks,
    name: name,
    coverUrl: coverUrl,
    description: artists,
    creator: artists,
    tags: const ['Spotify'],
  );
};

/// 单曲电台：每次调用都会重新生成，所以详情页下拉刷新会换一批。
Future<PlaylistDetail?> Function() spotifyRadioLoader({
  required String seedId,
  required String name,
  required String coverUrl,
  String description = '',
}) => () async {
  final tracks = await DiscoveryService.instance.getSpotifyRadio(seedId);
  return _assemble(
    tracks,
    name: name,
    coverUrl: coverUrl,
    description: description,
    creator: 'Spotify',
    tags: const ['Spotify', '电台'],
  );
};

PlaylistDetail? _assemble(
  List<ToplistTrack> tracks, {
  required String name,
  required String coverUrl,
  required String description,
  required String creator,
  required List<String> tags,
}) {
  if (tracks.isEmpty) return null;
  return PlaylistDetail(
    id: 0,
    name: name,
    coverImgUrl: coverUrl,
    description: description,
    source: MusicSource.spotify,
    tracks: tracks,
    playCount: 0,
    creator: creator,
    trackCount: tracks.length,
    createTime: 0,
    updateTime: 0,
    tags: tags,
  );
}
