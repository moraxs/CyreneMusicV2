import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一起听的偏好：总开关、房间是否私有、是否显示弹幕。
///
/// 开关打开后，一播歌就会自动开一个房间（房间号由服务端生成，见
/// [TogetherController.autoHostIfNeeded]）；私有房不进大厅，只能凭房间号加入。
class TogetherSettingsStore extends ChangeNotifier {
  TogetherSettingsStore._();

  static final TogetherSettingsStore instance = TogetherSettingsStore._();

  static const _kEnabled = 'together_enabled';
  static const _kPrivate = 'together_private_room';
  static const _kDanmaku = 'together_danmaku_visible';
  static const _kAllowGuestControl = 'together_allow_guest_control';

  bool _enabled = false;
  bool _isPrivate = false;
  bool _danmakuVisible = true;
  bool _allowGuestControl = false;
  bool _initialized = false;

  bool get enabled => _enabled;
  bool get isPrivate => _isPrivate;
  bool get danmakuVisible => _danmakuVisible;

  /// 是否允许听众点歌。默认关：房间本来是「听房主在放什么」，放开与否由房主定。
  bool get allowGuestControl => _allowGuestControl;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kEnabled) ?? false;
      _isPrivate = prefs.getBool(_kPrivate) ?? false;
      _danmakuVisible = prefs.getBool(_kDanmaku) ?? true;
      _allowGuestControl = prefs.getBool(_kAllowGuestControl) ?? false;
    } catch (error) {
      debugPrint('[TogetherSettings] 读取失败: $error');
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    await _save(_kEnabled, value);
  }

  Future<void> setPrivate(bool value) async {
    if (_isPrivate == value) return;
    _isPrivate = value;
    notifyListeners();
    await _save(_kPrivate, value);
  }

  Future<void> setDanmakuVisible(bool value) async {
    if (_danmakuVisible == value) return;
    _danmakuVisible = value;
    notifyListeners();
    await _save(_kDanmaku, value);
  }

  Future<void> setAllowGuestControl(bool value) async {
    if (_allowGuestControl == value) return;
    _allowGuestControl = value;
    notifyListeners();
    await _save(_kAllowGuestControl, value);
  }

  Future<void> _save(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (error) {
      debugPrint('[TogetherSettings] 保存失败: $error');
    }
  }
}
