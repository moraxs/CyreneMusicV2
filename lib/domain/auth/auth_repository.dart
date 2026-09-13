import '../models/user.dart';

abstract interface class AuthRepository {
  Future<AuthResponse> login(String account, String password);

  Future<bool> validateToken(String token);

  /// [inviteCode] 为邀请有礼的邀请码，选填；非空时后端在注册成功后绑定邀请关系。
  Future<AuthResponse> register(
    String email,
    String username,
    String password,
    String code, {
    String? inviteCode,
  });

  Future<AuthResponse> sendRegisterCode(String email, String username);

  Future<({bool success, bool enabled})> checkRegistrationStatus();
}
