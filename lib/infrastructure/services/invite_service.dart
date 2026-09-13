import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/api_client.dart';
import '../core/url_service.dart';

/// 提现单状态。后端取值 `pending` / `paid` / `rejected`；未知取值回落到
/// [WithdrawalStatus.pending]，保证后端新增状态时旧客户端不会崩在解析上。
enum WithdrawalStatus {
  /// 已提交、等管理员手动打款。用户端按产品要求显示为「待审核」。
  pending('pending', '待审核'),

  /// 管理员已打款。
  paid('paid', '已提现'),

  /// 管理员驳回，积分已退回余额。
  rejected('rejected', '已驳回');

  const WithdrawalStatus(this.wire, this.label);

  /// 后端字段值。
  final String wire;

  /// 用户端展示文案。
  final String label;

  static WithdrawalStatus parse(Object? raw) {
    final value = raw?.toString();
    for (final status in values) {
      if (status.wire == value) return status;
    }
    return WithdrawalStatus.pending;
  }
}

/// 一条提现记录。
class WithdrawalRecord {
  const WithdrawalRecord({
    required this.id,
    required this.userId,
    required this.username,
    required this.amount,
    required this.alipayAccount,
    required this.alipayName,
    required this.status,
    required this.note,
    required this.createdAt,
    required this.processedAt,
  });

  final int id;
  final int userId;
  final String username;

  /// 提现积分数，1 积分 = 1 CNY。
  final int amount;

  final String alipayAccount;
  final String? alipayName;
  final WithdrawalStatus status;

  /// 管理员备注（驳回原因等）。
  final String? note;

  final String? createdAt;
  final String? processedAt;

  factory WithdrawalRecord.fromJson(Map<String, Object?> json) =>
      WithdrawalRecord(
        id: (json['id'] as num?)?.toInt() ?? 0,
        userId: (json['userId'] as num?)?.toInt() ?? 0,
        username: json['username']?.toString() ?? '',
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        alipayAccount: json['alipayAccount']?.toString() ?? '',
        alipayName: json['alipayName']?.toString(),
        status: WithdrawalStatus.parse(json['status']),
        note: json['note']?.toString(),
        createdAt: json['createdAt']?.toString(),
        processedAt: json['processedAt']?.toString(),
      );
}

/// 我邀请的一位用户。
class InviteeItem {
  const InviteeItem({
    required this.id,
    required this.username,
    required this.maskedEmail,
    required this.avatarUrl,
    required this.joinedAt,
    required this.hasPremium,
    required this.rewarded,
  });

  final int id;
  final String username;

  /// 后端已脱敏的邮箱（`12***@qq.com`）。
  final String maskedEmail;

  final String? avatarUrl;
  final String? joinedAt;

  /// 该用户是否已开通 Cyrene Premium。
  final bool hasPremium;

  /// 该用户带来的积分是否已入账。
  final bool rewarded;

  factory InviteeItem.fromJson(Map<String, Object?> json) => InviteeItem(
    id: (json['id'] as num?)?.toInt() ?? 0,
    username: json['username']?.toString() ?? '',
    maskedEmail: json['maskedEmail']?.toString() ?? '',
    avatarUrl: json['avatarUrl']?.toString(),
    joinedAt: json['joinedAt']?.toString(),
    hasPremium: json['hasPremium'] == true,
    rewarded: json['rewarded'] == true,
  );
}

/// 邀请有礼总览。
class InviteSummary {
  const InviteSummary({
    required this.code,
    required this.points,
    required this.totalPoints,
    required this.rewardPerInvite,
    required this.minWithdrawal,
    required this.inviterName,
    required this.invitedCount,
    required this.rewardedCount,
    required this.invitees,
  });

  /// 我的邀请码；尚未生成时为 null。
  final String? code;

  /// 可提现积分余额（已提交提现的部分已扣除）。
  final int points;

  /// 累计获得积分，只增不减，用于展示。
  final int totalPoints;

  /// 每邀请一位用户开通 Premium 可得的积分。
  final int rewardPerInvite;

  /// 单笔提现的最小积分数。
  final int minWithdrawal;

  /// 我的邀请人用户名；未绑定时为 null。
  final String? inviterName;

  final int invitedCount;

  /// 已开通 Premium 并已发放奖励的人数。
  final int rewardedCount;

  final List<InviteeItem> invitees;

  bool get hasBoundInviter => inviterName != null && inviterName!.isNotEmpty;

  factory InviteSummary.fromJson(Map<String, Object?> json) {
    final inviter = json['invitedBy'];
    return InviteSummary(
      code: json['code']?.toString(),
      points: (json['points'] as num?)?.toInt() ?? 0,
      totalPoints: (json['totalPoints'] as num?)?.toInt() ?? 0,
      rewardPerInvite: (json['rewardPerInvite'] as num?)?.toInt() ?? 1,
      minWithdrawal: (json['minWithdrawal'] as num?)?.toInt() ?? 1,
      inviterName: inviter is Map ? inviter['username']?.toString() : null,
      invitedCount: (json['invitedCount'] as num?)?.toInt() ?? 0,
      rewardedCount: (json['rewardedCount'] as num?)?.toInt() ?? 0,
      invitees:
          (json['invitees'] as List?)
              ?.whereType<Map>()
              .map((e) => InviteeItem.fromJson(Map<String, Object?>.from(e)))
              .toList(growable: false) ??
          const [],
    );
  }
}

/// 写操作的统一结果：成功与否 + 可直接展示给用户的后端文案。
typedef InviteActionResult = ({bool ok, String message});

/// 邀请有礼服务：邀请码、绑定关系、积分与提现申请。
///
/// 单例。鉴权按既有约定，方法收 `token`（取自
/// `AccountSessionController.token`），与 [ListeningCardService] 一致；
/// 请求一律走 [ApiClient.apiFetch]，让 401 统一触发会话过期处理。
class InviteService {
  InviteService._();
  static final InviteService instance = InviteService._();

  String get _base => UrlService.instance.baseUrl;

  Map<String, String> _headers(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  Map<String, Object?> _decode(http.Response response) {
    try {
      final payload = jsonDecode(response.body);
      return payload is Map ? Map<String, Object?>.from(payload) : const {};
    } catch (_) {
      return const {};
    }
  }

  Map<String, Object?> _data(Map<String, Object?> json) {
    final data = json['data'];
    return data is Map ? Map<String, Object?>.from(data) : const {};
  }

  /// 把「HTTP 层 + 业务 code 层」两种失败折叠成一句可展示的文案。
  /// 后端的 400 提示（邀请码不存在、积分不足…）本身就是给用户看的，直接透传。
  InviteActionResult _result(http.Response response, String fallback) {
    final json = _decode(response);
    final code = (json['code'] as num?)?.toInt();
    final message = json['message']?.toString();
    if (code == 200) return (ok: true, message: message ?? fallback);
    return (ok: false, message: message ?? fallback);
  }

  /// 拉取邀请页总览。失败返回 null（由调用方展示重试）。
  Future<InviteSummary?> getSummary(String token) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '$_base/invite/summary',
        headers: _headers(token),
      );
      final json = _decode(response);
      if ((json['code'] as num?)?.toInt() != 200) return null;
      return InviteSummary.fromJson(_data(json));
    } catch (e) {
      debugPrint('[InviteService] getSummary error: $e');
      return null;
    }
  }

  /// 生成（或取回）我的邀请码。幂等，重复调用返回同一个码。
  Future<String?> generateCode(String token) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '$_base/invite/code',
        method: 'POST',
        headers: _headers(token),
      );
      final json = _decode(response);
      if ((json['code'] as num?)?.toInt() != 200) return null;
      final value = _data(json)['code']?.toString();
      return (value != null && value.isNotEmpty) ? value : null;
    } catch (e) {
      debugPrint('[InviteService] generateCode error: $e');
      return null;
    }
  }

  /// 手动绑定邀请人。绑定一次性、不可改，失败原因由后端给中文文案。
  Future<InviteActionResult> bindCode(String token, String code) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '$_base/invite/bind',
        method: 'POST',
        headers: _headers(token),
        body: jsonEncode({'code': code}),
      );
      return _result(response, '绑定失败，请稍后重试');
    } catch (e) {
      debugPrint('[InviteService] bindCode error: $e');
      return (ok: false, message: '网络错误，请稍后重试');
    }
  }

  /// 我的提现记录 + 当前可提现积分。失败返回 null。
  Future<({int points, int minWithdrawal, List<WithdrawalRecord> records})?>
  getWithdrawals(String token) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '$_base/invite/withdrawals',
        headers: _headers(token),
      );
      final json = _decode(response);
      if ((json['code'] as num?)?.toInt() != 200) return null;
      final data = _data(json);
      final list = data['withdrawals'];
      return (
        points: (data['points'] as num?)?.toInt() ?? 0,
        minWithdrawal: (data['minWithdrawal'] as num?)?.toInt() ?? 1,
        records: list is List
            ? list
                  .whereType<Map>()
                  .map(
                    (e) => WithdrawalRecord.fromJson(
                      Map<String, Object?>.from(e),
                    ),
                  )
                  .toList(growable: false)
            : const <WithdrawalRecord>[],
      );
    } catch (e) {
      debugPrint('[InviteService] getWithdrawals error: $e');
      return null;
    }
  }

  /// 提交提现申请。提交即冻结对应积分，等管理员手动打款后改状态。
  Future<InviteActionResult> submitWithdrawal({
    required String token,
    required int amount,
    required String alipayAccount,
    String? alipayName,
  }) async {
    try {
      final body = <String, Object?>{
        'amount': amount,
        'alipayAccount': alipayAccount,
      };
      // 姓名选填：为空时不下发，避免后端把空串当成填了个空名字存下来。
      if (alipayName != null && alipayName.trim().isNotEmpty) {
        body['alipayName'] = alipayName.trim();
      }
      final response = await ApiClient.instance.apiFetch(
        '$_base/invite/withdrawals',
        method: 'POST',
        headers: _headers(token),
        body: jsonEncode(body),
      );
      return _result(response, '提交失败，请稍后重试');
    } catch (e) {
      debugPrint('[InviteService] submitWithdrawal error: $e');
      return (ok: false, message: '网络错误，请稍后重试');
    }
  }
}
