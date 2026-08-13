import 'package:cyrene_music_reborn/application/auth/account_session_controller.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_repository.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_session_store.dart';
import 'package:cyrene_music_reborn/domain/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('登录成功后提交用户与 token，并持久化会话', () async {
    final repository = _FakeAuthRepository(loginResult: _successResponse());
    final store = _MemoryAuthSessionStore();
    final controller = AccountSessionController(repository, store);
    addTearDown(controller.dispose);

    final success = await controller.login('  cyrene  ', 'secret');

    expect(success, isTrue);
    expect(repository.lastAccount, 'cyrene');
    expect(controller.state.isLoggedIn, isTrue);
    expect(controller.state.user?.username, 'Cyrene');
    expect(controller.token, 'token-123');
    expect(store.session?.token, 'token-123');
  });

  test('恢复会话时校验 token，无效凭证会被清除', () async {
    final repository = _FakeAuthRepository(tokenIsValid: false);
    final store = _MemoryAuthSessionStore(
      AuthSession(user: _user, token: 'expired-token'),
    );
    final controller = AccountSessionController(repository, store);
    addTearDown(controller.dispose);

    await controller.restore();

    expect(controller.state.status, AccountSessionStatus.signedOut);
    expect(controller.state.errorMessage, '登录已失效，请重新登录');
    expect(controller.token, isNull);
    expect(store.session, isNull);
  });

  test('401 会话失效会立即清理内存状态和持久化凭证', () async {
    final store = _MemoryAuthSessionStore();
    final controller = AccountSessionController(
      _FakeAuthRepository(loginResult: _successResponse()),
      store,
    );
    addTearDown(controller.dispose);
    await controller.login('cyrene', 'secret');

    controller.expireSession();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, AccountSessionStatus.signedOut);
    expect(controller.state.errorMessage, '登录已失效，请重新登录');
    expect(controller.token, isNull);
    expect(store.session, isNull);
  });

  test('退出登录保留稳定的已登出状态', () async {
    final store = _MemoryAuthSessionStore();
    final controller = AccountSessionController(
      _FakeAuthRepository(loginResult: _successResponse()),
      store,
    );
    addTearDown(controller.dispose);
    await controller.login('cyrene', 'secret');

    await controller.logout();

    expect(controller.state.status, AccountSessionStatus.signedOut);
    expect(controller.state.errorMessage, isNull);
    expect(store.session, isNull);
  });
}

const _user = User(
  id: 7,
  email: 'cyrene@example.com',
  username: 'Cyrene',
  isVerified: true,
  isSponsor: false,
);

AuthResponse _successResponse() => const AuthResponse(
  success: true,
  user: _user,
  data: {'token': 'token-123'},
);

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({
    this.loginResult = const AuthResponse(success: false),
    this.tokenIsValid = true,
  });

  final AuthResponse loginResult;
  final bool tokenIsValid;
  String? lastAccount;

  @override
  Future<AuthResponse> login(String account, String password) async {
    lastAccount = account;
    return loginResult;
  }

  @override
  Future<bool> validateToken(String token) async => tokenIsValid;

  @override
  Future<AuthResponse> register(
    String email,
    String username,
    String password,
    String code,
  ) async => const AuthResponse(success: true);

  @override
  Future<AuthResponse> sendRegisterCode(String email, String username) async =>
      const AuthResponse(success: true);

  @override
  Future<({bool success, bool enabled})> checkRegistrationStatus() async =>
      (success: true, enabled: true);
}

class _MemoryAuthSessionStore implements AuthSessionStore {
  _MemoryAuthSessionStore([this.session]);

  AuthSession? session;

  @override
  Future<void> clear() async => session = null;

  @override
  Future<AuthSession?> read() async => session;

  @override
  Future<void> write(AuthSession value) async => session = value;
}
