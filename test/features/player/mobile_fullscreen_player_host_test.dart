import 'dart:async';

import 'package:cyrene_music_reborn/application/auth/account_session_controller.dart';
import 'package:cyrene_music_reborn/application/audio_sources/audio_source_preferences_controller.dart';
import 'package:cyrene_music_reborn/application/playback/playback_controller.dart';
import 'package:cyrene_music_reborn/application/stores/fullscreen_settings_store.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_repository.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_session_store.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/domain/models/user.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_player_gateway.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_source_preferences_store.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_snapshot.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_snapshot_store.dart';
import 'package:cyrene_music_reborn/features/player/mobile/mobile_fullscreen_player_host.dart';
import 'package:cyrene_music_reborn/features/player/super_cyrene/super_cyrene_fullscreen_player.dart';
import 'package:cyrene_music_reborn/infrastructure/services/configured_audio_source_importer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 移动端 SuperCyrene host：设置开启时渲染 SuperCyrene，关闭时切回。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final settings = FullscreenSettingsStore.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<PlaybackController> buildPlayback() async {
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
    return playback;
  }

  AccountSessionController buildAccount() {
    final account = AccountSessionController(
      const _FakeAuthRepository(),
      _MemoryAuthSessionStore(),
    );
    addTearDown(account.dispose);
    return account;
  }

  AudioSourcePreferencesController buildAudioSources() {
    final controller = AudioSourcePreferencesController(
      store: _MemoryAudioSourcePreferencesStore(),
      importer: ConfiguredAudioSourceImporter(),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  testWidgets('外观设置开 SuperCyrene 时 host 渲染 SuperCyrene 播放器', (tester) async {
    final playback = await buildPlayback();
    settings.setSuperCyrenePlayerEnabled(true);

    await tester.pumpWidget(
      MaterialApp(
        home: MobileFullscreenPlayerHost(
          playback: playback,
          audioSources: buildAudioSources(),
          account: buildAccount(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(SuperCyreneFullscreenPlayer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('host 内切回经典会触发 pop 返回流体云', (tester) async {
    final playback = await buildPlayback();
    settings.setSuperCyrenePlayerEnabled(true);

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(body: const Text('fluid-cloud')),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => MobileFullscreenPlayerHost(
          playback: playback,
          audioSources: buildAudioSources(),
          account: buildAccount(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SuperCyreneFullscreenPlayer), findsOneWidget);

    // 触发「切回经典」——host 监听设置变化，字段置 false 后应 pop 回流体云。
    settings.setSuperCyrenePlayerEnabled(false);
    await tester.pumpAndSettle();

    expect(find.byType(SuperCyreneFullscreenPlayer), findsNothing);
    expect(find.text('fluid-cloud'), findsOneWidget);
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