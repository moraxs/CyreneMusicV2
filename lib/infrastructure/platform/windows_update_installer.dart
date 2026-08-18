import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../../domain/updates/update_installer.dart';
import '../services/update_downloader.dart';

/// Windows 端安装器：解压更新包，交由提权的 PowerShell 脚本覆盖安装目录。
///
/// 应用不能覆盖正在运行的自己，所以流程必须外包给一个独立进程：
/// 解压到 `<安装目录>/updates/temp_<ts>/` → 释放 updater.ps1 与启动用的 bat →
/// 启动 bat（必要时 UAC 自举提权）→ 本进程 `exit(0)` → 脚本等主进程退出后
/// 逐文件覆盖，最后重新拉起 exe。
class WindowsUpdateInstaller implements UpdateInstaller {
  const WindowsUpdateInstaller();

  /// 更新器脚本在 assets 中的路径，与 pubspec.yaml 的声明一致。
  static const String _updaterAsset = 'windows/runner/updater.ps1';

  /// 留给脚本等待主进程退出的秒数，同时也是本进程退出前的宽限。
  static const int _waitSeconds = 3;

  @override
  bool get isSupported => true;

  @override
  Future<void> install(File package) async {
    if (!package.path.toLowerCase().endsWith('.zip')) {
      throw const UpdateInstallFailure('更新包格式不受支持（应为 .zip）');
    }

    final installDir = Directory(UpdateDownloader.resolveInstallDirectory());
    // 解压、写更新器脚本/启动 bat 等前置写操作放在**用户可写**的 AppData 目录，
    // 而不是安装目录：安装在 Program Files 时，非管理员运行的应用没有写入权限，
    // 提前写进去会直接失败（旧实现因此必须"以管理员运行主程序"才能更新）。
    // 只有覆盖安装目录的最终一步交给提权脚本（见 updater.ps1）。
    final staging = await UpdateDownloader().resolveDownloadDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final tempDir = Directory(p.join(staging.path, 'temp_$stamp'));
    tempDir.createSync(recursive: true);

    try {
      await _extract(package, tempDir);
    } catch (e) {
      throw UpdateInstallFailure('更新包解压失败：$e');
    }
    // 解压成功后压缩包就没用了，且它有几十 MB。
    package.delete().ignore();

    final scriptFile = File(p.join(staging.path, 'updater_$stamp.ps1'));
    await scriptFile.writeAsString(await _loadUpdaterScript(tempDir));
    if (!scriptFile.existsSync()) {
      throw const UpdateInstallFailure('更新器脚本写入失败');
    }

    final batchFile = File(p.join(staging.path, 'start_updater_$stamp.bat'));
    await batchFile.writeAsString(
      _buildBatchScript(
        scriptPath: _windowsPath(scriptFile.path),
        installDir: _windowsPath(installDir.path),
        updateDir: _windowsPath(tempDir.path),
        exePath: _windowsPath(Platform.resolvedExecutable),
      ),
      // bat 必须是单字节编码：cmd 按当前代码页解析，UTF-8 的中文会变乱码并
      // 让整个脚本失效。因此内容也全用英文。
      encoding: latin1,
    );

    await _startUpdater(batchFile);

    // 给更新器一点时间起来，然后主动退出——脚本正等着主进程消失才好覆盖文件。
    await Future<void>.delayed(const Duration(seconds: 2));
    debugPrint('[WindowsUpdateInstaller] 退出应用，交由更新器接管');
    exit(0);
  }

  /// 解压到 [target]，剥掉压缩包可能存在的单一顶层目录。
  ///
  /// 打包方式不同，zip 里可能是 `Cyrene/xxx.exe` 也可能直接是 `xxx.exe`。
  /// 不剥的话文件会被覆盖到 `<安装目录>/Cyrene/` 而非安装目录本身。
  ///
  /// 读盘 + CRC 校验 + 逐文件落盘对 ~70MB 的包是重活，放在独立 isolate 里跑，
  /// 否则会阻塞主 isolate，窗口表现为无响应（点击弹「窗口被占用」的提示音）。
  Future<void> _extract(File package, Directory target) async {
    final count = await Isolate.run(
      () => _extractSync(package.path, target.path),
    );
    debugPrint('[WindowsUpdateInstaller] 解压完成，共 $count 个文件');
  }

  /// [_extract] 的同步实现，只在后台 isolate 中执行。
  static int _extractSync(String packagePath, String targetPath) {
    final archive = ZipDecoder().decodeBytes(
      File(packagePath).readAsBytesSync(),
      verify: true,
    );

    final roots = <String>{};
    for (final entry in archive) {
      final name = _sanitizeEntryName(entry.name);
      if (name.isEmpty) continue;
      roots.add(name.split('/').first);
    }
    final stripPrefix = roots.length == 1 && roots.first.isNotEmpty
        ? '${roots.first}/'
        : null;

    var count = 0;
    for (final entry in archive) {
      var name = _sanitizeEntryName(entry.name);
      if (name.isEmpty) continue;
      if (stripPrefix != null && name.startsWith(stripPrefix)) {
        name = name.substring(stripPrefix.length);
      }
      if (name.isEmpty) continue;

      final outputPath = p.join(targetPath, name);
      if (entry.isDirectory) {
        Directory(outputPath).createSync(recursive: true);
        continue;
      }
      final file = File(outputPath);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(entry.readBytes() ?? const <int>[], flush: true);
      count++;
    }
    return count;
  }

  /// 压缩包条目名的防穿越处理：带 `..` 的一律丢弃，避免写到安装目录之外。
  @visibleForTesting
  static String sanitizeEntryName(String name) => _sanitizeEntryName(name);

  static String _sanitizeEntryName(String originalName) {
    var name = originalName.replaceAll('\\', '/');
    name = p.posix.normalize(name);

    while (name.startsWith('../')) {
      name = name.substring(3);
    }
    while (name.startsWith('./')) {
      name = name.substring(2);
    }
    if (name.startsWith('/')) name = name.substring(1);

    // normalize 之后仍含 `..`，说明它跳出了根，直接丢弃而不是试图修复。
    if (name == '..' || name.contains('../') || name.endsWith('/..')) {
      return '';
    }
    return name;
  }

  /// 取更新器脚本内容。
  ///
  /// 优先用**新包里**那份：更新逻辑本身若有修复，应当由新版本自己带来，而不是
  /// 被旧版本的脚本执行。新包没有才回退到当前 assets。
  Future<String> _loadUpdaterScript(Directory extracted) async {
    final bundled = File(
      p.join(extracted.path, 'data', 'flutter_assets', _updaterAsset),
    );
    if (bundled.existsSync()) {
      debugPrint('[WindowsUpdateInstaller] 使用新版本自带的更新器脚本');
      return bundled.readAsString();
    }
    try {
      return await rootBundle.loadString(_updaterAsset);
    } catch (e) {
      throw UpdateInstallFailure('无法加载更新器脚本：$e');
    }
  }

  /// 生成启动更新器的批处理。
  ///
  /// 覆盖 Program Files 之类的位置需要管理员权限，因此先用 `net session` 探测，
  /// 没有就用 `-Verb RunAs` 把自己重新拉起一次（触发 UAC）。
  String _buildBatchScript({
    required String scriptPath,
    required String installDir,
    required String updateDir,
    required String exePath,
  }) => '''@echo off
:: Check for administrator privileges
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :RunUpdater
) else (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:RunUpdater
echo ========================================
echo Cyrene Music Updater
echo ========================================
echo.
echo Install: $installDir
echo Update:  $updateDir
echo.

powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File "$scriptPath" -InstallDir "$installDir" -UpdateDir "$updateDir" -ExePath "$exePath" -WaitSeconds $_waitSeconds

echo.
echo Update completed.
timeout /t 2 /nobreak >nul
:: 更新完成后再删掉自己（放在提权分支末尾，避免非提权实例先删导致提权实例失联）
del /f /q "%~f0"
exit
''';

  /// 启动更新器，三级降级。
  ///
  /// 直接跑 bat 在部分环境（组策略限制、关联被改）会失败，因此依次退到
  /// `cmd /c` 和直接调 PowerShell。必须是 detached：本进程马上就要退出了。
  Future<void> _startUpdater(File batchFile) async {
    final attempts = <Future<Process> Function()>[
      () => Process.start(
        batchFile.path,
        const [],
        mode: ProcessStartMode.detached,
        runInShell: true,
      ),
      () => Process.start(
        'cmd.exe',
        ['/c', batchFile.path],
        mode: ProcessStartMode.detached,
      ),
      () => Process.start(
        'powershell.exe',
        [
          '-WindowStyle',
          'Hidden',
          '-ExecutionPolicy',
          'Bypass',
          '-NoProfile',
          '-Command',
          "Start-Process -FilePath '${batchFile.path}' -Verb RunAs",
        ],
        mode: ProcessStartMode.detached,
      ),
    ];

    Object? lastError;
    for (var i = 0; i < attempts.length; i++) {
      try {
        final process = await attempts[i]();
        debugPrint('[WindowsUpdateInstaller] 更新器已启动（方式 ${i + 1}，'
            'PID ${process.pid}）');
        return;
      } catch (e) {
        lastError = e;
        debugPrint('[WindowsUpdateInstaller] 启动方式 ${i + 1} 失败: $e');
      }
    }
    throw UpdateInstallFailure('无法启动更新程序：$lastError');
  }

  /// PowerShell 参数里的路径统一用反斜杠，混用分隔符会让带空格的路径更易出错。
  static String _windowsPath(String path) => path.replaceAll('/', r'\');
}
