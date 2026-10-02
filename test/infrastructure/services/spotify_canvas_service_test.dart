import 'dart:convert';

import 'package:cyrene_music_reborn/infrastructure/core/api_client.dart';
import 'package:cyrene_music_reborn/infrastructure/services/spotify_canvas_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('fetchVideoUrl 取回后能完成，并发与重复请求只打一次', () async {
    var calls = 0;
    final api = ApiClient(
      client: MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'status': 200,
            'data': {'type': 'VIDEO_LOOPING_RANDOM', 'url': 'https://canvaz.scdn.co/x.mp4'},
          }),
          200,
        );
      }),
    );
    final service = SpotifyCanvasService(apiClient: api);

    final results = await Future.wait([
      service.fetchVideoUrl('abc'),
      service.fetchVideoUrl('abc'),
    ]).timeout(const Duration(seconds: 2));
    expect(results, ['https://canvaz.scdn.co/x.mp4', 'https://canvaz.scdn.co/x.mp4']);
    expect(await service.fetchVideoUrl('abc'), 'https://canvaz.scdn.co/x.mp4');
    expect(calls, 1);
  });

  test('404 记为没有 Canvas，静图类型不放行', () async {
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/none')) return http.Response('', 404);
        return http.Response(
          jsonEncode({'data': {'type': 'IMAGE', 'url': 'https://canvaz.scdn.co/x.jpg'}}),
          200,
        );
      }),
    );
    final service = SpotifyCanvasService(apiClient: api);
    expect(await service.fetchVideoUrl('none').timeout(const Duration(seconds: 2)), isNull);
    expect(await service.fetchVideoUrl('img').timeout(const Duration(seconds: 2)), isNull);
  });
}
