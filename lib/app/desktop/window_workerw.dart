import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 桌面歌词覆盖层原生桥。
///
/// 对应 windows/runner/workerw_handler.cpp 的 MethodChannel "cyrene/workerw"。
/// runner 自托管第二个 Flutter 引擎（entrypoint args = "wallpaper-player"），
/// 由 [createLyricsWindow] 创建并显示覆盖层窗口。窗口为全屏顶层 WS_POPUP、
/// 置底、不进任务栏、per-pixel alpha、默认整窗鼠标穿透（设置面板区域除外）。
///
/// 命中区域上报与跨引擎状态推送不再走这里：命中区域由子窗口 Dart 直接经
/// `cyrene/desktop_lyrics` MethodChannel 上报原生（见 desktop_player_bridge.dart
/// 的 DesktopPlayerCommands.setHitRects），播放状态经 `to_sub`/`to_main`
/// 通道中继（见 desktop_player_bridge.dart）。
class WindowWorkerW {
  WindowWorkerW._();

  static final WindowWorkerW instance = WindowWorkerW._();

  static const _channel = MethodChannel('cyrene/workerw');

  /// 创建并显示桌面歌词覆盖层窗口（自托管子引擎，一步到位）。
  ///
  /// 返回 {screenWidth, screenHeight, iconsHidden}：失败返回空 Map。
  Future<Map<String, int>> createLyricsWindow() async {
    try {
      final result = await _channel.invokeMethod<Map>('createLyricsWindow');
      if (result != null) {
        return result.map(
          (key, value) => MapEntry(
            key.toString(),
            value is bool ? (value ? 1 : 0) : (value as num).toInt(),
          ),
        );
      }
    } catch (e) {
      debugPrint('[WorkerW] 创建桌面歌词窗口失败: $e');
    }
    return {};
  }

  /// 销毁覆盖层窗口并恢复桌面图标。
  Future<void> closeWindow() async {
    try {
      await _channel.invokeMethod<void>('closeWindow');
    } catch (e) {
      debugPrint('[WorkerW] 销毁覆盖层失败: $e');
    }
  }

  /// 诊断用：dump 所有 Progman / WorkerW 窗口树（按 z-order），
  /// 标出我们的窗口挂在哪一层。
  Future<void> dumpDesktopTree() async {
    try {
      final lines = await _channel.invokeMethod<List>('dumpDesktopTree');
      debugPrint('===== 桌面窗口层级 =====');
      for (final line in lines ?? const []) {
        debugPrint('$line');
      }
      debugPrint('========================');
    } catch (e) {
      debugPrint('[WorkerW] dump 桌面层级失败: $e');
    }
  }
}
