import '../models/track.dart';
import 'repeat_mode.dart';

class PlaybackState {
  PlaybackState({
    this.currentTrack,
    List<Track> queue = const [],
    this.isPlaying = false,
    this.isLoading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 0.8,
    this.repeatMode = RepeatMode.all,
    this.errorMessage,
  }) : queue = List.unmodifiable(queue);

  final Track? currentTrack;
  final List<Track> queue;
  final bool isPlaying;
  final bool isLoading;
  final Duration position;
  final Duration duration;
  final double volume;
  final RepeatMode repeatMode;
  final String? errorMessage;

  PlaybackState copyWith({
    Track? currentTrack,
    bool clearCurrentTrack = false,
    List<Track>? queue,
    bool? isPlaying,
    bool? isLoading,
    Duration? position,
    Duration? duration,
    double? volume,
    RepeatMode? repeatMode,
    String? errorMessage,
    bool clearError = false,
  }) => PlaybackState(
    currentTrack: clearCurrentTrack ? null : currentTrack ?? this.currentTrack,
    queue: queue ?? this.queue,
    isPlaying: isPlaying ?? this.isPlaying,
    isLoading: isLoading ?? this.isLoading,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    volume: volume ?? this.volume,
    repeatMode: repeatMode ?? this.repeatMode,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );

  PlaybackState resetForTrack(Track track) => PlaybackState(
    currentTrack: track,
    queue: queue,
    isLoading: true,
    volume: volume,
    repeatMode: repeatMode,
  );
}
