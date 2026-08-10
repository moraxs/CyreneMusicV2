#ifndef RUNNER_WORKERW_HANDLER_H_
#define RUNNER_WORKERW_HANDLER_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

#include <windows.h>

#include "desktop_lyrics_window.h"

/// 桌面歌词覆盖层桥。
///
/// Dart 侧 WindowWorkerW（lib/app/desktop/window_workerw.dart）通过
/// MethodChannel "cyrene/workerw" 调用原生方法：
///   - createLyricsWindow：创建并显示桌面歌词覆盖层窗口（自托管第二个 Flutter
///     引擎，entrypoint args = "wallpaper-player"）。窗口为全屏顶层 WS_POPUP、
///     置底、不进任务栏、per-pixel alpha、默认整窗鼠标穿透（设置面板区域除外）。
///     返回 {screenWidth, screenHeight, iconsHidden}。
///   - closeWindow：销毁覆盖层窗口并恢复桌面图标。
///   - dumpDesktopTree：诊断用，dump 桌面窗口树。
///
/// 取代了原本依赖 desktop_multi_window 插件的 attachToWorkerW 路径：runner 现在
/// 自建窗口类并直接托管子引擎，命中区域上报与状态推送均经原生通道直达，不再有三
/// 跳中转（这正是「设置按钮点不动」的根因）。
class WorkerWHandler {
 public:
  WorkerWHandler(flutter::BinaryMessenger* messenger, HWND window);
  ~WorkerWHandler();

  WorkerWHandler(const WorkerWHandler&) = delete;
  WorkerWHandler& operator=(const WorkerWHandler&) = delete;

  // 注册 MethodChannel（须在 UI 线程调用一次）。
  void RegisterChannels();

 private:
  using EncodableValue = flutter::EncodableValue;

  void OnMethodCall(const flutter::MethodCall<EncodableValue>& call,
                    std::unique_ptr<flutter::MethodResult<EncodableValue>> result);

  // createLyricsWindow：创建覆盖层，隐藏桌面图标。
  void HandleCreateLyricsWindow(
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);

  // closeWindow：销毁覆盖层，恢复桌面图标。
  void HandleCloseWindow(
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);

  // dumpDesktopTree：诊断用，dump 所有 Progman / WorkerW 窗口树。
  void HandleDumpDesktopTree(
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);

  flutter::BinaryMessenger* messenger_;
  HWND window_;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel_;
  std::unique_ptr<DesktopLyricsWindow> lyrics_window_;
};

#endif  // RUNNER_WORKERW_HANDLER_H_
