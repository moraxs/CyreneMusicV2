import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../app/app_version.dart';
import '../../domain/models/app_update.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';

/// 应用更新检查。
///
/// 打后端 `GET /version/latest`（见 [UrlService.latestVersionUrl]）。后端**不做
/// 版本比较**，无条件返回最新版信息，是否算「有更新」由 [hasUpdate] 在客户端判定。
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  /// 当前应用版本。默认取编译期常量 [appVersion]，测试可经 [setCurrentVersion] 覆盖。
  String _currentVersion = appVersion;
  String get currentVersion => _currentVersion;
  void setCurrentVersion(String version) => _currentVersion = version;

  /// 请求超时。启动时的静默检查不该把首屏拖在网络上。
  static const Duration _timeout = Duration(seconds: 10);

  /// 拉取最新版本信息。
  ///
  /// 网络失败 / 响应异常一律返回 null 并只记日志——检查更新是锦上添花，
  /// 不该因为后端抽风而弹错误给用户。注意返回非 null 不代表有新版本，
  /// 调用方需再过一道 [hasUpdate]（维护公告 `fixing` 也走这个通道下发）。
  Future<UpdateInfo?> checkUpdate() async {
    try {
      final response = await ApiClient.instance
          .apiFetch(UrlService.instance.latestVersionUrl)
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[UpdateService] 检查更新失败: HTTP ${response.statusCode}');
        return null;
      }

      final payload = jsonDecode(response.body);
      if (payload is! Map) return null;
      // HTTP 恒 200，业务码在 body.status。
      if (payload['status'] != 200) {
        debugPrint('[UpdateService] 检查更新失败: status=${payload['status']}');
        return null;
      }

      final data = payload['data'];
      if (data is! Map) return null;
      final info = UpdateInfo.fromJson(Map<String, Object?>.from(data));
      return info.version.isEmpty ? null : info;
    } on TimeoutException {
      debugPrint('[UpdateService] 检查更新超时');
    } catch (e) {
      debugPrint('[UpdateService] 检查更新异常: $e');
    }
    return null;
  }

  /// [info] 是否比当前版本新。
  bool hasUpdate(UpdateInfo info) =>
      compareVersions(info.version, _currentVersion) > 0;

  /// 版本对比：1 表示 v1 > v2，-1 表示 v1 < v2，0 表示相等。
  ///
  /// 按点分整数逐段比较，短的一侧补 0（`2.0` 等价于 `2.0.0`）。**不支持**语义化
  /// 版本的预发布标签：`2.0.0-beta.1` 会被切成 `['2','0','0-beta','1']`，
  /// `0-beta` 解析失败记 0，而多出的第四段反而让它"大于" `2.0.0` —— 预发布版
  /// 会被当成升级推给用户。发版请使用纯数字版本号（见 [appVersion] 的说明）。
  int compareVersions(String v1, String v2) {
    final n1 = _segments(v1);
    final n2 = _segments(v2);
    final len = n1.length > n2.length ? n1.length : n2.length;

    for (var i = 0; i < len; i++) {
      final a = i < n1.length ? n1[i] : 0;
      final b = i < n2.length ? n2[i] : 0;
      if (a > b) return 1;
      if (a < b) return -1;
    }
    return 0;
  }

  /// 只剥开头的 `v` 前缀——用 replaceAll 会把版本串里任意位置的 v 都删掉。
  static List<int> _segments(String version) => version
      .replaceFirst(RegExp(r'^v', caseSensitive: false), '')
      .split('.')
      .map((segment) => int.tryParse(segment) ?? 0)
      .toList(growable: false);

  /// 注入自定义 [http.Client]（测试用），转交给 [ApiClient]。
  @visibleForTesting
  void useClient(http.Client client) => ApiClient.instance.useClient(client);
}
