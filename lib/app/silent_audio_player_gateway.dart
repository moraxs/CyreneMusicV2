import 'dart:async';

import '../domain/playback/audio_player_gateway.dart';

class SilentAudioPlayerGateway implements AudioPlayerGateway {
  const SilentAudioPlayerGateway();

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<PlaybackStatus> get statusStream => const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<Duration?> load(Uri source) async => null;

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}
}
