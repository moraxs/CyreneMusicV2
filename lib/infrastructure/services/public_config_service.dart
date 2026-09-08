import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../domain/models/announcement.dart';
import '../../domain/models/qq_group.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';

/// `GET /config/public` 的响应体。
///
/// 后端只在这个端点下发「允许公开的配置项」（见 backend/src/routes/health.ts），
/// 目前是公告与 QQ 群两块。任一块解析失败/缺失时该字段为 null，其余照常可用。
class PublicConfig {
  const PublicConfig({this.announcement, this.qqGroup});

  final Announcement? announcement;
  final QqGroup? qqGroup;
}

/// 公共配置服务：`/config/public` 的唯一客户端。
///
/// 公告和 QQ 群来自同一个响应，所以取回与解码只写一份——两边各自 fetch 一次
/// 只会让「加了字段但另一边忘了同步解析」这类问题重演。
///
/// **刻意不缓存**：这个端点就是给运营改配置用的（关掉公告、关掉 QQ 群入口），
/// 缓存会让改动迟迟不生效。响应只有几百字节，调用点也都是低频的（启动一次、
/// 打开帮助页一次、下拉刷新一次）。
class PublicConfigService {
  PublicConfigService._();
  static final PublicConfigService instance = PublicConfigService._();

  /// 请求超时。与 UpdateService 一致：配置是锦上添花，不该把首屏或页面拖在网络上。
  static const Duration _timeout = Duration(seconds: 10);

  /// 拉取公共配置。
  ///
  /// 网络失败 / 响应异常一律返回 null 并只记日志——调用方据此走各自的降级
  /// （公告不弹、QQ 群入口不渲染），不该弹错误给用户。
  Future<PublicConfig?> fetch() async {
    try {
      final response = await ApiClient.instance
          .apiFetch('${UrlService.instance.baseUrl}/config/public')
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[PublicConfigService] 拉取失败: HTTP ${response.statusCode}');
        return null;
      }

      final payload = jsonDecode(response.body);
      if (payload is! Map) return null;
      final data = payload['data'];
      if (data is! Map) return null;

      final announcementRaw = data['announcement'];
      final qqGroupRaw = data['qq_group'];
      return PublicConfig(
        announcement: announcementRaw is Map
            ? Announcement.fromJson(Map<String, Object?>.from(announcementRaw))
            : null,
        qqGroup: qqGroupRaw is Map
            ? QqGroup.fromJson(Map<String, Object?>.from(qqGroupRaw))
            : null,
      );
    } on TimeoutException {
      debugPrint('[PublicConfigService] 拉取超时');
    } catch (e) {
      debugPrint('[PublicConfigService] 拉取异常: $e');
    }
    return null;
  }

  /// 仅取 QQ 群配置。取不到（网络失败 / 后端没配）返回 null。
  Future<QqGroup?> fetchQqGroup() async => (await fetch())?.qqGroup;
}
