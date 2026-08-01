import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/app_update.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';

/// 应用更新服务（对应 Next.js demo/lib/services/updateService.ts）。
///
/// 单例。检查 GitHub Release 是否有新版本（通过后端代理端点
/// [UrlService.latestNextVersionUrl]），并按平台 / Android ABI 挑选下载链接。
///
/// **差异说明**：
/// - 原 Next.js 版本直接请求 GitHub API；Flutter 端按任务要求改走后端
///   `/version/next/latest`（[UrlService.instance.latestNextVersionUrl]）。
/// - 原 `process.env.NEXT_PUBLIC_APP_VERSION` 在 Flutter 端无对应物，[currentVersion]
///   默认 `0.0.0`，由外部启动时通过 [setCurrentVersion] 注入。
/// - 原 `window.__TAURI_INTERNALS__` / `invoke('get_app_target_abi')` 在 Flutter
///   端无对应物，Tauri 分支被跳过；ABI 嗅探回退到 [Platform] 判断。
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  /// 当前应用版本（默认 `0.0.0`，由外部注入）。
  String _currentVersion = '0.0.0';
  String get currentVersion => _currentVersion;
  void setCurrentVersion(String version) => _currentVersion = version;

  /// 缓存的 Android 目标 ABI（与源码 cachedAbi 行为一致）。
  AndroidAbi? _cachedAbi;
  bool _abiResolved = false;

  /// ABI fallback 顺序（对应原 ABI_FALLBACK_ORDER）。
  static const Map<AndroidAbi, List<AndroidAbi>> _abiFallbackOrder = {
    AndroidAbi.arm64V8a: [
      AndroidAbi.arm64V8a,
      AndroidAbi.universal,
      AndroidAbi.armeabiV7a,
    ],
    AndroidAbi.armeabiV7a: [
      AndroidAbi.armeabiV7a,
      AndroidAbi.universal,
      AndroidAbi.arm64V8a,
    ],
    AndroidAbi.x86_64: [
      AndroidAbi.x86_64,
      AndroidAbi.universal,
      AndroidAbi.x86,
      AndroidAbi.arm64V8a,
      AndroidAbi.armeabiV7a,
    ],
    AndroidAbi.x86: [
      AndroidAbi.x86,
      AndroidAbi.universal,
      AndroidAbi.x86_64,
      AndroidAbi.armeabiV7a,
      AndroidAbi.arm64V8a,
    ],
    AndroidAbi.universal: [
      AndroidAbi.universal,
      AndroidAbi.arm64V8a,
      AndroidAbi.armeabiV7a,
      AndroidAbi.x86_64,
      AndroidAbi.x86,
    ],
  };

  /// ABI 文件名匹配模式（对应原 ABI_FILENAME_PATTERNS）。
  static final Map<AndroidAbi, RegExp> _abiFilenamePatterns = {
    AndroidAbi.arm64V8a: RegExp(r'arm64|aarch64', caseSensitive: false),
    AndroidAbi.armeabiV7a: RegExp(
      r'armeabi|armv7|([_-])arm(\.apk|[_-])',
      caseSensitive: false,
    ),
    AndroidAbi.x86_64: RegExp(r'x86[-_]?64', caseSensitive: false),
    AndroidAbi.x86: RegExp(
      r'([_-])(x86|i686)(\.apk|[_-])',
      caseSensitive: false,
    ),
    AndroidAbi.universal: RegExp(r'universal', caseSensitive: false),
  };

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

  /// 从 GitHub Releases 获取最新版本信息。
  ///
  /// @returns 如果有新版本则返回更新信息，否则返回 null
  Future<UpdateInfo?> checkUpdate() async {
    try {
      final response = await ApiClient.instance.apiFetch(
        UrlService.instance.latestNextVersionUrl,
      );
      if (!_ok(response)) return null;

      final release = _decode(response);
      final latestVersion = (release['tag_name']?.toString() ?? '').replaceAll(
        RegExp(r'^v', caseSensitive: false),
        '',
      );

      if (latestVersion.isEmpty ||
          compareVersions(latestVersion, _currentVersion) <= 0) {
        return null;
      }

      final assetsRaw = release['assets'];
      final assets = assetsRaw is List
          ? assetsRaw
                .whereType<Map>()
                .map((e) => GitHubAsset.fromJson(Map<String, Object?>.from(e)))
                .toList()
          : const <GitHubAsset>[];

      final androidAbiDownloads = _collectAndroidAbiDownloads(assets);
      final targetAbi = await _resolveAndroidTargetAbi();
      final downloads = _resolvePlatformDownloads(
        assets,
        androidAbiDownloads,
        targetAbi,
      );

      return UpdateInfo(
        version: latestVersion,
        changelog: release['body']?.toString() ?? '暂无更新说明',
        forceUpdate: false,
        downloadUrl: release['html_url']?.toString(),
        platformDownloads: downloads,
        androidAbiDownloads: androidAbiDownloads,
        androidTargetAbi: targetAbi,
      );
    } catch (e) {
      debugPrint('[UpdateService] checkUpdate failed: $e');
    }
    return null;
  }

  /// 探测当前 Android 运行环境的 ABI。桌面端直接返回 null。
  Future<AndroidAbi?> _resolveAndroidTargetAbi() async {
    if (_abiResolved) return _cachedAbi;

    // 原 Tauri 路径调用 invoke('get_app_target_abi')；Flutter 端无对应物，跳过。
    AndroidAbi? abi = _detectAbiFromPlatform();

    _cachedAbi = abi;
    _abiResolved = true;
    return abi;
  }

  /// Flutter 端无 navigator.userAgent，用 [Platform] 做平台判断。
  /// Android 设备无 ABI 信息时，与源码一致兜底为 arm64-v8a。
  AndroidAbi? _detectAbiFromPlatform() {
    if (!Platform.isAndroid) return null;
    return AndroidAbi.arm64V8a;
  }

  /// 从 release assets 中按 ABI 收集所有 Android APK 链接。
  Map<String, String> _collectAndroidAbiDownloads(List<GitHubAsset> assets) {
    final map = <String, String>{};
    for (final asset in assets) {
      final name = asset.name;
      if (!name.toLowerCase().endsWith('.apk')) continue;

      for (final entry in _abiFilenamePatterns.entries) {
        if (entry.value.hasMatch(name)) {
          map[entry.key.wireName] = asset.browserDownloadUrl;
          break;
        }
      }
    }
    return map;
  }

  /// 按设备 ABI 在 fallback 顺序中挑出最合适的 APK。
  String? _pickAndroidApkByAbi(
    Map<String, String> abiDownloads,
    AndroidAbi? targetAbi,
  ) {
    if (abiDownloads.isEmpty) return null;

    final order = targetAbi != null
        ? _abiFallbackOrder[targetAbi]!
        : const [
            AndroidAbi.arm64V8a,
            AndroidAbi.armeabiV7a,
            AndroidAbi.x86_64,
            AndroidAbi.x86,
          ];

    for (final abi in order) {
      final url = abiDownloads[abi.wireName];
      if (url != null && url.isNotEmpty) return url;
    }
    // 万一命名不在 ABI 表里，给一个最终兜底。
    return abiDownloads.values.firstOrNull;
  }

  /// 根据 release assets 生成各平台下载链接。
  Map<String, String> _resolvePlatformDownloads(
    List<GitHubAsset> assets,
    Map<String, String> androidAbiDownloads,
    AndroidAbi? targetAbi,
  ) {
    final map = <String, String>{};

    for (final asset in assets) {
      final name = asset.name.toLowerCase();
      if (name.endsWith('.exe') || name.endsWith('.msi')) {
        map['windows'] = asset.browserDownloadUrl;
      } else if (name.endsWith('.dmg') || name.endsWith('.app.tar.gz')) {
        map['macos'] = asset.browserDownloadUrl;
      } else if (name.endsWith('.deb') ||
          name.endsWith('.appimage') ||
          name.endsWith('.rpm')) {
        map['linux'] = asset.browserDownloadUrl;
      } else if (name.endsWith('.ipa')) {
        map['ios'] = asset.browserDownloadUrl;
      }
    }

    final apk = _pickAndroidApkByAbi(androidAbiDownloads, targetAbi);
    if (apk != null) map['android'] = apk;

    return map;
  }

  /// 版本对比算法。
  ///
  /// @returns 1: v1 > v2, -1: v1 < v2, 0: v1 == v2
  int compareVersions(String v1, String v2) {
    final n1 = v1
        .replaceAll(RegExp(r'^v', caseSensitive: false), '')
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    final n2 = v2
        .replaceAll(RegExp(r'^v', caseSensitive: false), '')
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    final len = n1.length > n2.length ? n1.length : n2.length;

    for (var i = 0; i < len; i++) {
      final a = i < n1.length ? n1[i] : 0;
      final b = i < n2.length ? n2[i] : 0;
      if (a > b) return 1;
      if (a < b) return -1;
    }
    return 0;
  }
}
