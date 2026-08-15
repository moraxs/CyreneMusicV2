import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/url_service.dart';

/// 号池账号条目（对应后端 /webui/pool 返回的单项）。
class AccountPoolEntry {
  const AccountPoolEntry({
    required this.id,
    required this.platformName,
    required this.status,
    required this.detail,
    this.updatedAt,
  });

  final String id;
  final String platformName;

  /// 账号状态：valid / invalid / empty。
  final String status;
  final Map<String, Object?> detail;
  final String? updatedAt;

  factory AccountPoolEntry.fromJson(Map<String, Object?> json) =>
      AccountPoolEntry(
        id: json['id']?.toString() ?? '',
        platformName: json['platformName']?.toString() ?? '',
        status: json['status']?.toString() ?? 'empty',
        detail: json['detail'] is Map
            ? Map<String, Object?>.from(json['detail'] as Map)
            : const {},
        updatedAt: json['updatedAt']?.toString(),
      );

  bool get isKugou => id == 'kugou';
}

/// 号池扫码二维码信息。
class PoolQrKey {
  const PoolQrKey({
    required this.qrcode,
    required this.qrUrl,
    required this.expire,
  });

  final String qrcode;
  final String qrUrl;
  final int expire;
}

/// 号池扫码状态（status 语义与后端 checkQrStatus 对齐：
/// 0 过期 / 1 等待扫码 / 2 待确认 / 4 成功）。
class PoolQrStatus {
  const PoolQrStatus({required this.status, this.message = ''});

  final int status;
  final String message;

  bool get success => status == 4;
  bool get expired => status == 0;
}

/// 号池管理服务：调用后端 /webui 接口。
///
/// 使用独立 [http.Client] 而非 [ApiClient]，避免触发应用用户会话失效逻辑
/// （WebUI 管理会话与应用用户会话相互独立）。
class AccountPoolService {
  AccountPoolService._();
  static final AccountPoolService instance = AccountPoolService._();

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

  /// 登录 WebUI 管理后台，成功返回会话 token，失败返回 null。
  Future<String?> login(String password) async {
    final resp = await _client.post(
      Uri.parse('$_base/webui/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': 'admin', 'password': password}),
    );
    final data = _decode(resp);
    if (data['success'] == true) {
      final d = data['data'];
      if (d is Map) {
        final token = d['token']?.toString();
        if (token != null && token.isNotEmpty) return token;
      }
    }
    return null;
  }

  /// 获取号池账号列表。
  Future<List<AccountPoolEntry>> getPool(String token) async {
    final resp = await _client.get(
      Uri.parse('$_base/webui/pool'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _decode(resp);
    if (data['success'] != true) return const [];
    final list = data['data'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => AccountPoolEntry.fromJson(Map<String, Object?>.from(e)))
        .toList(growable: false);
  }

  /// 发起号池扫码，返回二维码信息，失败返回 null。
  Future<PoolQrKey?> startQr(String token, String platformId) async {
    final resp = await _client.get(
      Uri.parse('$_base/webui/pool/$platformId/login/qr'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _decode(resp);
    if (data['success'] != true) return null;
    final d = data['data'];
    if (d is! Map) return null;
    return PoolQrKey(
      qrcode: d['qrcode']?.toString() ?? '',
      qrUrl: d['qrUrl']?.toString() ?? '',
      expire: d['expire'] is num ? (d['expire'] as num).toInt() : 300,
    );
  }

  /// 检查号池扫码状态。
  Future<PoolQrStatus> checkQr(
    String token,
    String platformId,
    String qrcode,
  ) async {
    final resp = await _client.get(
      Uri.parse(
        '$_base/webui/pool/$platformId/login/check'
        '?qrcode=${Uri.encodeQueryComponent(qrcode)}',
      ),
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _decode(resp);
    final d = data['data'];
    final status =
        d is Map && d['status'] is num ? (d['status'] as num).toInt() : -1;
    final message = d is Map ? d['message']?.toString() ?? '' : '';
    return PoolQrStatus(status: status, message: message);
  }
}
