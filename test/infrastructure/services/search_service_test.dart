import 'dart:convert';

import 'package:cyrene_music_reborn/domain/models/audio_source_config.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_source_preferences_store.dart';
import 'package:cyrene_music_reborn/infrastructure/core/api_client.dart';
import 'package:cyrene_music_reborn/infrastructure/services/search_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('合并同名歌曲并保留跨平台播放候选', () async {
    final repository = SearchService(
      apiClient: ApiClient(client: MockClient(_responseFor)),
      preferences: const _SearchPreferences(),
    );

    final result = await repository.search('同一首歌');
    final merged = result.mergedTracks.single;

    expect(result.neteaseResults, hasLength(1));
    expect(result.qqResults, hasLength(1));
    expect(merged.id, 'netease-id');
    expect(merged.alternatives.single.id, 'qq-id');
    expect(merged.alternatives.single.source.wireName, 'qq');
  });

  test('单个平台失败不会丢弃其他平台结果', () async {
    final repository = SearchService(
      apiClient: ApiClient(
        client: MockClient((request) {
          if (request.url.path == '/qq/search') {
            return Future.value(_jsonResponse('{"message":"繁忙"}', 503));
          }
          return _responseFor(request);
        }),
      ),
      preferences: const _SearchPreferences(),
    );

    final result = await repository.search('同一首歌');

    expect(result.neteaseResults, hasLength(1));
    expect(result.qqResults, isEmpty);
    expect(result.qqError, isNotNull);
    expect(result.hasPartialFailure, isTrue);
    expect(result.aggregatedError, isNotNull);
    expect(result.aggregatedError, contains('QQ 音乐'));
  });

  test('聚合搜索按「网易云 > 酷狗 > QQ」优先级合并并保留回退源', () async {
    final repository = SearchService(
      apiClient: ApiClient(client: MockClient(_responseForAggregated)),
      preferences: const _AggregatedPreferences(),
    );

    final result = await repository.search('同一首歌');
    final merged = result.aggregatedTracks.single;

    expect(merged.id, 'netease-id');
    expect(merged.alternatives, hasLength(2));
    expect(merged.alternatives[0].source, MusicSource.kugou);
    expect(merged.alternatives[1].source, MusicSource.qq);
  });
}

Future<http.Response> _responseFor(http.Request request) async {
  return switch (request.url.path) {
    '/search' => _jsonResponse(
      '{"status":200,"result":[{"id":"netease-id","name":"同一首歌","artists":"歌手","album":"专辑","picUrl":""}]}',
      200,
    ),
    '/qq/search' => _jsonResponse(
      '{"status":200,"result":[{"mid":"qq-id","name":"同一首歌","singer":"歌手","album":"专辑","pic":""}]}',
      200,
    ),
    '/artist/search' => _jsonResponse('{"status":200,"result":[]}', 200),
    _ => _jsonResponse('{"status":404}', 404),
  };
}

Future<http.Response> _responseForAggregated(http.Request request) async {
  return switch (request.url.path) {
    '/search' => _jsonResponse(
      '{"status":200,"result":[{"id":"netease-id","name":"同一首歌","artists":"歌手","album":"专辑","picUrl":""}]}',
      200,
    ),
    '/kugou/search' => _jsonResponse(
      '{"status":200,"result":[{"hash":"kugou-hash","album_id":"k1","name":"同一首歌","singer":"歌手","album":"专辑","pic":""}]}',
      200,
    ),
    '/qq/search' => _jsonResponse(
      '{"status":200,"result":[{"mid":"qq-id","name":"同一首歌","singer":"歌手","album":"专辑","pic":""}]}',
      200,
    ),
    '/artist/search' => _jsonResponse('{"status":200,"result":[]}', 200),
    _ => _jsonResponse('{"status":404}', 404),
  };
}

http.Response _jsonResponse(String body, int statusCode) => http.Response.bytes(
  utf8.encode(body),
  statusCode,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

class _SearchPreferences implements AudioSourcePreferencesStore {
  const _SearchPreferences();

  @override
  Future<AudioSourcePreferences> read() async => AudioSourcePreferences(
    sources: [
      AudioSourceConfig(
        id: 'test',
        type: AudioSourceType.omniParse,
        name: 'test',
        url: 'https://music.nekofun.top',
        apiKey: '',
        supportedPlatforms: ['netease', 'qq'],
        version: '',
        author: '',
        description: '',
        scriptSource: '',
        scriptContent: '',
        urlPathTemplate: '',
      ),
    ],
  );

  @override
  Future<void> write(AudioSourcePreferences preferences) async {}
}

class _AggregatedPreferences implements AudioSourcePreferencesStore {
  const _AggregatedPreferences();

  @override
  Future<AudioSourcePreferences> read() async => AudioSourcePreferences(
    sources: [
      AudioSourceConfig(
        id: 'test',
        type: AudioSourceType.omniParse,
        name: 'test',
        url: 'https://music.nekofun.top',
        apiKey: '',
        supportedPlatforms: ['netease', 'kugou', 'qq'],
        version: '',
        author: '',
        description: '',
        scriptSource: '',
        scriptContent: '',
        urlPathTemplate: '',
      ),
    ],
  );

  @override
  Future<void> write(AudioSourcePreferences preferences) async {}
}
