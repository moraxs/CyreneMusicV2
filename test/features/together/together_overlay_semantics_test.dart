import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music_reborn/application/auth/account_session_controller.dart';
import 'package:cyrene_music_reborn/application/playback/playback_controller.dart';
import 'package:cyrene_music_reborn/application/stores/together_settings_store.dart';
import 'package:cyrene_music_reborn/application/together/together_controller.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_repository.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_session_store.dart';
import 'package:cyrene_music_reborn/domain/models/user.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_player_gateway.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_snapshot.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_snapshot_store.dart';
import 'package:cyrene_music_reborn/features/together/together_player_overlay.dart';
import 'package:cyrene_music_reborn/infrastructure/core/url_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 桌面端的一起听图层不能往语义树里加节点。
///
/// Windows 版 Flutter 的无障碍桥有已知缺陷（flutter#182444）：往桌面播放器子树
/// 里加语义节点会让它更新 AXTree 失败并原生报错
/// （`Failed to update ui::AXTree, error: N will not be in the tree`）。
/// 这个只在 Windows 真机上炸、平时完全无感，所以必须有测试守着。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late _FakeServer server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = await _FakeServer.start();
    UrlService.instance
      ..setSourceType(BackendSourceType.custom)
      ..setCustomBaseUrl('http://127.0.0.1:${server.port}');
    await TogetherSettingsStore.instance.init();
    TogetherController.instance.bind(
      playback: PlaybackController(
        audio: _FakeAudioGateway(),
        store: _FakeSnapshotStore(),
      ),
      account: AccountSessionController(
        const _FakeAuthRepository(),
        _MemoryAuthSessionStore(),
      ),
    );
    expect(await TogetherController.instance.host(), isTrue);
  });

  tearDown(() async {
    await TogetherController.instance.leave(dissolve: false);
    await server.close();
  });

  Future<void> pump(WidgetTester tester, {required bool exclude}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const SizedBox.expand(),
                TogetherPlayerOverlay(excludeSemantics: exclude),
              ],
            ),
          ),
        ),
      );

  testWidgets('默认（移动端）保留语义节点', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, exclude: false);
    expect(find.bySemanticsLabel(RegExp('房间')), findsWidgets);
    handle.dispose();
  });

  testWidgets('excludeSemantics 打开后对语义树零贡献', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, exclude: true);
    // 房间胶囊照常画出来……
    expect(find.textContaining('房间'), findsWidgets);
    // ……但语义树里没有它。
    expect(find.bySemanticsLabel(RegExp('房间')), findsNothing);
    handle.dispose();
  });
}

/// 顶替一起听服务端：连上就发一帧 welcome。
class _FakeServer {
  _FakeServer(this._server);

  final HttpServer _server;
  WebSocket? _socket;

  int get port => _server.port;

  static Future<_FakeServer> start() async {
    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final server = _FakeServer(httpServer);
    httpServer.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      server._socket = socket;
      socket.add(
        jsonEncode({
          't': 'welcome',
          'self': {'id': 'm1', 'name': '我', 'isHost': true},
          'room': {
            'code': 'ABCDEF',
            'members': [
              {'id': 'm1', 'name': '我', 'isHost': true},
            ],
          },
          'chat': <Object?>[],
        }),
      );
      socket.listen((_) {});
    });
    return server;
  }

  Future<void> close() async {
    await _socket?.close();
    await _server.close(force: true);
  }
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
      const AuthResponse(success: false);
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
