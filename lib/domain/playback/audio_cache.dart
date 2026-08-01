import '../models/audio_quality.dart';
import '../models/track.dart';

abstract interface class AudioCache {
  Future<Uri?> find(Track track, AudioQuality quality);
}
