import 'dart:convert';

import 'package:http/http.dart' as http;

/// 鉴权失效识别与会话处理（对应 Next.js demo/lib/services/apiClient.ts）。
///
/// 各 service 带 Authorization 的请求应使用 [apiFetch]，而非裸 [http] 调用，
/// 以便在 401/403 或业务鉴权失败时统一触发会话过期处理。
class ApiClient {
  factory ApiClient({http.Client? client}) => ApiClient._(client);
  ApiClient._(this._client);

  static final ApiClient instance = ApiClient();

  http.Client? _client;
  http.Client get client => _client ??= http.Client();

  /// 注入自定义 [http.Client]（如测试 mock）。
  void useClient(http.Client client) => _client = client;

  /// 会话过期回调。由 [AppDependencies] 注入，连接到 AuthStore 清态与 UI 提示。
  /// 回调内部应自行判断当前是否已登录，避免无谓触发。
  void Function(String? reason)? onSessionExpired;

  static const Duration _cooldown = Duration(seconds: 4);
  DateTime _lastHandledAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _handling = false;

  /// 带鉴权感知的请求：请求携带 Authorization 时，识别 401/403 或 body 鉴权失败，
  /// 触发 [handleSessionExpired]。
  Future<http.Response> apiFetch(
    String url, {
    String method = 'GET',
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    final response = await _send(
      url,
      method: method,
      headers: headers,
      body: body,
      encoding: encoding,
    );

    if (!_hasAuthorization(headers)) return response;

    if (isAuthFailureStatus(response.statusCode)) {
      handleSessionExpired(null);
      return response;
    }

    final contentType = response.headers['content-type'] ?? '';
    if (contentType.contains('application/json')) {
      try {
        final data = jsonDecode(response.body);
        if (data is Map && isAuthFailurePayload(data)) {
          handleSessionExpired(null);
        }
      } catch (_) {
        // 非 JSON 或解析失败，忽略。
      }
    }
    return response;
  }

  Future<http.Response> _send(
    String url, {
    required String method,
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) {
    final uri = Uri.parse(url);
    switch (method.toUpperCase()) {
      case 'POST':
        return client.post(
          uri,
          headers: headers,
          body: body,
          encoding: encoding,
        );
      case 'PUT':
        return client.put(
          uri,
          headers: headers,
          body: body,
          encoding: encoding,
        );
      case 'DELETE':
        return client.delete(uri, headers: headers, body: body);
      default:
        return client.get(uri, headers: headers);
    }
  }

  static bool _hasAuthorization(Map<String, String>? headers) {
    if (headers == null) return false;
    return headers.keys.any((k) => k.toLowerCase() == 'authorization');
  }

  /// HTTP 401 / 403 视为鉴权失败。
  static bool isAuthFailureStatus(int status) => status == 401 || status == 403;

  /// 部分接口 HTTP 200，用 body.code / message 表达鉴权失败。
  static bool isAuthFailurePayload(Map data) {
    final code = data['code'] ?? data['status'];
    if (code == 401 || code == 40101) return true;

    final msg = (data['message'] ?? data['msg'] ?? data['error'] ?? '')
        .toString();
    if (msg.isEmpty) return false;
    final lower = msg.toLowerCase();

    final r1 = RegExp(
      r'(invalid|expired|失效|过期).{0,12}(token|jwt|凭证|登录)',
      caseSensitive: false,
    );
    final r2 = RegExp(
      r'(token|jwt|凭证).{0,12}(invalid|expired|失效|过期)',
      caseSensitive: false,
    );
    final r3 = RegExp(
      r'unauthorized|unauthorised|未登录|登录已失效|登录已过期|登录失效|登录过期|鉴权失败',
      caseSensitive: false,
    );

    return r1.hasMatch(lower) || r2.hasMatch(lower) || r3.hasMatch(lower);
  }

  /// 登录态失效：带 4 秒冷却，避免并发请求连弹。具体清态 / 提示 / 打开登录由回调负责。
  void handleSessionExpired(String? reason) {
    if (_handling) return;
    final now = DateTime.now();
    if (now.difference(_lastHandledAt) < _cooldown) return;

    _handling = true;
    _lastHandledAt = now;
    try {
      onSessionExpired?.call(reason);
    } finally {
      _handling = false;
    }
  }
}
