import '../models/track.dart';

class PlaybackCandidate {
  const PlaybackCandidate({required this.track, required this.sourceId});

  final Track track;
  final String sourceId;
}

class ResolvedAudioSources {
  const ResolvedAudioSources(this.candidates);

  final List<PlaybackCandidate> candidates;

  bool get isEmpty => candidates.isEmpty;
}

abstract interface class AudioSourceResolver {
  Future<ResolvedAudioSources> resolve(Track track);
}

class AudioSourceResolutionFailure implements Exception {
  const AudioSourceResolutionFailure(this.message, {this.causes = const []});

  final String message;
  final List<String> causes;

  @override
  String toString() => message;
}
