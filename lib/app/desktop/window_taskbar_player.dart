import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 任务栏播放器在任务栏空白区里的水平对齐方式。
///
/// [wireName] 是传给原生的字符串，须与 taskbar_player_window.cpp 的
/// ParseAlignment 保持一致。
enum TaskbarPlayerAlignment {
  left('left', '靠左', '任务栏左侧第一段空白'),
  center('center', '居中', '任务栏上最宽的一段空白'),
  right('right', '靠右', '紧贴系统托盘左侧');

  const TaskbarPlayerAlignment(this.wireName, this.label, this.subtitle);

  final String wireName;
  final String label;
  final String subtitle;

  static TaskbarPlayerAlignment fromName(String? name) =>
      TaskbarPlayerAlignment.values.firstWhere(
        (value) => value.wireName == name,
        orElse: () => TaskbarPlayerAlignment.center,
      );
}

/// 任务栏播放器的形态。
///
/// [wireName] 是与原生互传的字符串，须与 taskbar_player_window.cpp 的
/// ParseMode / NotifyModeChanged 保持一致。
enum TaskbarPlayerMode {
  /// 固定在任务栏空白区，位置由空白扫描算出，随任务栏变化跟进。
  pinned('pinned'),

  /// 被用户拖出任务栏，自由悬浮，位置由用户决定。
  floating('floating');

  const TaskbarPlayerMode(this.wireName);

  final String wireName;

  static TaskbarPlayerMode fromName(String? name) =>
      name == 'floating' ? TaskbarPlayerMode.floating : TaskbarPlayerMode.pinned;
}

/// 任务栏播放器原生桥。
///
/// 对应 windows/runner/taskbar_player_handler.cpp 的 MethodChannel
/// "cyrene/taskbar_player"。runner 自托管第三个 Flutter 引擎
/// （entrypoint args = "taskbar-player"），由 [openPlayer] 创建并显示窗口。
///
/// 窗口是独立顶层 WS_POPUP、置顶、owner 为 Shell_TrayWnd、不进任务栏、
/// per-pixel alpha。**不是**真嵌入任务栏（没有 SetParent，也没走 AppBar API），
/// 只是借 owner 关系视觉贴合，因此可以被拖出来变成自由悬浮窗。
class WindowTaskbarPlayer {
  WindowTaskbarPlayer._();

  static final WindowTaskbarPlayer instance = WindowTaskbarPlayer._();

  static const _channel = MethodChannel('cyrene/taskbar_player');

  /// 拖拽结束后原生回报的新形态与位置（物理像素）。由主窗口注册，用于持久化。
  void Function(TaskbarPlayerMode mode, int x, int y)? onModeChanged;

  /// 注册原生 → Dart 的回调通道。须在 [openPlayer] 之前调用一次。
  void bindCallbacks() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onModeChanged') {
        final args = call.arguments;
        if (args is Map) {
          onModeChanged?.call(
            TaskbarPlayerMode.fromName(args['mode']?.toString()),
            (args['x'] as num?)?.toInt() ?? 0,
            (args['y'] as num?)?.toInt() ?? 0,
          );
        }
      }
      return null;
    });
  }

  /// 创建并显示任务栏播放器窗口。已存在时只更新对齐并重新定位（幂等）。
  ///
  /// [mode] 为 [TaskbarPlayerMode.floating] 时窗口出生在 ([x], [y])
  /// （物理像素）；为 pinned 时忽略这两个参数。
  ///
  /// 返回是否成功。
  Future<bool> openPlayer(
    TaskbarPlayerAlignment alignment, {
    TaskbarPlayerMode mode = TaskbarPlayerMode.pinned,
    int x = 0,
    int y = 0,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('openPlayer', {
        'alignment': alignment.wireName,
        'mode': mode.wireName,
        'x': x,
        'y': y,
      });
      return ok ?? false;
    } catch (e) {
      debugPrint('[任务栏播放器] 创建窗口失败: $e');
      return false;
    }
  }

  /// 销毁任务栏播放器窗口。
  Future<void> closePlayer() async {
    try {
      await _channel.invokeMethod<void>('closePlayer');
    } catch (e) {
      debugPrint('[任务栏播放器] 销毁窗口失败: $e');
    }
  }

  /// 改变对齐方式并立即重新定位。窗口没开着时返回 false（不是错误：
  /// 设置项可以先改，下次开启时生效）。
  Future<bool> setAlignment(TaskbarPlayerAlignment alignment) async {
    try {
      final ok = await _channel.invokeMethod<bool>('setAlignment', {
        'alignment': alignment.wireName,
      });
      return ok ?? false;
    } catch (e) {
      debugPrint('[任务栏播放器] 设置对齐失败: $e');
      return false;
    }
  }

  /// 探测 Shell_TrayWnd 是否存在。任务栏被第三方工具替换或隐藏时为 false。
  Future<bool> isTaskbarAvailable() async {
    try {
      final ok = await _channel.invokeMethod<bool>('isTaskbarAvailable');
      return ok ?? false;
    } catch (e) {
      debugPrint('[任务栏播放器] 探测任务栏失败: $e');
      return false;
    }
  }
}
