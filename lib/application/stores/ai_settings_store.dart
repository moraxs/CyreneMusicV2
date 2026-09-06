import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/ai/ai_models.dart';
import '../../infrastructure/cache/song_cache_crypto.dart';

/// AI 功能的配置：兼容路由、Base URL、API Key、模型。
///
/// key 用 [SongCacheCrypto] 封装后再落 SharedPreferences。**这只是不让 key
/// 明文躺在磁盘上**——密钥由 App 内固定口令派生，拿到安装包的人一样能解出来，
/// 它挡的是「随手翻到偏好文件」，不是真正的机密保护。要真正保密得上系统钥匙串
/// （flutter_secure_storage），那是另一个依赖。
class AiSettingsStore extends ChangeNotifier {
  AiSettingsStore._();

  static final AiSettingsStore instance = AiSettingsStore._();

  static const _kEnabled = 'ai_enabled';
  static const _kRoute = 'ai_route';
  static const _kBaseUrl = 'ai_base_url';
  static const _kApiKey = 'ai_api_key_sealed';
  static const _kModel = 'ai_model';

  bool _enabled = false;
  AiRoute _route = AiRoute.openai;
  String _baseUrl = '';
  String _apiKey = '';
  String _model = '';
  bool _initialized = false;

  bool get enabled => _enabled;
  AiRoute get route => _route;
  String get baseUrl => _baseUrl;
  String get apiKey => _apiKey;
  String get model => _model;
  bool get isInitialized => _initialized;

  /// 配置齐了才谈得上调用——UI 用它决定入口是灰的还是亮的。
  bool get isConfigured =>
      _enabled &&
      _baseUrl.trim().isNotEmpty &&
      _apiKey.trim().isNotEmpty &&
      _model.trim().isNotEmpty;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kEnabled) ?? false;
      _route = AiRoute.fromWireName(prefs.getString(_kRoute));
      _baseUrl = prefs.getString(_kBaseUrl) ?? '';
      _model = prefs.getString(_kModel) ?? '';
      _apiKey = _unseal(prefs.getString(_kApiKey));
    } catch (error) {
      debugPrint('[AiSettings] 读取失败: $error');
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    await _write((prefs) => prefs.setBool(_kEnabled, value));
  }

  /// 换路由时，如果模型/地址还是空的或还是上一家的默认值，就顺手换成新路由的
  /// 建议值——两家的模型名完全不通用，留着旧值只会让下一次请求 404。
  Future<void> setRoute(AiRoute value) async {
    if (_route == value) return;
    final previous = _route;
    _route = value;
    if (_model.trim().isEmpty || _model == previous.suggestedModel) {
      _model = value.suggestedModel;
    }
    if (_baseUrl.trim().isEmpty || _baseUrl == previous.baseUrlHint) {
      _baseUrl = value.baseUrlHint;
    }
    notifyListeners();
    await _write((prefs) async {
      await prefs.setString(_kRoute, value.wireName);
      await prefs.setString(_kModel, _model);
      await prefs.setString(_kBaseUrl, _baseUrl);
    });
  }

  Future<void> setBaseUrl(String value) async {
    final trimmed = value.trim();
    if (_baseUrl == trimmed) return;
    _baseUrl = trimmed;
    notifyListeners();
    await _write((prefs) => prefs.setString(_kBaseUrl, trimmed));
  }

  Future<void> setModel(String value) async {
    final trimmed = value.trim();
    if (_model == trimmed) return;
    _model = trimmed;
    notifyListeners();
    await _write((prefs) => prefs.setString(_kModel, trimmed));
  }

  Future<void> setApiKey(String value) async {
    final trimmed = value.trim();
    if (_apiKey == trimmed) return;
    _apiKey = trimmed;
    notifyListeners();
    await _write((prefs) async {
      if (trimmed.isEmpty) {
        await prefs.remove(_kApiKey);
        return;
      }
      await prefs.setString(_kApiKey, _seal(trimmed));
    });
  }

  /// 打码后的 key，给设置页显示用（别把明文摆在屏幕上）。
  String get maskedApiKey {
    if (_apiKey.isEmpty) return '';
    if (_apiKey.length <= 8) return '••••••••';
    return '${_apiKey.substring(0, 4)}••••${_apiKey.substring(_apiKey.length - 4)}';
  }

  static String _seal(String plain) =>
      base64Encode(SongCacheCrypto.seal(utf8.encode(plain)));

  static String _unseal(String? sealed) {
    if (sealed == null || sealed.isEmpty) return '';
    try {
      final opened = SongCacheCrypto.open(
        Uint8List.fromList(base64Decode(sealed)),
      );
      if (opened == null) return '';
      return utf8.decode(opened);
    } catch (error) {
      // 存坏了就当没配过，让用户重填——总好过带着乱码 key 一直 401。
      debugPrint('[AiSettings] API Key 解密失败: $error');
      return '';
    }
  }

  Future<void> _write(Future<void> Function(SharedPreferences) action) async {
    try {
      await action(await SharedPreferences.getInstance());
    } catch (error) {
      debugPrint('[AiSettings] 保存失败: $error');
    }
  }
}
