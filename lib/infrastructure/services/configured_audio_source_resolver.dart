import '../../domain/models/audio_source_config.dart';
import '../../domain/models/lyric_data.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';
import '../../domain/playback/audio_cache.dart';
import '../../domain/playback/audio_source_preferences_store.dart';
import '../../domain/playback/audio_source_resolver.dart';
import 'cross_platform_fallback_service.dart';
import 'playback_url_resolver_service.dart';

class ConfiguredAudioSourceResolver implements AudioSourceResolver {
  factory ConfiguredAudioSourceResolver({
    required AudioSourcePreferencesStore preferences,
    required PlaybackSourceClient sourceClient,
    required AudioCache cache,
    CrossPlatformFallbackFinder? crossPlatformFallback,
  }) => ConfiguredAudioSourceResolver._(
    preferences,
    sourceClient,
    cache,
    crossPlatformFallback,
  );

  ConfiguredAudioSourceResolver._(
    this._preferences,
    this._sourceClient,
    this._cache,
    this._crossPlatformFallback,
  );

  final AudioSourcePreferencesStore _preferences;
  final PlaybackSourceClient _sourceClient;
  final AudioCache _cache;
  final CrossPlatformFallbackFinder? _crossPlatformFallback;

  /// 已尝试过跨平台兜底的曲目 key（会话级），避免对同一曲目反复搜索。
  final Set<String> _crossPlatformTried = {};

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
                  romaji: lyric.romaji,
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
                romaji: lyric.romaji,
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
                  romaji: lyric.romaji,
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
                  romaji: lyric.romaji,
                ),
                sourceId: '${config.id}:cache',
              ),
            ]);
          }
        }
      }
    }

    // 原平台（及 alternatives）全部解析失败。对无 alternatives 的曲目
    // （即导入歌单的曲目）做跨平台兜底：并行搜网易云+酷狗，换平台取流。
    final fallbackResolved = await _resolveCrossPlatformFallback(
      track,
      enabledSources,
      preferences,
      excluded,
      failures,
    );
    if (fallbackResolved != null) return fallbackResolved;

    throw AudioSourceResolutionFailure(
      enabledSources.isEmpty ? '尚未启用可用音源。' : '所有音源解析均失败。',
      causes: failures,
    );
  }

  /// 跨平台兜底：仅对无 alternatives 的曲目（导入歌单曲目）触发一次。
  ///
  /// 并行搜索网易云与酷狗，把每个命中（网易云优先排序）用现有音源配置重新
  /// 解析出可播放候选一并返回，调用方（playTrack）会逐候选加载，任一成功
  /// 即播放。候选携带 [PlaybackCandidate.fallbackFrom]，供上层写回歌单。
  Future<ResolvedAudioSources?> _resolveCrossPlatformFallback(
    Track track,
    List<AudioSourceConfig> enabledSources,
    AudioSourcePreferences preferences,
    Set<String> excluded,
    List<String> failures,
  ) async {
    final fallbackService = _crossPlatformFallback;
    // 已有 alternatives 的曲目在上一阶段已遍历过可行平台，无需再搜；
    // 本地文件也不参与搜索。
    if (fallbackService == null ||
        track.alternatives.isNotEmpty ||
        track.source == MusicSource.local ||
        track.source == MusicSource.apple ||
        track.source == MusicSource.spotify) {
      return null;
    }
    if (!_crossPlatformTried.add(track.key)) return null;

    final matches = await fallbackService.findFallbackFor(track);
    final candidates = <PlaybackCandidate>[];
    for (final match in matches) {
      if (excluded.contains(match.source.wireName)) continue;
      for (final config in enabledSources) {
        if (!_supports(config, match.source)) continue;
        final quality = preferences.quality.effectiveFor(match.source);
        try {
          final resolved = await _sourceClient.resolveUrlFromSource(
            match.track,
            config,
            quality,
          );
          final lyric =
              resolved.lyrics ??
              await _sourceClient.fetchLyrics(match.track) ??
              const LyricData();
          candidates.add(
            PlaybackCandidate(
              track: match.track.copyWith(
                playbackUrl: _parsePlaybackUri(resolved.url),
                lyric: lyric.lyric,
                yrc: lyric.yrc,
                tlyric: lyric.tlyric,
                ytlrc: lyric.ytlrc,
                romaji: lyric.romaji,
              ),
              sourceId: '${config.id}:cross-fallback',
              fallbackFrom: TrackSourceRef(
                id: track.id,
                source: track.source,
              ),
            ),
          );
          // 该配置与平台能取出直链即记一个候选；每个命中记一个足矣
          // （后续更近的命中会排在前面被优先加载）。不短路，收集全部
          // 命中候选，让 playTrack 依序尝试。
          break;
        } catch (error) {
          failures.add('兜底 ${match.source.wireName}/${config.name}: $error');
        }
      }
    }
    return candidates.isEmpty ? null : ResolvedAudioSources(candidates);
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
