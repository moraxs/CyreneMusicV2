import 'dart:async';

import 'package:cyrene_music_reborn/application/auth/account_session_controller.dart';
import 'package:cyrene_music_reborn/application/audio_sources/audio_source_preferences_controller.dart';
import 'package:cyrene_music_reborn/application/playback/playback_controller.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_repository.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_session_store.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/domain/models/user.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_player_gateway.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_source_preferences_store.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_snapshot.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_snapshot_store.dart';
import 'package:cyrene_music_reborn/features/player/super_cyrene/super_cyrene_fullscreen_player.dart';
import 'package:cyrene_music_reborn/features/together/together_player_overlay.dart';
import 'package:cyrene_music_reborn/infrastructure/services/configured_audio_source_importer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一起听覆盖层必须挂在每个全屏播放器上。
///
/// 这层不是「有就好」的装饰：房间号、弹幕、发言入口全在里面，漏挂哪个播放器，
/// 那个播放器就完全看不到一起听（曾经桌面端两套都漏了）。加了新的全屏播放器
/// 就往这里补一条。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('SuperCyrene 播放器挂了一起听覆盖层', (tester) async {
    final playback = PlaybackController(
      audio: _FakeAudioGateway(),
      store: _FakeSnapshotStore(),
    );
    addTearDown(playback.dispose);
    await playback.playTrack(
      const Track(
        id: '1',
        name: '晴天',
        artists: '周杰伦',
        album: '叶惠美',
        picUrl: '',
        source: MusicSource.netease,
      ),
    );
    final account = AccountSessionController(
      const _FakeAuthRepository(),
      _MemoryAuthSessionStore(),
    );
    addTearDown(account.dispose);
    final audioSources = AudioSourcePreferencesController(
      store: _MemoryAudioSourcePreferencesStore(),
      importer: ConfiguredAudioSourceImporter(),
    );
    addTearDown(audioSources.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SuperCyreneFullscreenPlayer(
          playback: playback,
          audioSources: audioSources,
          account: account,
          onSwitchToClassic: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TogetherPlayerOverlay), findsOneWidget);
  });
}

class _FakeAudioGateway implements AudioPlayerGateway {
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _status = StreamController<PlaybackStatus>.broadcast();

  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration?> get durationStream => _duration.stream;
  @override
  Stream<PlaybackStatus> get statusStream => _status.stream;

  @override
  Future<Duration?> load(Uri source) async => Duration.zero;
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {
    await _position.close();
    await _duration.close();
    await _status.close();
  }
}

class _FakeSnapshotStore implements PlaybackSnapshotStore {
  PlaybackSnapshot? _snapshot;

  @override
  Future<PlaybackSnapshot?> read() async => _snapshot;
  @override
  Future<void> write(PlaybackSnapshot snapshot) async {
    _snapshot = snapshot;
  }
}

class _FakeAuthRepository implements AuthRepository {
  const _FakeAuthRepository();

  @override
  Future<AuthResponse> login(String account, String password) async =>
      const AuthResponse(success: false, message: '未登录');

  @override
  Future<bool> validateToken(String token) async => false;

  @override
  Future<AuthResponse> register(
    String email,
    String username,
    String password,
    String code,
  ) async => const AuthResponse(success: false);

  @override
  Future<AuthResponse> sendRegisterCode(String email, String username) async =>
      const AuthResponse(success: false);

  @override
  Future<({bool success, bool enabled})> checkRegistrationStatus() async =>
      (success: true, enabled: true);
}

class _MemoryAuthSessionStore implements AuthSessionStore {
  AuthSession? session;

  @override
  Future<void> clear() async => session = null;
  @override
  Future<AuthSession?> read() async => session;
  @override
  Future<void> write(AuthSession value) async => session = value;
}

class _MemoryAudioSourcePreferencesStore
    implements AudioSourcePreferencesStore {
  AudioSourcePreferences value = const AudioSourcePreferences();

  @override
  Future<AudioSourcePreferences> read() async => value;
  @override
  Future<void> write(AudioSourcePreferences preferences) async {
    value = preferences;
  }
}
