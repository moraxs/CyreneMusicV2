import '../models/track.dart';
import 'repeat_mode.dart';

Track? nextTrack({
  required List<Track> queue,
  required Track? currentTrack,
  required RepeatMode repeatMode,
  int? randomIndex,
}) {
  if (queue.isEmpty) return null;
  final currentIndex = currentTrack == null ? -1 : queue.indexOf(currentTrack);

  if (repeatMode == RepeatMode.one && currentIndex >= 0) return currentTrack;
  if (repeatMode == RepeatMode.shuffle && queue.length > 1) {
    final candidates = queue.where((track) => track != currentTrack).toList();
    return candidates[(randomIndex ?? 0) % candidates.length];
  }
  if (currentIndex < 0) return queue.first;
  if (currentIndex == queue.length - 1) {
    return repeatMode == RepeatMode.all ? queue.first : null;
  }
  return queue[currentIndex + 1];
}

Track? previousTrack({
  required List<Track> queue,
  required Track? currentTrack,
  required RepeatMode repeatMode,
}) {
  if (queue.isEmpty) return null;
  final currentIndex = currentTrack == null ? -1 : queue.indexOf(currentTrack);
  if (currentIndex <= 0) {
    return repeatMode == RepeatMode.all ? queue.last : null;
  }
  return queue[currentIndex - 1];
}
