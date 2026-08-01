import 'package:cyrene_music_reborn/app/music_api_configuration.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/domain/search/search_repository.dart';
import 'package:cyrene_music_reborn/infrastructure/search/netease_music_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final configuration = MusicApiConfiguration(
    baseUrl: 'https://api.example.test',
  );

  test('网易云搜索响应映射为领域曲目', () async {
    final repository = NeteaseMusicRepository(
      configuration: configuration,
      client: MockClient((request) async {
        expect(request.url.path, '/search');
        expect(request.method, 'POST');
        expect(request.body, contains('keywords=%E6%B5%8B%E8%AF%95'));
        return http.Response(
          '{"status":200,"result":[{"id":7,"name":"测试","artists":"歌手","album":"专辑","picUrl":"cover"}]}',
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final result = await repository.search('测试');
    final tracks = result.neteaseResults;

    expect(tracks, hasLength(1));
    expect(tracks.single.id, '7');
    expect(tracks.single.source, MusicSource.netease);
  });

  test('解析播放地址会补全歌词并返回新曲目快照', () async {
    final repository = NeteaseMusicRepository(
      configuration: configuration,
      client: MockClient(
        (request) async => http.Response(
          '{"status":200,"url":"https://cdn.example.test/7.mp3","lyric":"[00:01]歌词"}',
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );
    const track = Track(
      id: '7',
      name: '测试',
      artists: '歌手',
      album: '专辑',
      picUrl: '',
      source: MusicSource.netease,
    );

    final resolved = await repository.resolve(track);
    final resolvedTrack = resolved.candidates.single.track;

    expect(
      resolvedTrack.playbackUrl,
      Uri.parse('https://cdn.example.test/7.mp3'),
    );
    expect(resolvedTrack.lyric, '[00:01]歌词');
    expect(resolvedTrack, track);
  });

  test('非成功响应转换为可展示的搜索错误', () async {
    final repository = NeteaseMusicRepository(
      configuration: configuration,
      client: MockClient(
        (request) async => http.Response(
          '{"message":"服务繁忙"}',
          503,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );

    expect(repository.search('测试'), throwsA(isA<SearchFailure>()));
  });
}
