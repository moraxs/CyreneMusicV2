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

  /// 发送找回密码的邮箱验证码。
  ///
  /// [email] 为注册邮箱；为防账号枚举，后端对未注册邮箱同样返回成功。
  Future<AuthResponse> sendResetCode(String email);

  /// 用邮箱验证码重置密码。
  ///
  /// 成功后后端不签发 token，调用方须引导用户用新密码重新登录。
  Future<AuthResponse> resetPassword(
    String email,
    String code,
    String newPassword,
  );
}
