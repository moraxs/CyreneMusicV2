import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/auth/auth_repository.dart';
import '../../domain/models/user.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';

/// 用户认证服务（对应 Next.js demo/lib/services/authService.ts）。
///
/// 单例。登录 / 注册 / 密码重置 / token 校验。
class AuthService implements AuthRepository {
  AuthService({ApiClient? apiClient, UrlService? urls})
    : _apiClient = apiClient ?? ApiClient.instance,
      _urls = urls ?? UrlService.instance;

  static final AuthService instance = AuthService();

  final ApiClient _apiClient;
  final UrlService _urls;

  Map<String, String> _headers({String? token}) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Map<String, Object?> _decode(http.Response response) {
    try {
      final payload = jsonDecode(response.body);
      return payload is Map ? Map<String, Object?>.from(payload) : const {};
    } catch (_) {
      return const {};
    }
  }

  bool _ok(http.Response response) =>
      response.statusCode >= 200 && response.statusCode < 300;

  // --- Authentication ---

  /// 登录。成功时 [AuthResponse.data] 为包含 token 与用户信息的原始载荷。
  @override
  Future<AuthResponse> login(String account, String pass) async {
    try {
      final response = await _apiClient.apiFetch(
        '${_urls.baseUrl}/auth/login',
        method: 'POST',
        headers: _headers(),
        body: jsonEncode({'account': account, 'password': pass}),
      );
      final data = _decode(response);
      if (_ok(response) && data['data'] != null) {
        return AuthResponse(
          success: true,
          message: data['message']?.toString(),
          data: data['data'],
          user: _parseUser(data['data']),
        );
      }
      return AuthResponse(
        success: false,
        message: data['message']?.toString() ?? '登录失败',
      );
    } catch (e) {
      return AuthResponse(success: false, message: '网络错误');
    }
  }

  Future<AuthResponse> register(
    String email,
    String username,
    String password,
    String code,
  ) async {
    try {
      final response = await _apiClient.apiFetch(
        '${_urls.baseUrl}/auth/register',
        method: 'POST',
        headers: _headers(),
        body: jsonEncode({
          'email': email,
          'username': username,
          'password': password,
          'code': code,
        }),
      );
      final data = _decode(response);
      return AuthResponse(
        success: _ok(response),
        message: data['message']?.toString(),
        data: data['data'],
      );
    } catch (e) {
      return AuthResponse(success: false, message: '网络错误');
    }
  }

  Future<AuthResponse> sendRegisterCode(String email, String username) async {
    try {
      final response = await _apiClient.apiFetch(
        '${_urls.baseUrl}/auth/register/send-code',
        method: 'POST',
        headers: _headers(),
        body: jsonEncode({'email': email, 'username': username}),
      );
      final data = _decode(response);
      return AuthResponse(
        success: _ok(response),
        message: data['message']?.toString(),
      );
    } catch (e) {
      return AuthResponse(success: false, message: '网络错误');
    }
  }

  Future<({bool success, bool enabled})> checkRegistrationStatus() async {
    try {
      final response = await _apiClient.apiFetch(
        '${_urls.baseUrl}/auth/registration-status',
        headers: _headers(),
      );
      final data = _decode(response);
      if (_ok(response)) {
        final enabledData = data['data'];
        final enabled = enabledData is Map
            ? enabledData['enabled'] == true
            : false;
        return (success: true, enabled: enabled);
      }
      return const (success: false, enabled: false);
    } catch (_) {
      return const (success: false, enabled: false);
    }
  }

  // --- Password Reset ---

  Future<AuthResponse> sendResetCode(String email) async {
    try {
      final response = await _apiClient.apiFetch(
        '${_urls.baseUrl}/auth/reset-password/send-code',
        method: 'POST',
        headers: _headers(),
        body: jsonEncode({'email': email}),
      );
      final data = _decode(response);
      return AuthResponse(
        success: _ok(response),
        message: data['message']?.toString(),
      );
    } catch (e) {
      return AuthResponse(success: false, message: '网络错误');
    }
  }

  Future<AuthResponse> resetPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    try {
      final response = await _apiClient.apiFetch(
        '${_urls.baseUrl}/auth/reset-password',
        method: 'POST',
        headers: _headers(),
        body: jsonEncode({
          'email': email,
          'code': code,
          'newPassword': newPassword,
        }),
      );
      final data = _decode(response);
      return AuthResponse(
        success: _ok(response),
        message: data['message']?.toString(),
      );
    } catch (e) {
      return AuthResponse(success: false, message: '网络错误');
    }
  }

  // --- User Info ---

  /// 校验本地 token 是否仍有效。网络错误时返回 true，避免误踢。
  /// 鉴权失败时 [ApiClient] 会触发会话过期处理。
  @override
  Future<bool> validateToken(String token) async {
    if (token.isEmpty) return false;
    try {
      final response = await _apiClient.apiFetch(
        '${_urls.baseUrl}/accounts/bindings',
        headers: _headers(token: token),
      );
      if (ApiClient.isAuthFailureStatus(response.statusCode)) return false;
      if (!_ok(response)) return true; // 5xx 不强制登出

      final result = _decode(response);
      if (result.isNotEmpty && ApiClient.isAuthFailurePayload(result)) {
        return false;
      }
      if (result['code'] == 200 || result['data'] != null) return true;
      return true;
    } catch (_) {
      return true;
    }
  }

  User? _parseUser(Object? data) {
    if (data is! Map) return null;
    final payload = Map<String, Object?>.from(data);
    final nestedUser = payload['user'];
    return User.fromJson(
      nestedUser is Map ? Map<String, Object?>.from(nestedUser) : payload,
    );
  }
}
