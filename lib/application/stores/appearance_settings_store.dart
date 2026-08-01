import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color, ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

/// 外观偏好（对应原版 ThemeManager 的移动端子集）。
///
/// 持久化键名与原版一致（`theme_mode` / `follow_system_color` / `seed_color`），
/// 但默认值保持新版现状：跟随系统明暗 + HyperOS 静态配色（无种子色、不跟随
/// 系统主题色），原版的「默认亮色 + 深紫色」不再沿用。
///
/// 三个维度组合出最终配色（由 main.dart 映射到 MiuixThemeController）：
/// - [themeMode]：明暗（跟随系统 / 亮色 / 暗色）；
/// - [followSystemColor]：开启后走 Monet 壁纸取色（Android 12+）；
/// - [seedColor]：手动种子色（非空时按种子生成动态配色；null = HyperOS 默认）。
class AppearanceSettingsStore extends ChangeNotifier {
  AppearanceSettingsStore._();

  static final AppearanceSettingsStore instance = AppearanceSettingsStore._();

  static const _kThemeMode = 'theme_mode';
  static const _kFollowSystemColor = 'follow_system_color';
  static const _kSeedColor = 'seed_color';

  SharedPreferences? _prefs;
  ThemeMode _themeMode = ThemeMode.system;
  bool _followSystemColor = false;
  Color? _seedColor;

  ThemeMode get themeMode => _themeMode;
  bool get followSystemColor => _followSystemColor;
  Color? get seedColor => _seedColor;

  Future<void> init() async {
    final prefs = _prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt(_kThemeMode);
    if (modeIndex != null &&
        modeIndex >= 0 &&
        modeIndex < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[modeIndex];
    }
    _followSystemColor =
        prefs.getBool(_kFollowSystemColor) ?? _followSystemColor;
    final seed = prefs.getInt(_kSeedColor);
    if (seed != null) _seedColor = Color(seed);
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    _prefs?.setInt(_kThemeMode, mode.index);
    notifyListeners();
  }

  void setFollowSystemColor(bool value) {
    if (_followSystemColor == value) return;
    _followSystemColor = value;
    _prefs?.setBool(_kFollowSystemColor, value);
    notifyListeners();
  }

  /// 设置主题种子色；null 表示恢复 HyperOS 默认配色。
  /// 与原版一致：手动选色会自动关闭「跟随系统主题色」。
  void setSeedColor(Color? color) {
    final colorChanged = _seedColor?.toARGB32() != color?.toARGB32();
    if (!colorChanged && !_followSystemColor) return;
    _seedColor = color;
    if (color == null) {
      _prefs?.remove(_kSeedColor);
    } else {
      _prefs?.setInt(_kSeedColor, color.toARGB32());
    }
    if (_followSystemColor) {
      _followSystemColor = false;
      _prefs?.setBool(_kFollowSystemColor, false);
    }
    notifyListeners();
  }
}
