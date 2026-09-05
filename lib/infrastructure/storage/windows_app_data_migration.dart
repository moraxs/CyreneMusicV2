import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Windows 应用数据目录搬家。
///
/// Windows 上的应用数据目录不是写死的，而是 `path_provider_windows` 在运行时
/// 从 exe 的版本信息资源里读出 `CompanyName` / `ProductName` 拼出来的
/// （`%APPDATA%\<CompanyName>\<ProductName>`，见 windows/runner/Runner.rc）。
/// 那两个字段此前一直是 Flutter 模板默认的 `com.example` / `cyrene_music_reborn`，
/// 改成正式名称等于把偏好、崩溃日志、歌曲缓存整体挪了地方——老用户升级后会
/// 发现要重新登录、设置全没了。
///
/// 所以升级后第一次启动时把旧目录里的东西整体挪过来。判据是「新目录还没有
/// `shared_preferences.json`」，因此是一次性的：全新安装或已经迁过的直接跳过。
///
/// 必须在**任何**代码碰应用数据目录之前调用（崩溃日志、偏好存储都在其中），
/// 见 main() 的调用点。
class WindowsAppDataMigration {
  const WindowsAppDataMigration._();

  /// 2.0.4 及更早版本用的目录名（Runner.rc 里的模板默认值）。
  static const _legacyCompany = 'com.example';
  static const _legacyProduct = 'cyrene_music_reborn';

  static const _preferencesFile = 'shared_preferences.json';

  static Future<void> run() async {
    if (!Platform.isWindows) return;
    try {
      // 这一步会顺带把新目录建出来（path_provider 的行为）。
      final target = await getApplicationSupportDirectory();
      if (await File(p.join(target.path, _preferencesFile)).exists()) return;

      final appData = Platform.environment['APPDATA'];
      if (appData == null || appData.isEmpty) return;
      final legacy = Directory(p.join(appData, _legacyCompany, _legacyProduct));
      if (p.equals(legacy.path, target.path)) return;
      if (!await legacy.exists()) return;

      var moved = 0;
      await for (final entity in legacy.list()) {
        final destination = p.join(target.path, p.basename(entity.path));
        try {
          // 同一个盘符下 rename 是瞬时的，几 GB 的歌曲缓存也不用真的拷一遍。
          await entity.rename(destination);
          moved += 1;
        } catch (error) {
          debugPrint('[AppData 迁移] ${p.basename(entity.path)} 移动失败: $error');
        }
      }
      debugPrint('[AppData 迁移] 已迁移 $moved 项：${legacy.path} → ${target.path}');
      // 旧目录空了就顺手清掉，连带只剩空壳的 com.example。
      await _deleteIfEmpty(legacy);
      await _deleteIfEmpty(legacy.parent);
    } catch (error) {
      // 迁移失败最多是回到「像新装一样」，绝不能挡住启动。
      debugPrint('[AppData 迁移] 失败（不影响启动）: $error');
    }
  }

  static Future<void> _deleteIfEmpty(Directory directory) async {
    try {
      if (await directory.list().isEmpty) await directory.delete();
    } catch (_) {}
  }
}
