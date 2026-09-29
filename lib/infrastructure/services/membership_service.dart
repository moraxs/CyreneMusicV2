import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/payment_order.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';

/// 会员中心服务：当前账号的支付订单流水。
///
/// 单例。鉴权沿用既有约定——方法接收 `token`（取自
/// `AccountSessionController.token`），请求一律走 [ApiClient.apiFetch]，
/// 让 401 统一触发会话过期处理。
///
/// 会员身份与定价不在这里：那是 [ListeningCardService.getCardStatus]
/// 的职责（后端「存量赞助者补授 Premium」的时间闸门只有一处），本服务只回答
/// 「这个账号下过哪些单、付了多少钱」。
class MembershipService {
  MembershipService._();
  static final MembershipService instance = MembershipService._();

  Map<String, String> _jsonHeaders(String token) => {
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

  /// 我的订单（含未支付单，按下单时间倒序）。失败返回 `null`，由调用方展示重试。
  Future<MembershipOrders?> getOrders(String token) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/member/orders',
        headers: _jsonHeaders(token),
      );
      final json = _decode(response);
      if (((json['code'] as num?) ?? 0).toInt() != 200) {
        debugPrint(
          '[MembershipService] getOrders failed: '
          '${json['message'] ?? '服务器错误'} (status=${response.statusCode})',
        );
        return null;
      }
      final data = json['data'];
      if (data is! Map) return null;
      return MembershipOrders.fromJson(Map<String, Object?>.from(data));
    } catch (e) {
      debugPrint('[MembershipService] getOrders error: $e');
      return null;
    }
  }
}
