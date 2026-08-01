import '../../domain/models/audio_quality.dart';
import '../../domain/models/track.dart';
import '../../domain/playback/audio_cache.dart';

class NoOpAudioCache implements AudioCache {
  const NoOpAudioCache();

  @override
  Future<Uri?> find(Track track, AudioQuality quality) async => null;
}
