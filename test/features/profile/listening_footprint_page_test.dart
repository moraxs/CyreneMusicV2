import 'dart:convert';

import 'package:cyrene_music_reborn/application/auth/account_session_controller.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_repository.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_session_store.dart';
import 'package:cyrene_music_reborn/domain/models/user.dart';
import 'package:cyrene_music_reborn/features/profile/listening_footprint_page.dart';
import 'package:cyrene_music_reborn/infrastructure/core/api_client.dart';
import 'package:cyrene_music_reborn/presentation/cyrene/cyrene_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<String> requestedPaths;

  http.Client statsBackend() => MockClient((request) async {
    requestedPaths.add(request.url.path);
    Map<String, Object?> body;
    switch (request.url.path) {
      case '/stats':
        body = {
          'code': 200,
          'data': {
            'totalListeningTime': 7260,
            'totalPlayCount': 42,
            'playCounts': [
              {
                'track_id': '1001',
                'track_name': 'Song A',
                'artists': 'Artist A',
                'album': 'Album A',
                'pic_url': '',
                'source': 'netease',
                'play_count': 10,
              },
            ],
          },
        };
      case '/history/weekly':
        body = {
          'code': 200,
          'data': [
            {
              'track_id': '1001',
              'track_name': 'Song A',
              'artists': 'Artist A',
              'pic_url': '',
              'source': 'netease',
            },
            {
              'track_id': '1002',
              'track_name': 'Song B',
              'artists': 'Artist B',
              'pic_url': '',
              'source': 'netease',
            },
          ],
        };
      case '/stats/languages':
        body = {
          'code': 200,
          'data': {
            'languages': [
              {'language': '华语', 'playCount': 30, 'songCount': 12},
              {'language': '日语', 'playCount': 10, 'songCount': 5},
            ],
            'totalPlayCount': 40,
            'totalSongCount': 17,
          },
        };
      default:
        return http.Response('{"code":404}', 404);
    }
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  setUp(() {
    requestedPaths = [];
    ApiClient.instance.useClient(statsBackend());
  });

  testWidgets('已登录时加载并渲染统计、唱片墙、语言与排行', (tester) async {
    final account = AccountSessionController(
      const _AuthRepositoryStub(),
      _MemoryAuthSessionStore(
        const AuthSession(user: _user, token: 'token-abc'),
      ),
    );
    addTearDown(account.dispose);
    await account.restore();
    expect(account.token, 'token-abc');

    await tester.pumpWidget(
      _testApp(ListeningFootprintPage(account: account)),
    );
    await tester.pumpAndSettle();

    expect(requestedPaths, containsAll(['/stats', '/history/weekly', '/stats/languages']));
    expect(find.text('聆听时长'), findsOneWidget);
    expect(find.text('2 小时 1 分'), findsOneWidget);
    expect(find.text('42 次'), findsOneWidget);
    expect(find.text('本周唱片墙'), findsOneWidget);
    expect(find.text('华语'), findsOneWidget);
    expect(find.text('播放排行'), findsOneWidget);
    expect(find.text('Song A'), findsOneWidget);
  });

  testWidgets('进入页面时会话仍在恢复，恢复完成后应自动加载而不是停在空数据', (tester) async {
    final store = _MemoryAuthSessionStore(
      const AuthSession(user: _user, token: 'token-abc'),
      readDelay: const Duration(milliseconds: 300),
    );
    final account = AccountSessionController(const _AuthRepositoryStub(), store);
    addTearDown(account.dispose);

    // 模拟真实时序：restore 尚未完成（token 仍为 null）时页面已被打开。
    final restoring = account.restore();
    await tester.pumpWidget(
      _testApp(ListeningFootprintPage(account: account)),
    );
    expect(account.token, isNull);
    await tester.pump();

    await restoring;
    await tester.pumpAndSettle();

    expect(
      requestedPaths,
      containsAll(['/stats', '/history/weekly', '/stats/languages']),
      reason: '会话恢复完成后页面应重新拉取统计数据',
    );
    expect(find.text('播放排行'), findsOneWidget);
    expect(find.text('Song A'), findsOneWidget);
  });
}

Widget _testApp(Widget home) => MiuixSystemTheme(
  child: Builder(
    builder: (context) => MaterialApp(
      theme: CyreneMiuixTheme.material(MiuixTheme.of(context)),
      home: home,
    ),
  ),
);

const _user = User(
  id: 7,
  email: 'cyrene@example.com',
  username: 'Cyrene',
  isVerified: true,
  isSponsor: false,
);

class _AuthRepositoryStub implements AuthRepository {
  const _AuthRepositoryStub();

  @override
  Future<AuthResponse> login(String account, String password) async =>
      const AuthResponse(success: true, user: _user, data: {'token': 'token-abc'});

  @override
  Future<bool> validateToken(String token) async => true;

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
  _MemoryAuthSessionStore(this.session, {this.readDelay});

  AuthSession? session;
  final Duration? readDelay;

  @override
  Future<void> clear() async => session = null;

  @override
  Future<AuthSession?> read() async {
    final delay = readDelay;
    if (delay != null) await Future<void>.delayed(delay);
    return session;
  }

  @override
  Future<void> write(AuthSession value) async => session = value;
}
