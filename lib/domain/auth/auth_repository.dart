import '../models/user.dart';

abstract interface class AuthRepository {
  Future<AuthResponse> login(String account, String password);

  Future<bool> validateToken(String token);

  Future<AuthResponse> register(
    String email,
    String username,
    String password,
    String code,
  );

  Future<AuthResponse> sendRegisterCode(String email, String username);

  Future<({bool success, bool enabled})> checkRegistrationStatus();
}
