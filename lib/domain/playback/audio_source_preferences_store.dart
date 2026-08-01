import '../models/audio_quality.dart';
import '../models/audio_source_config.dart';

class AudioSourcePreferences {
  const AudioSourcePreferences({
    this.sources = const [],
    this.quality = AudioQuality.exHigh,
  });

  final List<AudioSourceConfig> sources;
  final AudioQuality quality;

  AudioSourcePreferences copyWith({
    List<AudioSourceConfig>? sources,
    AudioQuality? quality,
  }) => AudioSourcePreferences(
    sources: sources ?? this.sources,
    quality: quality ?? this.quality,
  );
}

abstract interface class AudioSourcePreferencesStore {
  Future<AudioSourcePreferences> read();

  Future<void> write(AudioSourcePreferences preferences);
}
