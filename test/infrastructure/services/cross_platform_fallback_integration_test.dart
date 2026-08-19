import 'dart:convert';

import 'package:cyrene_music_reborn/domain/models/audio_quality.dart';
import 'package:cyrene_music_reborn/domain/models/audio_source_config.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_cache.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_source_preferences_store.dart';
import 'package:cyrene_music_reborn/infrastructure/core/api_client.dart';
import 'package:cyrene_music_reborn/infrastructure/core/url_service.dart';
import 'package:cyrene_music_reborn/infrastructure/services/configured_audio_source_resolver.dart';
import 'package:cyrene_music_reborn/infrastructure/services/cross_platform_fallback_service.dart';
import 'package:cyrene_music_reborn/infrastructure/services/playback_url_resolver_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 复现用户场景：QQ 歌单曲目 → QQ /qq/song 返回 status:200 但 music_urls 为空
/// （普通账号无 VIP，无直链）→ 期望触发网易云/酷狗搜索兜底并解析出直链。
void main() {
  test('QQ 歌单曲目无直链时触发网易云/酷狗搜索兜底', () async {
    final client = MockClient((request) async {
      final path = request.url.path;
      // QQ 歌曲详情：status 200 但 music_urls 空（与用户抓包一致）。
      if (path.endsWith('/qq/song')) {
        return http.Response(
          jsonEncode({
            'status': 200,
            'song': {
              'name': '光年之外',
              'album': '光年之外',
              'singer': 'G.E.M. 邓紫棋',
              'mid': '002E3MtF0IAMMY',
              'id': 200255722,
            },
            'lyric': {'lyric': '[00:01]光年之外', 'tylyric': ''},
            'music_urls': {},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      // 网易云搜索：返回可播放的候选。
      if (path.endsWith('/search')) {
        return http.Response(
          jsonEncode({
            'status': 200,
            'result': [
              {
                'id': 'netease-id-1',
                'name': '光年之外',
                'artists': 'G.E.M. 邓紫棋',
                'album': '光年之外',
                'picUrl': '',
                'duration': 269000,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      // 酷狗搜索：返回可播放的候选。
      if (path.endsWith('/kugou/search')) {
        return http.Response(
          jsonEncode({
            'status': 200,
            'result': [
              {
                'hash': 'kugou-hash-1',
                'album_id': 'album-1',
                'name': '光年之外',
                'singer': 'G.E.M. 邓紫棋',
                'album': '光年之外',
                'pic': '',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      // 网易云取链：返回可播放 URL。
      if (path.endsWith('/song')) {
        return http.Response(
          jsonEncode({'status': 200, 'url': 'https://cdn.test/netease-id-1.mp3'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      // 酷狗取链：返回可播放 URL。
      if (path.endsWith('/kugou/song')) {
        return http.Response(
          jsonEncode({
            'status': 200,
            'song': {'url': 'https://cdn.test/kugou-hash-1.mp3'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      // 网易云歌词。
      if (path.contains('/lyrics/netease')) {
        return http.Response(
          jsonEncode({'data': {'lyric': '[00:01]光年之外', 'tlyric': ''}}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });
    final apiClient = ApiClient(client: client);
    final sourceClient = PlaybackUrlResolverService(
      apiClient: apiClient,
      urls: UrlService.instance,
    );
    final resolver = ConfiguredAudioSourceResolver(
      preferences: _FakePreferencesStore([
        const AudioSourceConfig(
          id: 'omni',
          type: AudioSourceType.omniParse,
          name: 'OmniParse',
          url: 'https://music.nekofun.top',
        ),
      ]),
      sourceClient: sourceClient,
      cache: const _EmptyAudioCache(),
      crossPlatformFallback: CrossPlatformFallbackService(
        apiClient: apiClient,
        urls: UrlService.instance,
      ),
    );
    // 导入的 QQ 歌单曲目：source=qq，无 alternatives。
    const track = Track(
      id: '200255722',
      name: '光年之外',
      artists: 'G.E.M. 邓紫棋',
      album: '光年之外',
      picUrl: '',
      source: MusicSource.qq,
    );

    final resolved = await resolver.resolve(track);

    expect(resolved.candidates, isNotEmpty);
    // 兜底候选来自网易云（优先级最高），且标记了 fallbackFrom。
    final candidate = resolved.candidates.first;
    expect(candidate.fallbackFrom, isNotNull);
    expect(candidate.fallbackFrom!.source, MusicSource.qq);
    expect(candidate.track.source, MusicSource.netease);
    expect(candidate.track.playbackUrl, isNotNull);
  });
}

class _FakePreferencesStore implements AudioSourcePreferencesStore {
  _FakePreferencesStore(this.sources);

  final List<AudioSourceConfig> sources;

  @override
  Future<AudioSourcePreferences> read() async =>
      AudioSourcePreferences(sources: sources, quality: AudioQuality.lossless);

  @override
  Future<void> write(AudioSourcePreferences preferences) async {}
}

class _EmptyAudioCache implements AudioCache {
  const _EmptyAudioCache();

  @override
  Future<Uri?> find(Track track, AudioQuality quality) async => null;
}
