import '../../domain/models/announcement.dart';
import 'public_config_service.dart';

/// 公告服务（对应 Next.js demo/lib/services/announcementService.ts）。
///
/// 单例，只负责把公告取回来。取数与解码都在 [PublicConfigService]——公告和
/// QQ 群同属 `/config/public` 的响应，两边各写一份 fetch 只会分叉。
///
/// **职责边界**：原 Next.js 版本用 `localStorage` 持久化已关闭公告 ID；Flutter 端
/// 的「不再提示」由 [AnnouncementPreferences] 落 SharedPreferences，弹不弹由
/// [AnnouncementController] 判定，service 层不掺和。
class AnnouncementService {
  AnnouncementService._();
  static final AnnouncementService instance = AnnouncementService._();

  /// 从后端获取公告。后端关掉公告（`enabled: false`）时返回 null，
  /// 让调用方与「压根没配公告」走同一条降级路径。
  Future<Announcement?> fetchAnnouncement() async {
    final announcement =
        (await PublicConfigService.instance.fetch())?.announcement;
    if (announcement == null || !announcement.enabled) return null;
    return announcement;
  }
}
