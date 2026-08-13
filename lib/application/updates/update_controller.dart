import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../../domain/models/app_update.dart';
import '../../domain/updates/update_installer.dart';
import '../../infrastructure/platform/android_update_installer.dart';
import '../../infrastructure/platform/unsupported_update_installer.dart';
import '../../infrastructure/platform/windows_update_installer.dart';
import '../../infrastructure/services/update_downloader.dart';
import '../../infrastructure/services/update_service.dart';
import '../../infrastructure/storage/update_preferences.dart';

/// 应用更新的状态与流程编排：检查 → 提示决策 → 下载 → 安装。
///
/// 单例（与 UrlService / DeveloperModeService 一致）：它没有跨 controller
/// 依赖，没必要进 AppDependencies 再层层透传到设置页。
class UpdateController extends ChangeNotifier {
  UpdateController({
    UpdateService? service,
    UpdateDownloader? downloader,
    UpdatePreferences? preferences,
    UpdateInstaller? installer,
  }) : _service = service ?? UpdateService.instance,
       _downloader = downloader ?? UpdateDownloader(),
       _preferences = preferences ?? UpdatePreferences(),
       _installer = installer ?? _defaultInstaller();

  static final UpdateController instance = UpdateController();

  final UpdateService _service;
  final UpdateDownloader _downloader;
  final UpdatePreferences _preferences;
  final UpdateInstaller _installer;

  static UpdateInstaller _defaultInstaller() {
    if (Platform.isAndroid) return const AndroidUpdateInstaller();
    if (Platform.isWindows) return const WindowsUpdateInstaller();
    return const UnsupportedUpdateInstaller();
  }

  /// 已检出的新版本；无更新或尚未检查时为 null。
  UpdateInfo? _available;
  UpdateInfo? get available => _available;

  bool _isChecking = false;
  bool get isChecking => _isChecking;

  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool get isPlatformSupported => _installer.isSupported;

  /// 下载进度（0.0~1.0）走独立通知，不进主通知。
  ///
  /// 与 PlaybackController 的 positionListenable 同一个理由：进度是高频量，
  /// 若走 notifyListeners，整棵监听 controller 的树会跟着每次回调重建。
  /// 下载器侧已按 1% / 200ms 节流，这里只负责广播。
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  ValueListenable<double> get progressListenable => _progress;

  /// 本次启动内已「稍后提醒」过的版本。刻意不持久化——文案承诺的就是
  /// 「下次启动会再提示」。
  final Set<String> _remindedVersions = <String>{};

  /// 检查更新。返回值非 null 仅表示后端给出了信息，是否该弹窗见 [shouldPrompt]。
  ///
  /// [silent] 为 true（启动时的自动检查）时不设置 [errorMessage]，避免因一次
  /// 网络抖动就在首屏挂个错误。
  Future<UpdateInfo?> check({bool silent = true}) async {
    // 重入保护：手动检查与启动检查可能撞在一起。
    if (_isChecking) return _available;

    _isChecking = true;
    if (!silent) _errorMessage = null;
    notifyListeners();

    try {
      final info = await _service.checkUpdate();
      // 维护公告（fixing）没有版本语义，不参与版本比较，直接透传给 UI。
      _available = info != null && (info.fixing || _service.hasUpdate(info))
          ? info
          : null;
      if (!silent && _available == null && info == null) {
        _errorMessage = '检查更新失败，请稍后重试';
      }
      return _available;
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  /// 是否应当就 [info] 弹窗提示。
  ///
  /// 强制更新与维护公告无条件提示；否则跳过用户已忽略的版本（及更低）与本次
  /// 启动已「稍后提醒」过的版本。
  Future<bool> shouldPrompt(UpdateInfo info) async {
    if (info.forceUpdate || info.fixing) return true;
    if (_remindedVersions.contains(info.version)) return false;

    final ignored = await _preferences.readIgnoredVersion();
    if (ignored == null || ignored.isEmpty) return true;
    return _service.compareVersions(info.version, ignored) > 0;
  }

  /// 下载并安装 [info] 对应的更新包。
  ///
  /// 安装成功不会正常返回——Windows 实现会主动退出进程，安卓会切到系统安装器。
  /// 失败时把原因写进 [errorMessage] 并复位下载态。
  Future<void> startUpdate(UpdateInfo info) async {
    if (_isDownloading) return;

    final url = info.resolveDownloadUrl();
    if (url == null || url.isEmpty) {
      _errorMessage = '该版本没有提供当前平台的下载地址';
      notifyListeners();
      return;
    }
    if (!_installer.isSupported) {
      _errorMessage = '当前平台暂不支持应用内更新';
      notifyListeners();
      return;
    }

    _isDownloading = true;
    _errorMessage = null;
    _progress.value = 0;
    notifyListeners();

    try {
      final package = await _downloader.download(
        url,
        onProgress: (value) => _progress.value = value,
      );
      _progress.value = 1;
      await _installer.install(package);
    } catch (e) {
      _errorMessage = switch (e) {
        UpdateDownloadFailure(:final message) => message,
        UpdateInstallFailure(:final message) => message,
        _ => '更新失败：$e',
      };
      debugPrint('[UpdateController] 更新失败: $e');
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  /// 忽略 [version] 及更低版本，持久化。
  Future<void> ignoreVersion(String version) async {
    await _preferences.writeIgnoredVersion(version);
    _remindedVersions.add(version);
  }

  /// 本次启动内不再提示 [version]。
  void remindLater(String version) => _remindedVersions.add(version);

  /// 清除错误态，便于 UI 重试。
  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }
}
