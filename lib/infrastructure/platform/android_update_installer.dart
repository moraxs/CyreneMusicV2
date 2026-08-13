import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';

import '../../domain/updates/update_installer.dart';

/// 安卓端安装器：把下载好的 APK 交给系统安装器。
///
/// 走 `open_filex` 而不是自己写 platform channel：它内置的 FileProvider 会随
/// manifest 合并进来，省掉一套 `<provider>` + file_paths.xml 配置。
class AndroidUpdateInstaller implements UpdateInstaller {
  const AndroidUpdateInstaller();

  @override
  bool get isSupported => true;

  @override
  Future<void> install(File package) async {
    debugPrint('[AndroidUpdateInstaller] 拉起安装器: ${package.path}');
    final result = await OpenFilex.open(
      package.path,
      type: 'application/vnd.android.package-archive',
      uti: 'com.android.package-archive',
    );

    switch (result.type) {
      case ResultType.done:
        return;
      case ResultType.permissionDenied:
        // Android 8.0+ 的「安装未知应用」是按应用授权的，系统会引导用户去开，
        // 用户拒绝后就落到这里。
        throw const UpdateInstallFailure('需要授予「安装未知应用」权限才能更新');
      case ResultType.noAppToOpen:
        throw const UpdateInstallFailure('未找到可用的安装程序');
      case ResultType.fileNotFound:
        throw const UpdateInstallFailure('更新包已丢失，请重新下载');
      case ResultType.error:
        throw UpdateInstallFailure('安装失败：${result.message}');
    }
  }
}
