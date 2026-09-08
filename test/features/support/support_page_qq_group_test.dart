import 'dart:convert';

import 'package:cyrene_music_reborn/application/auth/account_session_controller.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_repository.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_session_store.dart';
import 'package:cyrene_music_reborn/domain/models/user.dart';
import 'package:cyrene_music_reborn/features/support/support_page.dart';
import 'package:cyrene_music_reborn/infrastructure/core/api_client.dart';
import 'package:cyrene_music_reborn/presentation/cyrene/cyrene_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 帮助与支持页的 QQ 群入口：完全由服务端 `/config/public` 的 `qq_group` 决定。
///
/// 关键不变量是 `enabled: false` 时**整块不渲染**——留个灰按钮或空标题都算 bug。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  tearDown(() => ApiClient.instance.useClient(http.Client()));

  testWidgets('enabled=true：渲染入群入口，副标题取服务端群名', (tester) async {
    await _pumpSupportPage(
      tester,
      qqGroup: const {
        'enabled': true,
        'url': 'https://qm.qq.com/q/5UADyZm3vi',
        'name': 'Cyrene Music 用户群',
      },
    );

    expect(find.byKey(const Key('join-qq-group')), findsOneWidget);
    expect(find.text('加入 QQ 群'), findsOneWidget);
    expect(find.text('Cyrene Music 用户群'), findsOneWidget);
    expect(find.text('交流与反馈'), findsOneWidget);
  });

  testWidgets('enabled=false：整块不渲染', (tester) async {
    await _pumpSupportPage(
      tester,
      qqGroup: const {
        'enabled': false,
        'url': 'https://qm.qq.com/q/5UADyZm3vi',
        'name': 'Cyrene Music 用户群',
      },
    );

    expect(find.byKey(const Key('join-qq-group')), findsNothing);
    expect(find.text('加入 QQ 群'), findsNothing);
    // 分节标题也不该留下。
    expect(find.text('交流与反馈'), findsNothing);
    // 页面其余部分正常。
    expect(find.text('赞助墙'), findsOneWidget);
  });

  testWidgets('enabled=true 但 url 为空：不渲染死按钮', (tester) async {
    await _pumpSupportPage(
      tester,
      qqGroup: const {'enabled': true, 'url': '', 'name': 'Cyrene Music 用户群'},
    );

    expect(find.byKey(const Key('join-qq-group')), findsNothing);
  });

  testWidgets('后端没下发 qq_group：不渲染，且页面不报错', (tester) async {
    await _pumpSupportPage(tester, qqGroup: null);

    expect(find.byKey(const Key('join-qq-group')), findsNothing);
    expect(tester.takeException(), isNull);
    expect(find.text('赞助墙'), findsOneWidget);
  });

  testWidgets('配置接口挂了：不渲染，且不拖累赞助墙', (tester) async {
    await _pumpSupportPage(tester, qqGroup: null, configFails: true);

    expect(find.byKey(const Key('join-qq-group')), findsNothing);
    expect(tester.takeException(), isNull);
    expect(find.text('赞助墙'), findsOneWidget);
  });
}

Future<void> _pumpSupportPage(
  WidgetTester tester, {
  required Map<String, Object?>? qqGroup,
  bool configFails = false,
}) async {
  // 走 ApiClient 的注入口，别去动 HttpOverrides：widget 绑定自带的那个
  // 「一律 400」mock 只会让两个请求都失败，测不出 qq_group 的分支。
  ApiClient.instance.useClient(
    MockClient((request) async {
      if (request.url.path.endsWith('/config/public')) {
        if (configFails) return http.Response('{}', 500);
        return http.Response(
          jsonEncode({
            'status': 200,
            'data': {
              'announcement': {
                'enabled': false,
                'id': '',
                'title': '',
                'content': '',
              },
              'qq_group': ?qqGroup,
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      // /sponsors/list：空赞助墙即可，本用例不关心它。
      return http.Response(
        jsonEncode({
          'code': 200,
          'message': 'ok',
          'data': {'sponsors': <Object?>[], 'total': 0},
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );

  tester.view.physicalSize = const Size(500, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final account = AccountSessionController(
    const _StubAuthRepository(),
    _MemoryAuthSessionStore(),
  );
  addTearDown(account.dispose);

  await tester.pumpWidget(
    MiuixSystemTheme(
      child: Builder(
        builder: (context) => MaterialApp(
          theme: CyreneMiuixTheme.material(MiuixTheme.of(context)),
          home: SupportPage(account: account),
        ),
      ),
    ),
  );

  // 等两个并行请求落地并重建。
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

class _StubAuthRepository implements AuthRepository {
  const _StubAuthRepository();

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
