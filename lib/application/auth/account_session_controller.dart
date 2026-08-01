import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/auth/auth_repository.dart';
import '../../domain/auth/auth_session_store.dart';
import '../../domain/models/user.dart';

enum AccountSessionStatus { initial, restoring, signedOut, signingIn, signedIn }

class AccountSessionState {
  const AccountSessionState({
    this.status = AccountSessionStatus.initial,
    this.user,
    this.errorMessage,
  });

  final AccountSessionStatus status;
  final User? user;
  final String? errorMessage;

  bool get isLoggedIn =>
      status == AccountSessionStatus.signedIn && user != null;
  bool get isBusy =>
      status == AccountSessionStatus.restoring ||
      status == AccountSessionStatus.signingIn;

  AccountSessionState copyWith({
    AccountSessionStatus? status,
    User? user,
    bool clearUser = false,
    String? errorMessage,
    bool clearError = false,
  }) => AccountSessionState(
    status: status ?? this.status,
    user: clearUser ? null : user ?? this.user,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );
}

class AccountSessionController extends ChangeNotifier {
  AccountSessionController(this._repository, this._store);

  final AuthRepository _repository;
  final AuthSessionStore _store;

  AccountSessionState _state = const AccountSessionState();
  AccountSessionState get state => _state;

  String? _token;
  String? get token => _token;

  var _requestId = 0;

  Future<void> restore() async {
    final requestId = ++_requestId;
    _emit(
      _state.copyWith(status: AccountSessionStatus.restoring, clearError: true),
    );

    try {
      final session = await _store.read();
      if (requestId != _requestId) return;
      if (session == null) {
        _setSignedOut();
        return;
      }

      final valid = await _repository.validateToken(session.token);
      if (requestId != _requestId) return;
      if (!valid) {
        await _store.clear();
        if (requestId != _requestId) return;
        _setSignedOut(errorMessage: '登录已失效，请重新登录');
        return;
      }

      _token = session.token;
      _emit(
        AccountSessionState(
          status: AccountSessionStatus.signedIn,
          user: session.user,
        ),
      );
    } catch (_) {
      if (requestId != _requestId) return;
      _setSignedOut(errorMessage: '无法恢复账号信息');
    }
  }

  Future<bool> login(String account, String password) async {
    final normalizedAccount = account.trim();
    if (normalizedAccount.isEmpty || password.isEmpty) {
      _emit(_state.copyWith(errorMessage: '请输入账号和密码'));
      return false;
    }

    final requestId = ++_requestId;
    _emit(
      _state.copyWith(
        status: AccountSessionStatus.signingIn,
        clearUser: true,
        clearError: true,
      ),
    );

    try {
      final result = await _repository.login(normalizedAccount, password);
      if (requestId != _requestId) return false;
      final user = result.user;
      final token = result.token;
      if (!result.success || user == null || token == null || token.isEmpty) {
        _setSignedOut(errorMessage: result.message ?? '登录失败');
        return false;
      }

      await _store.write(AuthSession(user: user, token: token));
      if (requestId != _requestId) return false;
      _token = token;
      _emit(
        AccountSessionState(status: AccountSessionStatus.signedIn, user: user),
      );
      return true;
    } catch (_) {
      if (requestId != _requestId) return false;
      _setSignedOut(errorMessage: '网络错误，请稍后重试');
      return false;
    }
  }

  Future<void> logout() async {
    ++_requestId;
    _setSignedOut();
    await _store.clear();
  }

  void expireSession([String? reason]) {
    if (!_state.isLoggedIn && _token == null) return;
    ++_requestId;
    _setSignedOut(errorMessage: reason ?? '登录已失效，请重新登录');
    unawaited(_store.clear());
  }

  /// 在不重新走登录链路的前提下，就地更新当前用户信息并落盘。
  ///
  /// 用于权益状态（如 Cyrene Premium 持卡）由前端拉取后回写本机快照：
  /// 避免要求用户退出重登才能在个人中心/我的页看到状态更新。用
  /// `_requestId` 守卫，若期间发生登出/重登则放弃本次回写，避免把
  /// 旧用户对象写回新会话。
  Future<void> patchUser(User Function(User current) updater) async {
    final current = _state.user;
    final token = _token;
    if (current == null || token == null || token.isEmpty) return;
    final requestId = _requestId;
    final updated = updater(current);
    await _store.write(AuthSession(user: updated, token: token));
    if (requestId != _requestId) return;
    _emit(_state.copyWith(user: updated));
  }

  void clearError() {
    if (_state.errorMessage == null) return;
    _emit(_state.copyWith(clearError: true));
  }

  void _setSignedOut({String? errorMessage}) {
    _token = null;
    _emit(
      AccountSessionState(
        status: AccountSessionStatus.signedOut,
        errorMessage: errorMessage,
      ),
    );
  }

  void _emit(AccountSessionState state) {
    _state = state;
    notifyListeners();
  }
}
