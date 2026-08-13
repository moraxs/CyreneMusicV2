import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/desktop/window_taskbar_player.dart';
import '../../application/playback/playback_controller.dart';
import 'taskbar_player_bridge.dart';

/// 任务栏播放器控制器（主窗口侧）。
///
/// 窗口由 runner 自建并自托管子引擎（见 windows/runner/taskbar_player_window.cpp），
/// 本类只负责协调主窗口的状态推送与窗口生命周期。与 DesktopPlayerController
/// 同构。
class TaskbarPlayerController {
  TaskbarPlayerController._();
  static final TaskbarPlayerController instance = TaskbarPlayerController._();

  TaskbarPlayerStateSender? _sender;
  bool _enabled = false;
  bool get isEnabled => _enabled;

  /// 主窗口的播放控制器。启用前必须先设置，否则子窗口收不到任何播放状态。
  PlaybackController? playback;

  /// 拖拽结束后原生回报的新形态与位置的落点。由 main.dart 注入，指向
  /// FullscreenSettingsStore.setTaskbarPlayerPlacement，用于持久化。
  void Function(TaskbarPlayerMode mode, int x, int y)? onPlacementChanged;

  /// 启用任务栏播放器：先建状态推送（注册 toMain 命令 handler）再创建窗口。
  ///
  /// 顺序很关键：先把主窗口的命令 handler 挂上，子引擎启动后索要状态
  /// （requestState）时主窗口一定已就绪。
  ///
  /// [mode] / [x] / [y] 为上次退出时的形态与悬浮位置，用于原样恢复。
  Future<String?> enable(
    TaskbarPlayerAlignment alignment, {
    TaskbarPlayerMode mode = TaskbarPlayerMode.pinned,
    int x = 0,
    int y = 0,
  }) async {
    if (_enabled) {
      // 已开着时改对齐即可，不重建窗口（重建会让子引擎重启、播放器闪一下）。
      await WindowTaskbarPlayer.instance.setAlignment(alignment);
      return null;
    }

    try {
      final source = playback;
      if (source == null) {
        debugPrint('[任务栏播放器] 未设置 playback，将显示为空');
      } else {
        _sender = TaskbarPlayerStateSender(
          playback: source,
          onShowMain: _showMainWindow,
        );
      }

      // 回调要在建窗之前挂好：窗口一旦创建，用户随时可能拖动它。
      WindowTaskbarPlayer.instance.onModeChanged = (mode, x, y) {
        onPlacementChanged?.call(mode, x, y);
      };
      WindowTaskbarPlayer.instance.bindCallbacks();

      final ok = await WindowTaskbarPlayer.instance.openPlayer(
        alignment,
        mode: mode,
        x: x,
        y: y,
      );
      if (!ok) {
        _sender?.dispose();
        _sender = null;
        return '任务栏播放器创建失败';
      }

      _enabled = true;
      return null;
    } catch (e, stackTrace) {
      debugPrint('[任务栏播放器] 启用失败: $e');
      debugPrint('[任务栏播放器] 堆栈: $stackTrace');
      _sender?.dispose();
      _sender = null;
      _enabled = false;
      return '启用失败: $e';
    }
  }

  /// 禁用任务栏播放器：销毁窗口。
  Future<String?> disable() async {
    // 先停推送再销毁窗口：否则销毁后仍有 invokeMethod 打到已失效的引擎。
    _sender?.dispose();
    _sender = null;
    try {
      await WindowTaskbarPlayer.instance.closePlayer().timeout(
        const Duration(seconds: 5),
        onTimeout: () => debugPrint('[任务栏播放器] closePlayer 超时，强制清理状态'),
      );
      _enabled = false;
      return null;
    } catch (e) {
      debugPrint('[任务栏播放器] 禁用失败: $e');
      _enabled = false;
      return '禁用失败: $e';
    }
  }

  /// 改变对齐方式。窗口没开着时只是空操作（设置项已被 store 持久化，
  /// 下次开启时生效）。
  Future<void> setAlignment(TaskbarPlayerAlignment alignment) async {
    if (!_enabled) return;
    await WindowTaskbarPlayer.instance.setAlignment(alignment);
  }

  /// 唤起主窗口（点任务栏播放器的封面时）。最小化状态下要先 restore，
  /// 否则 show() 只会让它在任务栏闪一下而不真正展开。
  Future<void> _showMainWindow() async {
    try {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('[任务栏播放器] 唤起主窗口失败: $e');
    }
  }
}
