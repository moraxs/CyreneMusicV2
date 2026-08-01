import 'dart:async';

import 'package:cyrene_music_reborn/application/discovery/discover_controller.dart';
import 'package:cyrene_music_reborn/domain/discovery/discover_repository.dart';
import 'package:cyrene_music_reborn/domain/models/discovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('初次加载同时获取分类和歌单', () async {
    final repository = _FakeDiscoverRepository();
    final controller = DiscoverController(repository);
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.state.tags.single.name, '流行');
    expect(controller.state.playlists.single.name, '全部歌单精选');
    expect(controller.state.isInitialLoading, isFalse);
  });

  test('快速切换分类只保留最后一次结果', () async {
    final repository = _ControlledDiscoverRepository();
    final controller = DiscoverController(repository);
    addTearDown(controller.dispose);

    final first = controller.selectCategory('流行');
    final second = controller.selectCategory('摇滚');
    repository.complete('摇滚', [_playlist(2, '摇滚精选')]);
    await second;
    repository.complete('流行', [_playlist(1, '流行精选')]);
    await first;

    expect(controller.state.selectedCategory, '摇滚');
    expect(controller.state.playlists.single.name, '摇滚精选');
  });
}

class _FakeDiscoverRepository implements DiscoverRepository {
  @override
  Future<List<DiscoveryPlaylist>> getPlaylists({
    String category = '全部歌单',
    bool forceRefresh = false,
  }) async => [_playlist(1, '$category精选')];

  @override
  Future<List<DiscoveryTag>> getTags() async => const [
    DiscoveryTag(id: 1, name: '流行', category: 0),
  ];
}

class _ControlledDiscoverRepository implements DiscoverRepository {
  final requests = <String, Completer<List<DiscoveryPlaylist>>>{};

  @override
  Future<List<DiscoveryPlaylist>> getPlaylists({
    String category = '全部歌单',
    bool forceRefresh = false,
  }) {
    final completer = Completer<List<DiscoveryPlaylist>>();
    requests[category] = completer;
    return completer.future;
  }

  @override
  Future<List<DiscoveryTag>> getTags() async => const [];

  void complete(String category, List<DiscoveryPlaylist> playlists) {
    requests[category]!.complete(playlists);
  }
}

DiscoveryPlaylist _playlist(int id, String name) => DiscoveryPlaylist(
  id: id,
  name: name,
  coverImgUrl: '',
  creatorNickname: 'Cyrene',
  playCount: 100,
  trackCount: 20,
);
