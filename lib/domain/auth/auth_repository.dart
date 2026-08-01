import '../models/user.dart';

abstract interface class AuthRepository {
  Future<AuthResponse> login(String account, String password);

  Future<bool> validateToken(String token);
}
