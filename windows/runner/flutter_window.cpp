#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "accent_acrylic_handler.h"
#include "smtc_handler.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // SMTC（系统媒体传输控件）原生桥：注册 MethodChannel/EventChannel。
  // 须在引擎就绪后、UI 线程上注册；Flutter 的 platform thread 即主线程。
  smtc_handler_ = std::make_unique<SmtcHandler>(
      flutter_controller_->engine()->messenger(), GetHandle());
  smtc_handler_->RegisterChannels();

  // 原生真·亚克力（毛玻璃）桥：注册 MethodChannel。
  accent_acrylic_handler_ = std::make_unique<AccentAcrylicHandler>(
      flutter_controller_->engine()->messenger(), GetHandle());
  accent_acrylic_handler_->RegisterChannels();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // 先释放原生桥（撤销 WinRT 事件订阅 / 平台通道），再销毁引擎。
  accent_acrylic_handler_.reset();
  smtc_handler_.reset();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case SmtcHandler::kWmSetThumbnail:
      // 后台协程在 UI 线程设置 SMTC 缩略图。handler 可能已随窗口销毁释放，
      // 此时走静态路径释放消息里的内存流，避免泄漏。
      if (smtc_handler_) {
        smtc_handler_->OnSetThumbnailMessage(wparam, lparam);
      } else {
        SmtcHandler::ReleaseThumbnailMessage(lparam);
      }
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
