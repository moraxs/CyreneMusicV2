import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/url_service.dart';

/// 管理端用户列表项（对应 /admin/users 返回的单项）。
class AdminUser {
  const AdminUser({
    required this.id,
    required this.username,
    required this.email,
    required this.isSponsor,
    required this.hasListeningCard,
  });

  final int id;
  final String username;
  final String email;
  final bool isSponsor;
  final bool hasListeningCard;

  factory AdminUser.fromJson(Map<String, Object?> json) => AdminUser(
    id: (json['id'] as num?)?.toInt() ?? 0,
    username: json['username']?.toString() ?? '',
    email: json['email']?.toString() ?? '',
    isSponsor: (json['is_sponsor'] as num?)?.toInt() == 1,
    hasListeningCard: (json['has_listening_card'] as num?)?.toInt() == 1,
  );
}

/// 赞助记录（对应 /admin/sponsors/:userId 返回的 donations 单项）。
class DonationItem {
  const DonationItem({
    required this.id,
    required this.amount,
    required this.paymentType,
    required this.status,
    this.paidAt,
    this.createdAt,
  });

  final int id;
  final double amount;
  final String paymentType;
  final int status;
  final String? paidAt;
  final String? createdAt;

  bool get paid => status == 1;

  factory DonationItem.fromJson(Map<String, Object?> json) => DonationItem(
    id: (json['id'] as num?)?.toInt() ?? 0,
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    paymentType: json['paymentType']?.toString() ?? '',
    status: (json['status'] as num?)?.toInt() ?? 0,
    paidAt: json['paidAt']?.toString(),
    createdAt: json['createdAt']?.toString(),
  );
}

/// 用户订阅/赞助详情。
class SponsorDetail {
  const SponsorDetail({
    required this.userId,
    required this.username,
    required this.isSponsor,
    required this.hasListeningCard,
    required this.totalAmount,
    required this.donations,
  });

  final int userId;
  final String username;
  final bool isSponsor;
  final bool hasListeningCard;
  final double totalAmount;
  final List<DonationItem> donations;

  factory SponsorDetail.fromJson(Map<String, Object?> json) => SponsorDetail(
    userId: (json['userId'] as num?)?.toInt() ?? 0,
    username: json['username']?.toString() ?? '',
    isSponsor: json['isSponsor'] == true,
    hasListeningCard: json['hasListeningCard'] == true,
    totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0,
    donations: (json['donations'] as List?)
            ?.whereType<Map>()
            .map((e) => DonationItem.fromJson(Map<String, Object?>.from(e)))
            .toList(growable: false) ??
        const [],
  );
}

/// 订阅与赞助管理服务：调用后端 /admin 接口。
///
/// 使用独立 [http.Client]，避免触发应用用户会话失效逻辑
/// （管理会话与应用用户会话相互独立）。
class SponsorAdminService {
  SponsorAdminService._();
  static final SponsorAdminService instance = SponsorAdminService._();

  final http.Client _client = http.Client();
  String get _base => UrlService.instance.baseUrl;

  Map<String, Object?> _decode(http.Response r) {
    try {
      final payload = jsonDecode(r.body);
      return payload is Map ? Map<String, Object?>.from(payload) : const {};
    } catch (_) {
      return const {};
    }
  }

  Map<String, Object?> _data(Map<String, Object?> decoded) {
    final d = decoded['data'];
    return d is Map ? Map<String, Object?>.from(d) : const {};
  }

  /// 登录管理后台，成功返回会话 token，失败返回 null。
  Future<String?> login(String password) async {
    final resp = await _client.post(
      Uri.parse('$_base/admin/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'password': password}),
    );
    final data = _decode(resp);
    if (data['code'] == 200) {
      final token = _data(data)['token']?.toString();
      if (token != null && token.isNotEmpty) return token;
    }
    return null;
  }

  /// 搜索用户（关键词为空时返回最近注册的一批用户）。
  Future<List<AdminUser>> searchUsers(String token, String keyword) async {
    final query = keyword.trim().isEmpty
        ? ''
        : '?keyword=${Uri.encodeQueryComponent(keyword.trim())}';
    final resp = await _client.get(
      Uri.parse('$_base/admin/users$query'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _decode(resp);
    if (data['code'] != 200) return const [];
    final d = _data(data);
    final users = d['users'];
    if (users is! List) return const [];
    return users
        .whereType<Map>()
        .map((e) => AdminUser.fromJson(Map<String, Object?>.from(e)))
        .toList(growable: false);
  }

  /// 获取用户订阅/赞助详情。
  Future<SponsorDetail?> getDetails(String token, int userId) async {
    final resp = await _client.get(
      Uri.parse('$_base/admin/sponsors/$userId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _decode(resp);
    if (data['code'] != 200) return null;
    return SponsorDetail.fromJson(_data(data));
  }

  /// 切换赞助状态。
  Future<bool> toggleSponsor(
    String token,
    int userId,
    bool isSponsor,
  ) async {
    final resp = await _client.put(
      Uri.parse('$_base/admin/sponsors/$userId'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'isSponsor': isSponsor}),
    );
    final data = _decode(resp);
    return data['code'] == 200;
  }

  /// 切换 Cyrene Premium 订阅状态。
  Future<bool> togglePremium(
    String token,
    int userId,
    bool hasListeningCard,
  ) async {
    final resp = await _client.put(
      Uri.parse('$_base/admin/users/$userId/premium'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'hasListeningCard': hasListeningCard}),
    );
    final data = _decode(resp);
    return data['code'] == 200;
  }

  /// 手动添加赞助记录（已支付）。
  Future<bool> addDonation(String token, int userId, double amount) async {
    final resp = await _client.post(
      Uri.parse('$_base/admin/sponsors/$userId/donation'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'amount': amount, 'paymentType': 'manual', 'markAsPaid': true}),
    );
    final data = _decode(resp);
    return data['code'] == 200;
  }

  /// 删除赞助记录。
  Future<bool> deleteDonation(String token, int donationId) async {
    final resp = await _client.delete(
      Uri.parse('$_base/admin/donations/$donationId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _decode(resp);
    return data['code'] == 200;
  }
}
