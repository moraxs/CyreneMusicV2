import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/account.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';

/// 账号绑定与第三方登录服务（对应 Next.js demo/lib/services/accountService.ts）。
///
/// 单例。覆盖网易云 / 酷狗 / QQ 的绑定查询、解绑、二维码登录、手机验证码登录。
class AccountService {
  AccountService._();
  static final AccountService instance = AccountService._();

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

  int get _timestamp => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // --- 绑定查询 / 解绑 ---

  Future<AccountBindings?> getBindings(String token) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/accounts/bindings',
        headers: _jsonHeaders(token),
      );
      final result = _decode(response);
      if (result['code'] == 200 && result['data'] is Map) {
        return AccountBindings.fromJson(
          Map<String, Object?>.from(result['data'] as Map),
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> unbindNetease(String token) =>
      _unbind(token, '${UrlService.instance.baseUrl}/accounts/netease/unbind');

  Future<bool> unbindKugou(String token) =>
      _unbind(token, '${UrlService.instance.baseUrl}/accounts/kugou/unbind');

  Future<bool> unbindQq(String token) =>
      _unbind(token, '${UrlService.instance.baseUrl}/accounts/qq/unbind');

  Future<bool> _unbind(String token, String url) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        url,
        method: 'POST',
        headers: _jsonHeaders(token),
        body: jsonEncode({'timestamp': _timestamp}),
      );
      final result = _decode(response);
      return result['code'] == 200;
    } catch (_) {
      return false;
    }
  }

  // --- 网易云二维码登录 ---

  Future<String?> getNeteaseQRKey() async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/login/qr/key',
      );
      final result = _decode(response);
      final data = result['data'];
      return data is Map ? data['unikey']?.toString() : null;
    } catch (_) {
      return null;
    }
  }

  Future<NeteaseQrData?> getNeteaseQRData(String key) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/login/qr/create?key=${Uri.encodeQueryComponent(key)}',
      );
      final result = _decode(response);
      final data = result['data'];
      return data is Map
          ? NeteaseQrData.fromJson(Map<String, Object?>.from(data))
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Object?>> checkNeteaseQR(String key, int userId) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/login/qr/check?key=${Uri.encodeQueryComponent(key)}&userId=$userId',
      );
      return _decode(response);
    } catch (_) {
      return const {'code': 500, 'message': '检查失败'};
    }
  }

  // --- 酷狗二维码登录 ---

  Future<Map<String, Object?>?> getKugouQRData() async {
    try {
      final response = await ApiClient.instance.apiFetch(
        // 后端只注册了 `/kugou/login/qr/key`（没有 `/create`）；返回
        // `{ code, data: { qrcode, expire, qrUrl } }`。`qrcode` 用于 check，
        // `qrUrl` 用于本地生成二维码图片。
        '${UrlService.instance.baseUrl}/kugou/login/qr/key',
      );
      final result = _decode(response);
      if (result['code'] == 200) {
        return result['data'] is Map
            ? Map<String, Object?>.from(result['data'] as Map)
            : null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Object?>> checkKugouQR(String qrcode, int userId) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/kugou/login/qr/check?qrcode=${Uri.encodeQueryComponent(qrcode)}&userId=$userId',
      );
      return _decode(response);
    } catch (_) {
      return const {'code': 500, 'message': '检查失败'};
    }
  }

  // --- QQ 二维码登录 ---

  Future<Map<String, Object?>?> getQqQRData() async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/qq/login/qr/create',
      );
      final result = _decode(response);
      if (result['code'] == 200) {
        return result['data'] is Map
            ? Map<String, Object?>.from(result['data'] as Map)
            : null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Object?>> checkQqQR(
    String ptqrtoken,
    String qrsig,
    int userId,
  ) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/qq/login/qr/check?ptqrtoken=${Uri.encodeQueryComponent(ptqrtoken)}&qrsig=${Uri.encodeQueryComponent(qrsig)}&userId=$userId',
      );
      return _decode(response);
    } catch (_) {
      return const {'code': 500, 'message': '检查失败'};
    }
  }

  Future<bool> isNeteaseBound(String token) async {
    try {
      final data = await getBindings(token);
      return data?.netease.bound ?? false;
    } catch (_) {
      return false;
    }
  }

  // --- 网易云手机验证码登录 ---

  Future<CaptchaResult> sendNeteaseCaptcha(
    String phone, {
    String ctcode = '86',
  }) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/captcha/sent',
        method: 'POST',
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'phone': phone, 'ctcode': ctcode},
      );
      return CaptchaResult.fromJson(_decode(response));
    } catch (_) {
      return const CaptchaResult(code: 500, message: '网络错误');
    }
  }

  Future<CaptchaResult> verifyNeteaseCaptcha(
    String phone,
    String captcha, {
    String ctcode = '86',
  }) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/captcha/verify',
        method: 'POST',
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'phone': phone, 'captcha': captcha, 'ctcode': ctcode},
      );
      return CaptchaResult.fromJson(_decode(response));
    } catch (_) {
      return const CaptchaResult(code: 500, message: '网络错误');
    }
  }

  Future<CaptchaResult> loginNeteaseByCellphone(
    String token,
    String phone,
    String captcha, {
    String ctcode = '86',
  }) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/login/cellphone',
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': 'Bearer $token',
        },
        body: {'phone': phone, 'captcha': captcha, 'ctcode': ctcode},
      );
      return CaptchaResult.fromJson(_decode(response));
    } catch (_) {
      return const CaptchaResult(code: 500, message: '网络错误');
    }
  }
}
