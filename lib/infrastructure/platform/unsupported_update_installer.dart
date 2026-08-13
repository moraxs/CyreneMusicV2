import 'dart:io';

import '../../domain/updates/update_installer.dart';

/// 不支持应用内安装的平台（macOS / Linux / iOS）用的空实现。
///
/// [isSupported] 为 false 时 UI 会把「立即更新」换成「前往下载」跳浏览器，
/// 因此 [install] 正常情况下不会被调用。
class UnsupportedUpdateInstaller implements UpdateInstaller {
  const UnsupportedUpdateInstaller();

  @override
  bool get isSupported => false;

  @override
  Future<void> install(File package) async =>
      throw const UpdateInstallFailure('当前平台暂不支持应用内更新');
}
