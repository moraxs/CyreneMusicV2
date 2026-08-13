import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「忽略此版本」的持久化。
///
/// 语义是**忽略该版本及更低**：记下版本号后，只有更高的版本才会再次提示。
/// 「稍后提醒」不落这里——它只在本次启动内生效，见 [UpdateController]。
class UpdatePreferences {
  factory UpdatePreferences({SharedPreferences? preferences}) =>
      UpdatePreferences._(preferences);

  UpdatePreferences._(this._preferences);

  static const String _keyIgnoredVersion = 'ignored_update_version';

  SharedPreferences? _preferences;
  Future<String?> readIgnoredVersion() async {
    try {
      return (await _instance).getString(_keyIgnoredVersion);
    } catch (e) {
      debugPrint('[UpdatePreferences] 读取忽略版本失败: $e');
      return null;
    }
  }

  Future<void> writeIgnoredVersion(String version) async {
    try {
      await (await _instance).setString(_keyIgnoredVersion, version);
    } catch (e) {
      debugPrint('[UpdatePreferences] 写入忽略版本失败: $e');
    }
  }

  Future<void> clearIgnoredVersion() async {
    try {
      await (await _instance).remove(_keyIgnoredVersion);
    } catch (e) {
      debugPrint('[UpdatePreferences] 清除忽略版本失败: $e');
    }
  }

  Future<SharedPreferences> get _instance async =>
      _preferences ??= await SharedPreferences.getInstance();
}
