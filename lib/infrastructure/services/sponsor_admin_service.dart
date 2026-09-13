import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/url_service.dart';
import 'invite_service.dart';

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
    required this.outTradeNo,
    required this.tradeNo,
    this.paidAt,
    this.createdAt,
  });

  final int id;
  final double amount;
  final String paymentType;
  final int status;

  /// 商户订单号（本地生成，创建订单时即确定）。
  final String outTradeNo;

  /// 支付平台账单号/流水号（支付成功后由网关回写，可能为空）。
  final String tradeNo;

  final String? paidAt;
  final String? createdAt;

  bool get paid => status == 1;

  factory DonationItem.fromJson(Map<String, Object?> json) {
    String asString(Object? v) => v?.toString() ?? '';
    return DonationItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      paymentType: json['paymentType']?.toString() ?? '',
      status: (json['status'] as num?)?.toInt() ?? 0,
      outTradeNo: asString(json['outTradeNo']),
      tradeNo: asString(json['tradeNo']),
      paidAt: json['paidAt']?.toString(),
      createdAt: json['createdAt']?.toString(),
    );
  }
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

  // --- 提现管理（邀请有礼积分提现） ---

  /// 拉取提现申请列表。[status] 为 null 表示不按状态过滤。
  ///
  /// 复用用户端的 [WithdrawalRecord]：后端两侧走的是同一个序列化函数，
  /// 再定义一份管理端模型只会让字段名两处各飘一次。
  Future<({List<WithdrawalRecord> records, WithdrawalStats stats})?>
  getWithdrawals(
    String token, {
    WithdrawalStatus? status,
    String keyword = '',
  }) async {
    final query = <String, String>{
      if (status != null) 'status': status.wire,
      if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
    };
    final uri = Uri.parse(
      '$_base/admin/withdrawals',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final resp = await _client.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    final decoded = _decode(resp);
    if (decoded['code'] != 200) return null;
    final data = _data(decoded);
    final list = data['withdrawals'];
    return (
      records: list is List
          ? list
                .whereType<Map>()
                .map(
                  (e) => WithdrawalRecord.fromJson(Map<String, Object?>.from(e)),
                )
                .toList(growable: false)
          : const <WithdrawalRecord>[],
      stats: WithdrawalStats.fromJson(data['stats']),
    );
  }

  /// 修改提现状态（待提现 → 已提现 / 已驳回）。
  ///
  /// 返回后端文案而非裸 bool：驳回改回待提现时可能因用户余额不足被拒，
  /// 那条原因必须原样透给管理员，不然只会看到一个没头没尾的「操作失败」。
  Future<InviteActionResult> updateWithdrawalStatus(
    String token,
    int withdrawalId,
    WithdrawalStatus status, {
    String? note,
  }) async {
    final resp = await _client.put(
      Uri.parse('$_base/admin/withdrawals/$withdrawalId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'status': status.wire, 'note': ?note}),
    );
    final data = _decode(resp);
    final message = data['message']?.toString();
    return (ok: data['code'] == 200, message: message ?? '操作失败');
  }
}

/// 各状态的提现笔数与金额合计（管理端顶部概览）。
class WithdrawalStats {
  const WithdrawalStats({
    required this.pendingCount,
    required this.pendingAmount,
    required this.paidCount,
    required this.paidAmount,
    required this.rejectedCount,
  });

  final int pendingCount;
  final int pendingAmount;
  final int paidCount;
  final int paidAmount;
  final int rejectedCount;

  static const empty = WithdrawalStats(
    pendingCount: 0,
    pendingAmount: 0,
    paidCount: 0,
    paidAmount: 0,
    rejectedCount: 0,
  );

  factory WithdrawalStats.fromJson(Object? raw) {
    if (raw is! Map) return empty;
    ({int count, int amount}) cell(Object? value) {
      if (value is! Map) return (count: 0, amount: 0);
      return (
        count: (value['count'] as num?)?.toInt() ?? 0,
        amount: (value['amount'] as num?)?.toInt() ?? 0,
      );
    }

    final pending = cell(raw['pending']);
    final paid = cell(raw['paid']);
    final rejected = cell(raw['rejected']);
    return WithdrawalStats(
      pendingCount: pending.count,
      pendingAmount: pending.amount,
      paidCount: paid.count,
      paidAmount: paid.amount,
      rejectedCount: rejected.count,
    );
  }
}
