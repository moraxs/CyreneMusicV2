import '../../domain/models/audio_quality.dart';
import '../../domain/models/track.dart';
import '../../domain/playback/audio_cache.dart';

/// 不做任何缓存的实现（预览/测试用）。
class NoOpAudioCache implements AudioCache {
  const NoOpAudioCache();

  @override
  Future<CachedAudio?> lookup(Track track, AudioQuality quality) async => null;

  @override
  Future<Uri> intercept({
    required Track track,
    required AudioQuality quality,
    required Uri remoteUrl,
  }) async => remoteUrl;
}
