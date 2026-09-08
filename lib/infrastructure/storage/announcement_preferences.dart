import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 公告「不再提示」的持久化。
///
/// 只存一个编号（用户最后一次勾选「不再提示」时那条公告的 id），语义是
/// **压住该编号及更早的公告**：之后只有编号更大的公告才会重新自动弹窗。
/// 和 [UpdatePreferences] 的「忽略此版本及更低」是同一个套路，只是比较的
/// 是公告编号而非版本号。
///
/// 没勾选就关掉弹窗的话这里不写任何东西——下次启动照常再弹，这正是「勾选」
/// 这个交互存在的意义。
class AnnouncementPreferences {
  factory AnnouncementPreferences({SharedPreferences? preferences}) =>
      AnnouncementPreferences._(preferences);

  AnnouncementPreferences._(this._preferences);

  static const String _keyDismissedId = 'dismissed_announcement_id';

  SharedPreferences? _preferences;

  /// 读取用户勾选「不再提示」时记下的公告编号；从未勾过返回 null。
  Future<String?> readDismissedId() async {
    try {
      return (await _instance).getString(_keyDismissedId);
    } catch (e) {
      debugPrint('[AnnouncementPreferences] 读取不再提示公告失败: $e');
      return null;
    }
  }

  Future<void> writeDismissedId(String id) async {
    if (id.isEmpty) return;
    try {
      await (await _instance).setString(_keyDismissedId, id);
    } catch (e) {
      debugPrint('[AnnouncementPreferences] 写入不再提示公告失败: $e');
    }
  }

  Future<void> clearDismissedId() async {
    try {
      await (await _instance).remove(_keyDismissedId);
    } catch (e) {
      debugPrint('[AnnouncementPreferences] 清除不再提示公告失败: $e');
    }
  }

  Future<SharedPreferences> get _instance async =>
      _preferences ??= await SharedPreferences.getInstance();
}
