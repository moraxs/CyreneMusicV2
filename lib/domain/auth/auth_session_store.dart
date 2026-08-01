import '../models/user.dart';

class AuthSession {
  const AuthSession({required this.user, required this.token});

  final User user;
  final String token;
}

abstract interface class AuthSessionStore {
  Future<AuthSession?> read();

  Future<void> write(AuthSession session);

  Future<void> clear();
}
