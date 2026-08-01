import 'dart:async';

import 'package:cyrene_music_reborn/application/search/search_controller.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/search.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/domain/search/search_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('新请求完成后只提交最后一次搜索结果', () async {
    final repository = _FakeSearchRepository();
    final controller = SearchController(repository);
    addTearDown(controller.dispose);

    final first = controller.search('第一首');
    final second = controller.search('第二首');
    repository.complete('第二首', [_track('2')]);
    await second;
    repository.complete('第一首', [_track('1')]);
    await first;

    expect(controller.state.keyword, '第二首');
    expect(controller.state.results.single.id, '2');
  });

  test('空关键词重置搜索状态', () async {
    final controller = SearchController(_FakeSearchRepository());
    addTearDown(controller.dispose);

    await controller.search('   ');

    expect(controller.state.results, isEmpty);
    expect(controller.state.keyword, isEmpty);
  });
}

class _FakeSearchRepository implements SearchRepository {
  final _requests = <String, _PendingRequest>{};

  @override
  Future<SearchResult> search(String keyword) {
    final request = _PendingRequest();
    _requests[keyword] = request;
    return request.completer.future;
  }

  void complete(String keyword, List<Track> results) => _requests[keyword]!
      .completer
      .complete(SearchResult(neteaseResults: results));
}

class _PendingRequest {
  final completer = Completer<SearchResult>();
}

Track _track(String id) => Track(
  id: id,
  name: '歌曲 $id',
  artists: '歌手',
  album: '专辑',
  picUrl: '',
  source: MusicSource.netease,
);
