import 'dart:io' show Platform;

/// 更新信息（对应后端 `GET /version/latest` 响应中的 `data`）。
///
/// 后端不做版本比较，无条件返回最新版信息，比较责任全在客户端
/// （见 `UpdateService.hasUpdate`）。也**不下发 sha256 / 文件大小**，
/// 因此下载完只能靠 Content-Length 判断是否完整。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.changelog,
    required this.forceUpdate,
    this.fixing = false,
    this.downloadUrl,
    this.platformDownloads = const {},
  });

  final String version;
  final String changelog;

  /// 强制更新：弹窗不可关闭，且不提供「稍后提醒 / 忽略此版本」。
  final bool forceUpdate;

  /// 服务器维护中。此时 [changelog] 是维护公告而非更新说明，不该走下载流程。
  final bool fixing;

  /// 主下载链接。仅在 [platformDownloads] 没有对应平台时兜底。
  final String? downloadUrl;

  /// 各平台下载链接。后端只会给出 `windows`（-full.zip）、`android`
  /// 与 `mobile`（同一个 -full.apk 的两个键），不区分 CPU 架构。
  final Map<String, String> platformDownloads;

  factory UpdateInfo.fromJson(Map<String, Object?> json) => UpdateInfo(
    version: json['version']?.toString() ?? '',
    changelog: json['changelog']?.toString() ?? '暂无更新说明',
    forceUpdate: _parseBool(json['force_update']),
    fixing: _parseBool(json['fixing']),
    downloadUrl: switch (json['download_url']) {
      final String value when value.isNotEmpty => value,
      _ => null,
    },
    platformDownloads: _parseStringMap(json['platform_downloads']),
  );

  Map<String, Object?> toJson() => {
    'version': version,
    'changelog': changelog,
    'force_update': forceUpdate,
    'fixing': fixing,
    'download_url': downloadUrl,
    'platform_downloads': platformDownloads,
  };

  /// 按当前平台挑选下载地址。
  ///
  /// 安卓上 `android` 与 `mobile` 指向同一个 APK，后端两个键都会给，但历史
  /// 版本的 manifest 可能只写了其中一个，因此依次回退。
  String? resolveDownloadUrl() {
    final keys = switch (Platform.operatingSystem) {
      'android' => const ['android', 'mobile'],
      'ios' => const ['ios', 'mobile'],
      'windows' => const ['windows'],
      'macos' => const ['macos'],
      'linux' => const ['linux'],
      _ => const <String>[],
    };
    for (final key in keys) {
      final url = platformDownloads[key];
      if (url != null && url.isNotEmpty) return url;
    }
    return downloadUrl;
  }

  /// 后端 manifest 的布尔字段可能是 bool，也可能是字符串 `"true"`
  /// （`health.ts` 的解析处就两种都兼容），这里跟随同样的宽容度。
  static bool _parseBool(Object? value) {
    if (value is bool) return value;
    return value?.toString().toLowerCase() == 'true';
  }

  static Map<String, String> _parseStringMap(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        entry.key.toString(): entry.value.toString(),
    };
  }
}
