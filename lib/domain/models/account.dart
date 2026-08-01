/// 第三方平台绑定信息（对应 accountService.ts 的 BindingInfo）。
class BindingInfo {
  const BindingInfo({
    required this.bound,
    this.nickname,
    this.avatarUrl,
    this.avatar,
    this.userId,
    this.username,
  });

  final bool bound;
  final String? nickname;
  final String? avatarUrl;
  final String? avatar;
  final String? userId;
  final String? username;

  factory BindingInfo.fromJson(Map<String, Object?> json) => BindingInfo(
    bound: json['bound'] == true,
    nickname: json['nickname']?.toString(),
    avatarUrl: json['avatarUrl']?.toString(),
    avatar: json['avatar']?.toString(),
    userId: json['userId']?.toString(),
    username: json['username']?.toString(),
  );

  Map<String, Object?> toJson() => {
    'bound': bound,
    'nickname': nickname,
    'avatarUrl': avatarUrl,
    'avatar': avatar,
    'userId': userId,
    'username': username,
  };
}

/// 账号第三方绑定集合（对应 AccountBindings）。
class AccountBindings {
  const AccountBindings({
    required this.netease,
    required this.kugou,
    required this.qq,
  });

  final BindingInfo netease;
  final BindingInfo kugou;
  final BindingInfo qq;

  factory AccountBindings.fromJson(Map<String, Object?> json) =>
      AccountBindings(
        netease: _binding(json['netease']),
        kugou: _binding(json['kugou']),
        qq: _binding(json['qq']),
      );

  static BindingInfo _binding(Object? data) => data is Map
      ? BindingInfo.fromJson(Map<String, Object?>.from(data))
      : const BindingInfo(bound: false);
}

/// 验证码 / 手机登录接口的统一响应。
class CaptchaResult {
  const CaptchaResult({required this.code, this.message});

  final int code;
  final String? message;

  factory CaptchaResult.fromJson(Map<String, Object?> json) => CaptchaResult(
    code: (json['code'] as num?)?.toInt() ?? 0,
    message: json['message']?.toString(),
  );
}

/// 网易云二维码数据（对应 getNeteaseQRData 返回）。
class NeteaseQrData {
  const NeteaseQrData({this.qrimg, required this.qrUrl});

  final String? qrimg;
  final String qrUrl;

  factory NeteaseQrData.fromJson(Map<String, Object?> json) => NeteaseQrData(
    qrimg: json['qrimg']?.toString(),
    qrUrl: json['qrUrl']?.toString() ?? '',
  );
}
