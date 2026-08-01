import '../models/track.dart';
import 'playback_state.dart';
import 'repeat_mode.dart';

class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.queue,
    required this.currentTrackKey,
    required this.volume,
    required this.repeatMode,
  });

  final List<Track> queue;
  final String? currentTrackKey;
  final double volume;
  final RepeatMode repeatMode;

  factory PlaybackSnapshot.fromState(PlaybackState state) => PlaybackSnapshot(
    queue: state.queue,
    currentTrackKey: state.currentTrack?.key,
    volume: state.volume,
    repeatMode: state.repeatMode,
  );

  factory PlaybackSnapshot.fromJson(Map<String, Object?> json) {
    final queueValue = json['queue'];
    final tracks = queueValue is List
        ? queueValue
              .whereType<Map>()
              .map((value) => Track.fromJson(Map<String, Object?>.from(value)))
              .toList(growable: false)
        : const <Track>[];
    final currentTrackKey = json['currentTrackKey'] as String?;

    return PlaybackSnapshot(
      queue: tracks,
      currentTrackKey: tracks.any((track) => track.key == currentTrackKey)
          ? currentTrackKey
          : null,
      volume: switch (json['volume']) {
        final num value => value.clamp(0, 1).toDouble(),
        _ => 0.8,
      },
      repeatMode: RepeatMode.values.firstWhere(
        (mode) => mode.name == json['repeatMode'],
        orElse: () => RepeatMode.all,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'queue': queue.map((track) => track.toJson()).toList(growable: false),
    'currentTrackKey': currentTrackKey,
    'volume': volume,
    'repeatMode': repeatMode.name,
  };
}
