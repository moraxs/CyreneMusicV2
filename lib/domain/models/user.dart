/// 用户账户模型（对应 Next.js demo/lib/services/authService.ts 的 User / AuthResponse）。
class User {
  const User({
    required this.id,
    required this.email,
    required this.username,
    required this.isVerified,
    this.lastLogin,
    this.avatarUrl,
    required this.isSponsor,
    this.sponsorSince,
    this.ipLocation,
    this.hasListeningCard = false,
    this.listeningCardSince,
  });

  final int id;
  final String email;
  final String username;
  final bool isVerified;
  final String? lastLogin;
  final String? avatarUrl;
  final bool isSponsor;
  final String? sponsorSince;
  final String? ipLocation;

  /// 是否持有 Cyrene Premium（永久买断），对应后端 has_listening_card===1。
  final bool hasListeningCard;
  final String? listeningCardSince;

  factory User.fromJson(Map<String, Object?> json) => User(
    id: (json['id'] as num?)?.toInt() ?? 0,
    email: json['email']?.toString() ?? '',
    username: json['username']?.toString() ?? '',
    isVerified: json['isVerified'] == true,
    lastLogin: json['lastLogin']?.toString(),
    avatarUrl: json['avatarUrl']?.toString(),
    isSponsor: json['isSponsor'] == true,
    sponsorSince: json['sponsorSince']?.toString(),
    ipLocation: json['ipLocation']?.toString(),
    hasListeningCard: json['hasListeningCard'] == true,
    listeningCardSince: json['listeningCardSince']?.toString(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'email': email,
    'username': username,
    'isVerified': isVerified,
    'lastLogin': lastLogin,
    'avatarUrl': avatarUrl,
    'isSponsor': isSponsor,
    'sponsorSince': sponsorSince,
    'ipLocation': ipLocation,
    'hasListeningCard': hasListeningCard,
    'listeningCardSince': listeningCardSince,
  };

  User copyWith({
    int? id,
    String? email,
    String? username,
    bool? isVerified,
    String? lastLogin,
    String? avatarUrl,
    bool? isSponsor,
    String? sponsorSince,
    String? ipLocation,
    bool? hasListeningCard,
    String? listeningCardSince,
  }) => User(
    id: id ?? this.id,
    email: email ?? this.email,
    username: username ?? this.username,
    isVerified: isVerified ?? this.isVerified,
    lastLogin: lastLogin ?? this.lastLogin,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    isSponsor: isSponsor ?? this.isSponsor,
    sponsorSince: sponsorSince ?? this.sponsorSince,
    ipLocation: ipLocation ?? this.ipLocation,
    hasListeningCard: hasListeningCard ?? this.hasListeningCard,
    listeningCardSince: listeningCardSince ?? this.listeningCardSince,
  );
}

/// 认证接口统一响应（对应 authService.ts 的 AuthResponse）。
class AuthResponse {
  const AuthResponse({
    required this.success,
    this.message,
    this.data,
    this.user,
  });

  final bool success;
  final String? message;

  /// 登录成功时为包含 token 与用户信息的原始载荷。
  final Object? data;
  final User? user;

  String? get token {
    final payload = data;
    if (payload is! Map) return null;
    final value = payload['token'];
    return value is String && value.isNotEmpty ? value : null;
  }
}
