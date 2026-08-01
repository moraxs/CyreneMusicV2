import 'playback_snapshot.dart';

abstract interface class PlaybackSnapshotStore {
  Future<PlaybackSnapshot?> read();
  Future<void> write(PlaybackSnapshot snapshot);
}
