import 'package:flutter/foundation.dart';

import '../../domain/models/announcement.dart';
import '../../infrastructure/services/announcement_service.dart';
import '../../infrastructure/storage/announcement_preferences.dart';

/// 公告的拉取与「是否该弹」判定。
///
/// 单例，理由同 [UpdateController]：没有跨 controller 依赖，不值得进
/// AppDependencies 再层层透传到设置页。
///
/// 节流规则只有一条：**公告编号大于用户上次勾选「不再提示」时记下的编号才弹**。
/// 用户关掉弹窗但没勾选，什么都不记，下次启动照常再弹。
class AnnouncementController extends ChangeNotifier {
  AnnouncementController({
    AnnouncementService? service,
    AnnouncementPreferences? preferences,
  }) : _service = service ?? AnnouncementService.instance,
       _preferences = preferences ?? AnnouncementPreferences();

  static final AnnouncementController instance = AnnouncementController();

  final AnnouncementService _service;
  final AnnouncementPreferences _preferences;

  /// 最近一次拉到的公告；未拉取或后端关闭公告时为 null。
  Announcement? _current;
  Announcement? get current => _current;

  bool _isFetching = false;
  bool get isFetching => _isFetching;

  /// 拉取公告。失败一律返回 null——公告不是关键路径，不该因为后端抽风打断启动。
  Future<Announcement?> fetch() async {
    // 重入保护：启动自动弹窗与用户手点设置页可能撞在一起。
    if (_isFetching) return _current;

    _isFetching = true;
    notifyListeners();
    try {
      _current = await _service.fetchAnnouncement();
      return _current;
    } finally {
      _isFetching = false;
      notifyListeners();
    }
  }

  /// 启动时是否该就 [announcement] 自动弹窗。
  ///
  /// 设置页的手动入口不走这里——用户主动点的，压过也得给他看。
  Future<bool> shouldPrompt(Announcement announcement) async {
    if (!announcement.canPopup) return false;
    final dismissed = await _preferences.readDismissedId();
    if (dismissed == null || dismissed.isEmpty) return true;
    return compareAnnouncementIds(announcement.id, dismissed) > 0;
  }

  /// 记下「不再提示」：压住 [id] 及更早编号的公告，直到后端把编号调大。
  Future<void> dismissUntilNewer(String id) =>
      _preferences.writeDismissedId(id);

  /// 清除「不再提示」标记，让当前公告重新参与弹窗。
  Future<void> resetDismissed() => _preferences.clearDismissedId();
}
