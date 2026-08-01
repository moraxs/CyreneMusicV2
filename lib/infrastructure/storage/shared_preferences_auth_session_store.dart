import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/auth/auth_session_store.dart';
import '../../domain/models/user.dart';

class SharedPreferencesAuthSessionStore implements AuthSessionStore {
  SharedPreferencesAuthSessionStore([this._preferences]);

  static const _storageKey = 'auth-storage';
  final SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async =>
      _preferences ?? await SharedPreferences.getInstance();

  @override
  Future<AuthSession?> read() async {
    final raw = (await _prefs).getString(_storageKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final json = Map<String, Object?>.from(decoded);
      final userData = json['user'];
      final token = json['token'];
      final isLoggedIn = json['isLoggedIn'];
      if (userData is! Map || token is! String || token.isEmpty) return null;
      if (isLoggedIn == false) return null;

      return AuthSession(
        user: User.fromJson(Map<String, Object?>.from(userData)),
        token: token,
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(AuthSession session) => _update({
    'user': session.user.toJson(),
    'token': session.token,
    'isLoggedIn': true,
  });

  @override
  Future<void> clear() =>
      _update({'user': null, 'token': null, 'isLoggedIn': false});

  Future<void> _update(Map<String, Object?> values) async {
    final preferences = await _prefs;
    final current = <String, Object?>{};
    final raw = preferences.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          current.addAll(Map<String, Object?>.from(decoded));
        }
      } on FormatException {
        // 损坏数据由当前有效状态覆盖。
      }
    }
    current.addAll(values);
    await preferences.setString(_storageKey, jsonEncode(current));
  }
}
