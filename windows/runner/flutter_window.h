#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "accent_acrylic_handler.h"
#include "smtc_handler.h"
#include "taskbar_player_handler.h"
#include "win32_window.h"
#include "workerw_handler.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // SMTC（系统媒体传输控件）原生桥。
  std::unique_ptr<SmtcHandler> smtc_handler_;

  // 原生真·亚克力（毛玻璃）桥。
  std::unique_ptr<AccentAcrylicHandler> accent_acrylic_handler_;

  // WorkerW 壁纸层桥。
  std::unique_ptr<WorkerWHandler> workerw_handler_;

  // 任务栏播放器桥。
  std::unique_ptr<TaskbarPlayerHandler> taskbar_player_handler_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
