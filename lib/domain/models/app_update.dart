/// Android ABI 类型（对应 Next.js updateService.ts 的 AndroidAbi）。
enum AndroidAbi {
  arm64V8a('arm64-v8a'),
  armeabiV7a('armeabi-v7a'),
  x86_64('x86_64'),
  x86('x86'),
  universal('universal');

  const AndroidAbi(this.wireName);

  final String wireName;

  static AndroidAbi? fromWireName(String? value) {
    if (value == null) return null;
    final lower = value.toLowerCase();
    if (lower.contains('arm64') || lower == 'aarch64') {
      return AndroidAbi.arm64V8a;
    }
    if (lower.contains('armeabi') ||
        lower.startsWith('armv7') ||
        lower == 'arm') {
      return AndroidAbi.armeabiV7a;
    }
    if (lower == 'x86_64' || lower == 'x64') return AndroidAbi.x86_64;
    if (lower == 'x86' || lower == 'i686') return AndroidAbi.x86;
    if (lower == 'universal') return AndroidAbi.universal;
    return null;
  }
}

/// GitHub Release Asset（对应 Next.js GitHubAsset）。
class GitHubAsset {
  const GitHubAsset({required this.name, required this.browserDownloadUrl});

  final String name;
  final String browserDownloadUrl;

  factory GitHubAsset.fromJson(Map<String, Object?> json) => GitHubAsset(
    name: json['name']?.toString() ?? '',
    browserDownloadUrl: json['browser_download_url']?.toString() ?? '',
  );
}

/// 更新信息（对应 Next.js updateService.ts 的 UpdateInfo）。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.changelog,
    required this.forceUpdate,
    this.downloadUrl,
    this.platformDownloads,
    this.androidAbiDownloads,
    this.androidTargetAbi,
  });

  final String version;
  final String changelog;
  final bool forceUpdate;

  /// 主下载链接（exe）。
  final String? downloadUrl;

  /// 各平台下载链接。
  final Map<String, String>? platformDownloads;

  /// 全部 Android ABI 安装包，用于按设备架构挑选。
  final Map<String, String>? androidAbiDownloads;

  /// 当前运行环境识别出的 Android ABI（仅在移动端有效）。
  final AndroidAbi? androidTargetAbi;

  factory UpdateInfo.fromJson(Map<String, Object?> json) => UpdateInfo(
    version: json['version']?.toString() ?? '',
    changelog: json['changelog']?.toString() ?? '暂无更新说明',
    forceUpdate: json['force_update'] == true,
    downloadUrl: json['download_url']?.toString(),
    platformDownloads: _parseStringMap(json['platform_downloads']),
    androidAbiDownloads: _parseStringMap(json['android_abi_downloads']),
    androidTargetAbi: AndroidAbi.fromWireName(
      json['android_target_abi']?.toString(),
    ),
  );

  Map<String, Object?> toJson() => {
    'version': version,
    'changelog': changelog,
    'force_update': forceUpdate,
    'download_url': downloadUrl,
    'platform_downloads': platformDownloads,
    'android_abi_downloads': androidAbiDownloads,
    'android_target_abi': androidTargetAbi?.wireName,
  };

  static Map<String, String>? _parseStringMap(Object? value) {
    if (value is! Map) return null;
    return Map<String, String>.fromEntries(
      value.entries.whereType<MapEntry>().map(
        (e) => MapEntry(e.key.toString(), e.value.toString()),
      ),
    );
  }
}
