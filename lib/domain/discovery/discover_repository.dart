import '../../domain/models/discovery.dart';

abstract interface class DiscoverRepository {
  Future<List<DiscoveryTag>> getTags();

  Future<List<DiscoveryPlaylist>> getPlaylists({
    String category = '全部歌单',
    bool forceRefresh = false,
  });
}
