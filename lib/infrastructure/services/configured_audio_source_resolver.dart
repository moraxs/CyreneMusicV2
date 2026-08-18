import '../../domain/models/audio_source_config.dart';
import '../../domain/models/lyric_data.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';
import '../../domain/playback/audio_cache.dart';
import '../../domain/playback/audio_source_preferences_store.dart';
import '../../domain/playback/audio_source_resolver.dart';
import 'playback_url_resolver_service.dart';

class ConfiguredAudioSourceResolver implements AudioSourceResolver {
  factory ConfiguredAudioSourceResolver({
    required AudioSourcePreferencesStore preferences,
    required PlaybackSourceClient sourceClient,
    required AudioCache cache,
  }) => ConfiguredAudioSourceResolver._(preferences, sourceClient, cache);

  ConfiguredAudioSourceResolver._(
    this._preferences,
    this._sourceClient,
    this._cache,
  );

  final AudioSourcePreferencesStore _preferences;
  final PlaybackSourceClient _sourceClient;
  final AudioCache _cache;

  @override
  Future<ResolvedAudioSources> resolve(
    Track track, {
    Set<String>? exclude,
  }) async {
    if (track.playbackUrl != null) {
      return ResolvedAudioSources([
        PlaybackCandidate(track: track, sourceId: 'embedded'),
      ]);
    }

    final excluded = exclude ?? const <String>{};
    final preferences = await _preferences.read();
    final enabledSources = preferences.sources
        .where((source) => source.isEnabled)
        .toList(growable: false);
    final failures = <String>[];

    for (final config in enabledSources) {
      for (final sourceRef in track.sourceCandidates) {
        if (excluded.contains(sourceRef.source.wireName)) continue;
        if (!_supports(config, sourceRef.source)) continue;
        final sourceTrack = track.withSource(sourceRef);
        // 网易云专属音质（higher/dolby/jyeffect/sky/jymaster）仅对网易云
        // 生效；其它来源回落到极高音质，避免把网易云 level 透传给别的后端。
        final quality = preferences.quality.effectiveFor(sourceRef.source);

        final cached = await _cache.find(sourceTrack, quality);
        try {
          final resolved = await _sourceClient.resolveUrlFromSource(
            sourceTrack,
            config,
            quality,
          );
          final lyric =
              resolved.lyrics ??
              await _sourceClient.fetchLyrics(sourceTrack) ??
              const LyricData();
          // 主候选为当前平台；若命中缓存则缓存文件优先（同样回填歌词）。
          final candidates = <PlaybackCandidate>[];
          if (cached != null) {
            candidates.add(
              PlaybackCandidate(
                track: sourceTrack.copyWith(
                  playbackUrl: cached,
                  lyric: lyric.lyric,
                  yrc: lyric.yrc,
                  tlyric: lyric.tlyric,
                  ytlrc: lyric.ytlrc,
                ),
                sourceId: '${config.id}:cache',
              ),
            );
          }
          candidates.add(
            PlaybackCandidate(
              track: sourceTrack.copyWith(
                playbackUrl: _parsePlaybackUri(resolved.url),
                lyric: lyric.lyric,
                yrc: lyric.yrc,
                tlyric: lyric.tlyric,
                ytlrc: lyric.ytlrc,
              ),
              sourceId: config.id,
            ),
          );
          final fallback = resolved.fallbackUrl;
          if (fallback != null && fallback.isNotEmpty) {
            candidates.add(
              PlaybackCandidate(
                track: sourceTrack.copyWith(
                  playbackUrl: _parsePlaybackUri(fallback),
                  lyric: lyric.lyric,
                  yrc: lyric.yrc,
                  tlyric: lyric.tlyric,
                  ytlrc: lyric.ytlrc,
                ),
                sourceId: '${config.id}:fallback',
              ),
            );
          }
          // 短路：首个能解析出可播放候选的「配置 × 平台」一到手即返回，不把
          // 全部平台都请求一遍（例如晴天：网易云无版权跳过、酷狗可播，不应再
          // 请求 QQ/酷我/Apple）。调用方（playTrack）加载失败后会用 exclude
          // 排除该平台再次调用，从而逐平台惰性回退。
          return ResolvedAudioSources(candidates);
        } catch (error) {
          failures.add('${config.name}/${sourceRef.source.wireName}: $error');
          // 当前平台 URL 解析失败（如版权失效）但本地已有缓存：仍用缓存兜底
          // 并尽量补一次歌词。若缓存加载也失败，调用方会排除该平台继续回退。
          if (cached != null) {
            final lyric =
                await _sourceClient.fetchLyrics(sourceTrack) ?? const LyricData();
            return ResolvedAudioSources([
              PlaybackCandidate(
                track: sourceTrack.copyWith(
                  playbackUrl: cached,
                  lyric: lyric.lyric,
                  yrc: lyric.yrc,
                  tlyric: lyric.tlyric,
                  ytlrc: lyric.ytlrc,
                ),
                sourceId: '${config.id}:cache',
              ),
            ]);
          }
        }
      }
    }

    throw AudioSourceResolutionFailure(
      enabledSources.isEmpty ? '尚未启用可用音源。' : '所有音源解析均失败。',
      causes: failures,
    );
  }

  bool _supports(AudioSourceConfig config, MusicSource source) {
    if (source == MusicSource.local) return false;
    final configured = config.supportedPlatforms;
    if (configured.isNotEmpty) return configured.contains(source.wireName);
    return switch (config.type) {
      AudioSourceType.omniParse => true,
      AudioSourceType.lxMusic => const {
        MusicSource.netease,
        MusicSource.qq,
        MusicSource.kugou,
        MusicSource.kuwo,
      }.contains(source),
    };
  }

  Uri _parsePlaybackUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) {
      throw AudioSourceError('音源返回了无效播放地址');
    }
    return uri;
  }
}
