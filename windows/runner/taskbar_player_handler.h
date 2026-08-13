#ifndef RUNNER_TASKBAR_PLAYER_HANDLER_H_
#define RUNNER_TASKBAR_PLAYER_HANDLER_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

#include <windows.h>

#include "taskbar_player_window.h"

/// 任务栏播放器桥。
///
/// Dart 侧 WindowTaskbarPlayer（lib/app/desktop/window_taskbar_player.dart）
/// 通过 MethodChannel "cyrene/taskbar_player" 调用原生方法：
///   - openPlayer({alignment, mode, x, y})：创建并显示任务栏播放器窗口
///     （自托管第三个 Flutter 引擎，entrypoint args = "taskbar-player"）。
///     窗口为顶层 WS_POPUP、置顶、owner 为 Shell_TrayWnd、不进任务栏、
///     per-pixel alpha。mode = "pinned" 时位置落在任务栏空白区，
///     mode = "floating" 时落在 (x, y)。
///   - closePlayer：销毁窗口。
///   - setAlignment({alignment})：改变在任务栏空白区里的对齐方式（left /
///     center / right）并立即重新定位。
///   - beginDrag：把窗口交给 Windows 的拖拽循环。由子引擎在 onPanStart 时
///     调用，松手后原生自行判定吸附。
///   - isTaskbarAvailable：探测 Shell_TrayWnd 是否存在（供设置页判断该功能
///     在当前环境下是否可用）。
///
/// 反向（原生 → 主窗口 Dart）：
///   - onModeChanged({mode, x, y})：拖拽结束后回报新形态与位置，供 Dart
///     侧持久化。由 TaskbarPlayerWindow 直接发起。
class TaskbarPlayerHandler {
 public:
  TaskbarPlayerHandler(flutter::BinaryMessenger* messenger, HWND window);
  ~TaskbarPlayerHandler();

  TaskbarPlayerHandler(const TaskbarPlayerHandler&) = delete;
  TaskbarPlayerHandler& operator=(const TaskbarPlayerHandler&) = delete;

  // 注册 MethodChannel（须在 UI 线程调用一次）。
  void RegisterChannels();

 private:
  using EncodableValue = flutter::EncodableValue;

  void OnMethodCall(
      const flutter::MethodCall<EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);

  void HandleOpenPlayer(
      const flutter::MethodCall<EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);

  void HandleClosePlayer(
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);

  void HandleSetAlignment(
      const flutter::MethodCall<EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);

  flutter::BinaryMessenger* messenger_;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel_;
  std::unique_ptr<TaskbarPlayerWindow> player_window_;
};

#endif  // RUNNER_TASKBAR_PLAYER_HANDLER_H_
