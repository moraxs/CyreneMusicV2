import 'package:cyrene_music_reborn/domain/models/audio_quality.dart';
import 'package:cyrene_music_reborn/domain/models/audio_source_config.dart';
import 'package:cyrene_music_reborn/domain/models/lyric_data.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_cache.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_source_preferences_store.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_source_resolver.dart';
import 'package:cyrene_music_reborn/infrastructure/services/configured_audio_source_resolver.dart';
import 'package:cyrene_music_reborn/infrastructure/services/playback_url_resolver_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('按音源优先级和跨平台候选继续解析并附加歌词', () async {
    final sourceClient = _FakePlaybackSourceClient()
      ..failures.add('first:netease');
    final resolver = ConfiguredAudioSourceResolver(
      preferences: _FakePreferencesStore([
        _config('first', ['netease']),
        _config('second', ['qq']),
      ]),
      sourceClient: sourceClient,
      cache: const _EmptyAudioCache(),
    );
    final track = _track().copyWith(
      alternatives: const [TrackSourceRef(id: 'qq-id', source: MusicSource.qq)],
    );

    final resolved = await resolver.resolve(track);
    final candidate = resolved.candidates.single;

    expect(sourceClient.calls, ['first:netease', 'second:qq']);
    expect(candidate.sourceId, 'second');
    expect(candidate.track.source, MusicSource.qq);
    expect(candidate.track.id, 'qq-id');
    expect(candidate.track.lyric, '[00:01]歌词');
    expect(
      candidate.track.playbackUrl,
      Uri.parse('https://cdn.test/qq-id.mp3'),
    );
  });

  test('中途平台命中后短路，不再请求更低优先级平台', () async {
    final sourceClient = _FakePlaybackSourceClient()
      ..failures.add('omni:netease');
    final resolver = ConfiguredAudioSourceResolver(
      preferences: _FakePreferencesStore([_config('omni', [])]),
      sourceClient: sourceClient,
      cache: const _EmptyAudioCache(),
    );
    // 聚合曲目：网易云为主源，酷狗/QQ/酷我为 alternatives（无版权场景）。
    final track = _track().copyWith(
      alternatives: const [
        TrackSourceRef(id: 'kugou-id', source: MusicSource.kugou),
        TrackSourceRef(id: 'qq-id', source: MusicSource.qq),
        TrackSourceRef(id: 'kuwo-id', source: MusicSource.kuwo),
      ],
    );

    final resolved = await resolver.resolve(track);
    final candidate = resolved.candidates.single;

    // 网易云无版权失败 → 酷狗命中即停，QQ/酷我不再被请求。
    expect(sourceClient.calls, ['omni:netease', 'omni:kugou']);
    expect(candidate.sourceId, 'omni');
    expect(candidate.track.source, MusicSource.kugou);
    expect(candidate.track.id, 'kugou-id');
  });

  test('所有解析失败时返回包含原因的领域错误', () async {
    final sourceClient = _FakePlaybackSourceClient()
      ..failures.add('first:netease');
    final resolver = ConfiguredAudioSourceResolver(
      preferences: _FakePreferencesStore([
        _config('first', ['netease']),
      ]),
      sourceClient: sourceClient,
      cache: const _EmptyAudioCache(),
    );

    expect(
      resolver.resolve(_track()),
      throwsA(
        isA<AudioSourceResolutionFailure>().having(
          (error) => error.causes,
          'causes',
          isNotEmpty,
        ),
      ),
    );
  });

  test('禁用音源不会进入解析链路', () async {
    final sourceClient = _FakePlaybackSourceClient();
    final resolver = ConfiguredAudioSourceResolver(
      preferences: _FakePreferencesStore([
        _config('disabled', ['netease'], isEnabled: false),
        _config('enabled', ['netease']),
      ]),
      sourceClient: sourceClient,
      cache: const _EmptyAudioCache(),
    );

    final resolved = await resolver.resolve(_track());

    expect(sourceClient.calls, ['enabled:netease']);
    expect(resolved.candidates.single.sourceId, 'enabled');
  });

  test('音频命中缓存时第一候选仍会回填解析结果中的歌词', () async {
    final sourceClient = _FakePlaybackSourceClient()
      ..fetchedLyrics = null
      ..resolvedLyrics = const LyricData(
        lyric: '[00:01]第二首歌词',
        yrc: '[1000,1000](1000,1000,0)第二首歌词',
      );
    final resolver = ConfiguredAudioSourceResolver(
      preferences: _FakePreferencesStore([
        _config('cached-source', ['netease']),
      ]),
      sourceClient: sourceClient,
      cache: const _HitAudioCache(),
    );

    final resolved = await resolver.resolve(_track());
    final cachedCandidate = resolved.candidates.first;

    expect(cachedCandidate.sourceId, 'cached-source:cache');
    expect(cachedCandidate.track.playbackUrl, Uri.parse('file:///cached.mp3'));
    expect(cachedCandidate.track.lyric, '[00:01]第二首歌词');
    expect(cachedCandidate.track.yrc, isNotEmpty);
  });

  test('Android 未启用 LxMusic 运行时时返回受控解析错误', () async {
    final service = PlaybackUrlResolverService();

    expect(
      service.resolveUrlFromSource(
        _track(),
        _config('lx', ['netease'], type: AudioSourceType.lxMusic),
        AudioQuality.exHigh,
      ),
      throwsA(
        isA<AudioSourceError>().having(
          (error) => error.message,
          'message',
          contains('未启用 LxMusic'),
        ),
      ),
    );
  });
}

Track _track() => const Track(
  id: 'netease-id',
  name: '同一首歌',
  artists: '歌手',
  album: '专辑',
  picUrl: '',
  source: MusicSource.netease,
);

AudioSourceConfig _config(
  String id,
  List<String> platforms, {
  AudioSourceType type = AudioSourceType.omniParse,
  bool isEnabled = true,
}) => AudioSourceConfig(
  id: id,
  type: type,
  name: id,
  url: 'https://source.test',
  apiKey: '',
  isEnabled: isEnabled,
  supportedPlatforms: platforms,
  version: '',
  author: '',
  description: '',
  scriptSource: '',
  scriptContent: '',
  urlPathTemplate: '',
);

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

class _HitAudioCache implements AudioCache {
  const _HitAudioCache();

  @override
  Future<Uri?> find(Track track, AudioQuality quality) async =>
      Uri.parse('file:///cached.mp3');
}

class _FakePlaybackSourceClient implements PlaybackSourceClient {
  final failures = <String>{};
  final calls = <String>[];
  LyricData? fetchedLyrics = const LyricData(lyric: '[00:01]歌词');
  LyricData? resolvedLyrics;

  @override
  Future<ResolvedPlayback> resolveUrlFromSource(
    Track track,
    AudioSourceConfig configSource,
    AudioQuality quality,
  ) async {
    final call = '${configSource.id}:${track.source.wireName}';
    calls.add(call);
    if (failures.contains(call)) throw AudioSourceError('不可用');
    return ResolvedPlayback(
      url: 'https://cdn.test/${track.id}.mp3',
      lyrics: resolvedLyrics,
    );
  }

  @override
  Future<LyricData?> fetchLyrics(Track track) async => fetchedLyrics;
}
