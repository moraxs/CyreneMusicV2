import 'dart:io' show File;

/// 更新包的安装动作。
///
/// 各平台差异极大——安卓是拉起系统安装器，Windows 是解压后由提权脚本覆盖
/// 安装目录并重启——抽成接口后，[UpdateController] 不必感知平台，测试也能
/// 塞进假实现而不真的装东西。
abstract interface class UpdateInstaller {
  /// 当前平台是否支持应用内安装。为 false 时 UI 退化为「前往下载」跳浏览器。
  bool get isSupported;

  /// 安装 [package]。
  ///
  /// Windows 实现会在启动更新器后主动结束进程，因此该 Future 可能永远不会
  /// 正常返回——调用方不应在其后安排必须执行的收尾逻辑。
  Future<void> install(File package);
}

/// 安装失败。[message] 面向用户，可直接展示。
class UpdateInstallFailure implements Exception {
  const UpdateInstallFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
