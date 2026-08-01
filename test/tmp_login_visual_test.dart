// 临时视觉核对用（生成 golden PNG 供人眼检查），核对后即删。
import 'package:cyrene_music_reborn/application/auth/account_session_controller.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_repository.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_session_store.dart';
import 'package:cyrene_music_reborn/domain/models/user.dart';
import 'package:cyrene_music_reborn/features/settings/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubAuth implements AuthRepository {
  const _StubAuth();

  @override
  Future<AuthResponse> login(String account, String password) async =>
      const AuthResponse(success: false, message: '账号或密码错误');

  @override
  Future<bool> validateToken(String token) async => false;
}

class _StubStore implements AuthSessionStore {
  AuthSession? session;

  @override
  Future<AuthSession?> read() async => session;

  @override
  Future<void> write(AuthSession value) async => session = value;

  @override
  Future<void> clear() async => session = null;
}

Future<void> _pump(WidgetTester tester, MiuixColorSchemeMode mode) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  await tester.pumpWidget(
    MiuixThemeController(
      colorSchemeMode: mode,
      child: MaterialApp(
        home: LoginPage(
          account: AccountSessionController(const _StubAuth(), _StubStore()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('login light', (tester) async {
    await _pump(tester, MiuixColorSchemeMode.light);
    await expectLater(
      find.byType(LoginPage),
      matchesGoldenFile('tmp_login_light.png'),
    );
  });

  testWidgets('login dark', (tester) async {
    await _pump(tester, MiuixColorSchemeMode.dark);
    await expectLater(
      find.byType(LoginPage),
      matchesGoldenFile('tmp_login_dark.png'),
    );
  });
}
