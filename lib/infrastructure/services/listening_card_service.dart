import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/cyrene_config.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';
import 'cyrene_config_service.dart';

/// Cyrene Premium 服务：一次性买断，付款后后端自动下发加密 .cyrene 音源配置。
/// 定价由后端 config.json 的 pay.card_price 统一管理，前端经 [/getCardStatus]
/// 下发的 price 动态渲染，默认兜底见 [defaultCardPrice]。
///
/// 单例。组合复用 [SponsorService] 的支付链路（订单轮询走现有 `/pay/query`）。
/// 鉴权按现有约定：方法接收 `token`（从 `AccountSessionController.token` 取），
/// 与 [AuthService] / [ListeningStatsService] 一致。
class ListeningCardService {
  ListeningCardService._();
  static final ListeningCardService instance = ListeningCardService._();

  Map<String, String> _jsonHeaders(String token) =>
      {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};

  Map<String, Object?> _decode(http.Response response) {
    try {
      final payload = jsonDecode(response.body);
      return payload is Map ? Map<String, Object?>.from(payload) : const {};
    } catch (_) {
      return const {};
    }
  }

  /// 下单购买 Cyrene Premium。
  ///
  /// [type] 支付方式：`alipay` / `wxpay`。后端金额以 config.json 的 pay.card_price
  /// 为准、服务端生成订单号、
  /// `payment_type='card'`。返回订单号与网关支付数据（含 `pay_info/qrcode/payurl/urlscheme`）。
  Future<({String outTradeNo, Map<String, Object?> payInfo})?> purchaseCard({
    required String token,
    required String type,
    required String clientip,
    String? device,
    String? method,
  }) async {
    try {
      // device/method 可选：仅在非空时下发，避免后端 schema 校验把 null 当成
      // "Expected string" 拒掉整笔订单（后端 device/method 都是 string 类型，不接受 null）。
      final body = <String, Object?>{
        'type': type,
        'clientip': clientip,
      };
      if (device != null && device.isNotEmpty) body['device'] = device;
      if (method != null && method.isNotEmpty) body['method'] = method;
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/card/purchase',
        method: 'POST',
        headers: _jsonHeaders(token),
        body: jsonEncode(body),
      );
      final json = _decode(response);
      final code = ((json['code'] as num?) ?? 0).toInt();
      if (code != 200) {
        debugPrint(
          '[ListeningCardService] purchaseCard failed: '
          '${json['message'] ?? '服务器错误'} (code=$code, status=${response.statusCode})',
        );
        return null;
      }
      final dataRaw = json['data'];
      if (dataRaw is! Map) return null;
      final outTradeNo = dataRaw['out_trade_no']?.toString() ?? '';
      final payInfo =
          dataRaw['pay_info'] is Map
              ? Map<String, Object?>.from(dataRaw['pay_info'] as Map)
              : <String, Object?>{};
      return (outTradeNo: outTradeNo, payInfo: payInfo);
    } catch (e) {
      debugPrint('[ListeningCardService] purchaseCard error: $e');
      return null;
    }
  }

  /// 查询 Cyrene Premium 持有状态（后端含存量赞助者 lazy backfill）。
  ///
  /// 返回值含 [price]：当前 Cyrene Premium 标准定价（元），取自后端 config.json 的
  /// pay.card_price。前端据此动态渲染按钮/文案，调价时无需改前端。拉取失败
  /// 时 price 回落到本地默认 5.88，保证 UI 不崩。
  Future<({bool hasCard, String? grantedAt, bool isSponsor, double price})?>
  getCardStatus(String token) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/card/status',
        headers: _jsonHeaders(token),
      );
      final json = _decode(response);
      final code = ((json['code'] as num?) ?? 0).toInt();
      if (code != 200) return null;
      final dataRaw = json['data'];
      if (dataRaw is! Map) return null;
      final data = Map<String, Object?>.from(dataRaw);
      final price = ((data['price'] as num?) ?? defaultCardPrice).toDouble();
      return (
        hasCard: data['hasCard'] == true,
        grantedAt: data['grantedAt']?.toString(),
        isSponsor: data['isSponsor'] == true,
        price: price > 0 ? price : defaultCardPrice,
      );
    } catch (e) {
      debugPrint('[ListeningCardService] getCardStatus error: $e');
      return null;
    }
  }

  /// Cyrene Premium 本地兜底定价（元）。仅在后端未返回 price 时使用，
  /// 真实定价以 [/card/status] 返回的 price 为准。
  static const double defaultCardPrice = 5.88;

  /// 拉取下发的加密 .cyrene 配置字节流。
  ///
  /// 持卡用户返回解密后的 [CyreneConfig]；未持卡（HTTP 402）返回 `null`
  /// （非鉴权失败，不会触发 [ApiClient] 的会话过期处理）；网络错误抛异常。
  Future<CyreneConfig?> fetchCardConfig(String token) async {
    http.Response response;
    try {
      response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/card/config',
        headers: _jsonHeaders(token),
      );
    } catch (e) {
      debugPrint('[ListeningCardService] fetchCardConfig error: $e');
      rethrow;
    }
    // 402 = 未持卡，非鉴权失败。返回 null 让上层走「未购买」分支，不触发登出。
    if (response.statusCode == 402) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '[ListeningCardService] fetchCardConfig status ${response.statusCode}',
      );
      return null;
    }
    final bytes = Uint8List.fromList(response.bodyBytes);
    final config = await CyreneConfigService.instance.decrypt(bytes);
    if (config == null) {
      debugPrint('[ListeningCardService] 下发的 .cyrene 解密失败');
    }
    return config;
  }
}
