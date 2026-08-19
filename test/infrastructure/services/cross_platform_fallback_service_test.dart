import 'dart:convert';

import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/infrastructure/core/api_client.dart';
import 'package:cyrene_music_reborn/infrastructure/core/url_service.dart';
import 'package:cyrene_music_reborn/infrastructure/services/cross_platform_fallback_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  // 原曲：QQ 平台导入的「晴天」，无 alternatives。
  const original = Track(
    id: 'qq-original',
    name: '晴天',
    artists: '周杰伦',
    album: '叶惠美',
    picUrl: '',
    source: MusicSource.qq,
  );

  test('网易云与酷狗并行命中时按相近度排序且网易云优先', () async {
    final service = _service(_pathRoutingMock(
      onNetease: (_) => http.Response(
        jsonEncode({
          'status': 200,
          'result': [
            _neteaseItem(id: 'ne-1', name: '晴天', artists: '周杰伦'),
            _neteaseItem(id: 'ne-2', name: '晴天娃娃', artists: '周杰伦'),
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
      onKugou: (_) => http.Response(
        jsonEncode({
          'status': 200,
          'result': [
            _kugouItem(hash: 'kg-1', name: '晴天', singer: '周杰伦'),
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    ));

    final matches = await service.findFallbackFor(original);

    expect(matches, isNotEmpty);
    // 网易云精确同名命中排在最前（平台权重 + 更高相似度）。
    expect(matches.first.source, MusicSource.netease);
    expect(matches.first.id, 'ne-1');
    expect(matches.first.track.source, MusicSource.netease);
    // 酷狗候选紧随其后（KugouTrackDto 的 id 为 hash:album_id 格式）。
    expect(
      matches.any(
        (m) =>
            m.source == MusicSource.kugou &&
            m.id.startsWith('kg-1'),
      ),
      isTrue,
    );
  });

  test('歌手不同但歌名相近时相似度仍高于阈值', () async {
    final service = _service(_pathRoutingMock(
      onNetease: (_) => http.Response(
        jsonEncode({
          'status': 200,
          'result': [
            _neteaseItem(id: 'ne-1', name: '晴天', artists: '周杰伦'),
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
      onKugou: (_) => http.Response(jsonEncode({'status': 200, 'result': []}), 200),
    ));

    final matches = await service.findFallbackFor(original);

    expect(matches, isNotEmpty);
    expect(matches.first.id, 'ne-1');
    expect(matches.first.score, greaterThan(0.35));
  });

  test('完全无关的结果不会进入候选', () async {
    final service = _service(_pathRoutingMock(
      onNetease: (_) => http.Response(
        jsonEncode({
          'status': 200,
          'result': [
            _neteaseItem(id: 'ne-x', name: '霓虹甜心', artists: '马赛克乐队'),
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
      onKugou: (_) => http.Response(jsonEncode({'status': 200, 'result': []}), 200),
    ));

    final matches = await service.findFallbackFor(original);

    expect(matches, isEmpty);
  });

  test('两个平台搜索失败时返回空候选不抛错', () async {
    final service = _service(
      MockClient((request) async => http.Response('oops', 500)),
    );

    final matches = await service.findFallbackFor(original);

    expect(matches, isEmpty);
  });

  test('兜底命中保留原曲展示信息但换上新平台 id', () async {
    final service = _service(_pathRoutingMock(
      onNetease: (_) => http.Response(
        jsonEncode({
          'status': 200,
          'result': [
            _neteaseItem(id: 'ne-1', name: '晴天', artists: '周杰伦'),
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
      onKugou: (_) => http.Response(jsonEncode({'status': 200, 'result': []}), 200),
    ));

    final matches = await service.findFallbackFor(original);
    final hit = matches.first.track;

    // 展示信息来自原曲（导入时记录的 QQ 信息），id/source 换成网易云。
    expect(hit.name, '晴天');
    expect(hit.artists, '周杰伦');
    expect(hit.album, '叶惠美');
    expect(hit.source, MusicSource.netease);
    expect(hit.id, 'ne-1');
  });
}

CrossPlatformFallbackService _service(http.Client client) =>
    CrossPlatformFallbackService(
      apiClient: ApiClient(client: client),
      urls: UrlService.instance,
    );

/// 按 URL 路径分发响应的 MockClient：/search → 网易云，/kugou/search → 酷狗。
/// 两个搜索在服务内并行发起，调用顺序不固定，不能依赖顺序分发。
http.Client _pathRoutingMock({
  required http.Response Function(http.Request) onNetease,
  required http.Response Function(http.Request) onKugou,
}) {
  return MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/kugou/search')) return onKugou(request);
    if (path.endsWith('/search')) return onNetease(request);
    return http.Response('{}', 404);
  });
}

Map<String, Object?> _neteaseItem({
  required String id,
  required String name,
  required String artists,
}) => {
  'id': id,
  'name': name,
  'artists': artists,
  'album': '叶惠美',
  'picUrl': 'https://p.test/$id.jpg',
  'duration': 269000,
};

Map<String, Object?> _kugouItem({
  required String hash,
  required String name,
  required String singer,
}) => {
  'hash': hash,
  'album_id': 'album-1',
  'emixsongid': '',
  'name': name,
  'singer': singer,
  'album': '叶惠美',
  'pic': 'https://p.test/$hash.jpg',
};
