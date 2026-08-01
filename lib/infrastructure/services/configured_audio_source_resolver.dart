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
  Future<ResolvedAudioSources> resolve(Track track) async {
    if (track.playbackUrl != null) {
      return ResolvedAudioSources([
        PlaybackCandidate(track: track, sourceId: 'embedded'),
      ]);
    }

    final preferences = await _preferences.read();
    final enabledSources = preferences.sources
        .where((source) => source.isEnabled)
        .toList(growable: false);
    final candidates = <PlaybackCandidate>[];
    final failures = <String>[];

    for (final config in enabledSources) {
      for (final sourceRef in track.sourceCandidates) {
        if (!_supports(config, sourceRef.source)) continue;
        final sourceTrack = track.withSource(sourceRef);

        final cached = await _cache.find(sourceTrack, preferences.quality);
        if (cached != null) {
          candidates.add(
            PlaybackCandidate(
              track: sourceTrack.copyWith(playbackUrl: cached),
              sourceId: '${config.id}:cache',
            ),
          );
        }

        try {
          final resolved = await _sourceClient.resolveUrlFromSource(
            sourceTrack,
            config,
            preferences.quality,
          );
          final lyric =
              resolved.lyrics ??
              await _sourceClient.fetchLyrics(sourceTrack) ??
              const LyricData();
          final playable = sourceTrack.copyWith(
            playbackUrl: _parsePlaybackUri(resolved.url),
            lyric: lyric.lyric,
            yrc: lyric.yrc,
            tlyric: lyric.tlyric,
            ytlrc: lyric.ytlrc,
          );
          candidates.add(
            PlaybackCandidate(track: playable, sourceId: config.id),
          );

          final fallback = resolved.fallbackUrl;
          if (fallback != null && fallback.isNotEmpty) {
            candidates.add(
              PlaybackCandidate(
                track: playable.copyWith(
                  playbackUrl: _parsePlaybackUri(fallback),
                ),
                sourceId: '${config.id}:fallback',
              ),
            );
          }
        } catch (error) {
          failures.add('${config.name}/${sourceRef.source.wireName}: $error');
        }
      }
    }

    if (candidates.isEmpty) {
      throw AudioSourceResolutionFailure(
        enabledSources.isEmpty ? '尚未启用可用音源。' : '所有音源解析均失败。',
        causes: failures,
      );
    }
    return ResolvedAudioSources(List.unmodifiable(candidates));
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
