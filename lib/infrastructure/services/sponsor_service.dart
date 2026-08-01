import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/sponsor.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';

/// 赞助服务（对应 Next.js demo/lib/services/sponsorService.ts）。
///
/// 单例。赞助墙列表、用户赞助状态、赞助记录创建、支付订单创建与查询、客户端 IP 获取。
class SponsorService {
  SponsorService._();
  static final SponsorService instance = SponsorService._();

  final Random _random = Random();

  Map<String, Object?> _decode(http.Response response) {
    try {
      final payload = jsonDecode(response.body);
      return payload is Map ? Map<String, Object?>.from(payload) : const {};
    } catch (_) {
      return const {};
    }
  }

  Map<String, String> _jsonHeaders() => {'Content-Type': 'application/json'};

  /// 获取赞助墙列表。
  Future<SponsorResponse<SponsorListResponse>> getSponsorList() async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/sponsors/list',
      );
      final json = _decode(response);
      final code = ((json['code'] as num?) ?? 500).toInt();
      final dataRaw = json['data'];
      SponsorListResponse? data;
      if (dataRaw is Map) {
        data = SponsorListResponse.fromJson(Map<String, Object?>.from(dataRaw));
      }
      return SponsorResponse<SponsorListResponse>(
        code: code,
        data: data,
        message: json['message']?.toString(),
      );
    } catch (e) {
      debugPrint('[SponsorService] getSponsorList failed: $e');
      return SponsorResponse<SponsorListResponse>(
        code: 500,
        message: e.toString(),
      );
    }
  }

  /// 查询用户赞助状态。
  Future<SponsorResponse<SponsorStatus>> getSponsorStatus(int userId) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/sponsors/status/$userId',
      );
      final json = _decode(response);
      final code = ((json['code'] as num?) ?? 500).toInt();
      final dataRaw = json['data'];
      SponsorStatus? data;
      if (dataRaw is Map) {
        data = SponsorStatus.fromJson(Map<String, Object?>.from(dataRaw));
      }
      return SponsorResponse<SponsorStatus>(
        code: code,
        data: data,
        message: json['message']?.toString(),
      );
    } catch (e) {
      debugPrint('[SponsorService] getSponsorStatus failed: $e');
      return SponsorResponse<SponsorStatus>(code: 500, message: e.toString());
    }
  }

  /// 创建赞助记录。
  Future<SponsorResponse<Map<String, Object?>>> createDonationRecord(
    CreateDonationRecordParams params,
  ) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/sponsors/create',
        method: 'POST',
        headers: _jsonHeaders(),
        body: jsonEncode(params.toJson()),
      );
      final json = _decode(response);
      final code = ((json['code'] as num?) ?? 500).toInt();
      final dataRaw = json['data'];
      return SponsorResponse<Map<String, Object?>>(
        code: code,
        data: dataRaw is Map ? Map<String, Object?>.from(dataRaw) : null,
        message: json['message']?.toString(),
      );
    } catch (e) {
      debugPrint('[SponsorService] createDonationRecord failed: $e');
      return SponsorResponse<Map<String, Object?>>(
        code: 500,
        message: e.toString(),
      );
    }
  }

  /// 创建支付订单。
  ///
  /// 与源码一致：网络错误时抛异常，由调用方处理。
  Future<Map<String, Object?>> createPayOrder(
    CreatePayOrderParams params,
  ) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/pay/create',
        method: 'POST',
        headers: _jsonHeaders(),
        body: jsonEncode(params.toJson()),
      );
      return _decode(response);
    } catch (e) {
      debugPrint('[SponsorService] createPayOrder failed: $e');
      rethrow;
    }
  }

  /// 查询支付状态。
  ///
  /// 与源码一致：网络错误时抛异常，由调用方处理。
  Future<Map<String, Object?>> queryPayStatus(String outTradeNo) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/pay/query',
        method: 'POST',
        headers: _jsonHeaders(),
        body: jsonEncode({'out_trade_no': outTradeNo}),
      );
      return _decode(response);
    } catch (e) {
      debugPrint('[SponsorService] queryPayStatus failed: $e');
      rethrow;
    }
  }

  /// 获取客户端 IP（使用后端 /ip-location 接口）。
  Future<String?> getClientIp() async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/ip-location',
      );
      final data = _decode(response);
      if (data['success'] == true && data['ip'] != null) {
        return data['ip'].toString();
      }
      return null;
    } catch (e) {
      debugPrint('[SponsorService] getClientIp failed: $e');
      return null;
    }
  }

  /// 生成订单号（与源码一致：时间戳 + 6 位随机数）。
  String generateOutTradeNo() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = 100000 + _random.nextInt(900000);
    return '$ts$rand';
  }
}
