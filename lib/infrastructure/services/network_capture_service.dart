import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 单条网络捕获记录。
class NetworkCaptureEntry {
  const NetworkCaptureEntry({
    required this.time,
    required this.method,
    required this.url,
    this.requestBody,
    this.status,
    this.responseBody = '',
    this.error,
  });

  final DateTime time;
  final String method;
  final String url;
  final String? requestBody;

  /// HTTP 状态码；网络异常时为 null。
  final int? status;
  final String responseBody;
  final String? error;

  bool get isError => error != null;
}

/// 网络捕获器（开发者调试用）：拦截 [ApiClient.apiFetch] 的请求，记录
/// URL / 请求体 / 状态码 / 响应体，供开发者查看后端实际返回数据。
class NetworkCaptureService extends ChangeNotifier {
  NetworkCaptureService._();
  static final NetworkCaptureService instance = NetworkCaptureService._();

  static const _kEnabled = 'network_capture_enabled';
  static const _maxEntries = 200;
  static const _maxBodyLen = 8192;

  bool _enabled = false;
  bool _loaded = false;
  final List<NetworkCaptureEntry> _entries = [];

  /// 条目版本号：每追加/清空一次 +1，供列表页监听（避免整页反复重建）。
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  bool get enabled => _enabled;
  List<NetworkCaptureEntry> get entries => List.unmodifiable(_entries);

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kEnabled) ?? false;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, value);
    } catch (_) {}
  }

  /// 记录一次成功请求（含响应状态与响应体）。
  void capture({
    required String method,
    required String url,
    Object? requestBody,
    required int status,
    required String responseBody,
  }) {
    if (!_enabled) return;
    _add(NetworkCaptureEntry(
      time: DateTime.now(),
      method: method.toUpperCase(),
      url: url,
      requestBody: _stringifyBody(requestBody),
      status: status,
      responseBody: _truncate(responseBody),
    ));
  }

  /// 记录一次网络异常（无响应体）。
  void captureError({
    required String method,
    required String url,
    Object? requestBody,
    required String error,
  }) {
    if (!_enabled) return;
    _add(NetworkCaptureEntry(
      time: DateTime.now(),
      method: method.toUpperCase(),
      url: url,
      requestBody: _stringifyBody(requestBody),
      error: error,
    ));
  }

  void clear() {
    _entries.clear();
    revision.value++;
  }

  void _add(NetworkCaptureEntry entry) {
    _entries.add(entry);
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    revision.value++;
  }

  static String? _stringifyBody(Object? body) {
    if (body == null) return null;
    if (body is String) return _truncate(body);
    try {
      return _truncate(const JsonEncoder.withIndent('  ').convert(body));
    } catch (_) {
      return _truncate(body.toString());
    }
  }

  static String _truncate(String s) {
    if (s.length <= _maxBodyLen) return s;
    return '${s.substring(0, _maxBodyLen)}…（已截断，原 ${s.length} 字符）';
  }
}
