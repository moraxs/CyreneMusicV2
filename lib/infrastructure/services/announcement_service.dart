import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/announcement.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';

/// 公告服务（对应 Next.js demo/lib/services/announcementService.ts）。
///
/// 单例。从后端拉取公告，并维护「已关闭」标记。
///
/// **职责边界**：原 Next.js 版本用 `localStorage` 持久化已关闭公告 ID；Flutter 端
/// service 层不直接写持久化，改为内存 [Set] 缓存，**持久化交给 store 层**（如
/// SharedPreferences）。
class AnnouncementService {
  AnnouncementService._();
  static final AnnouncementService instance = AnnouncementService._();

  /// 内存缓存：已被用户关闭的公告 ID。
  final Set<String> _dismissedIds = {};

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

  /// 从后端获取公告。
  Future<Announcement?> fetchAnnouncement() async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/config/public',
      );
      if (!_ok(response)) return null;

      final json = _decode(response);
      final data = json['data'];
      if (data is! Map) return null;
      final announcementRaw = data['announcement'];
      if (announcementRaw is! Map) return null;
      final announcement = Announcement.fromJson(
        Map<String, Object?>.from(announcementRaw),
      );
      if (!announcement.enabled) return null;
      return announcement;
    } catch (e) {
      debugPrint('[AnnouncementService] fetchAnnouncement failed: $e');
      return null;
    }
  }

  /// 检查公告是否已被用户关闭（基于 id）。
  ///
  /// 注：仅查内存缓存；进程重启后状态丢失。需跨重启保留请由 store 层持久化。
  bool isDismissed(String id) {
    return _dismissedIds.contains(id);
  }

  /// 标记公告为已关闭。
  ///
  /// 注：仅写内存缓存；进程重启后状态丢失。需跨重启保留请由 store 层持久化。
  void dismiss(String id) {
    _dismissedIds.add(id);
  }
}
