import 'dart:async';

enum PlaybackStatus { idle, loading, ready, playing, paused, completed }

abstract interface class AudioPlayerGateway {
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<PlaybackStatus> get statusStream;

  Future<Duration?> load(Uri source);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> stop();
  Future<void> dispose();
}
