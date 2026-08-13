#include "taskbar_player_handler.h"

#include <string>

#include "flutter/standard_method_codec.h"

namespace {

/// 从 MethodCall 的参数 map 里取字符串。缺失时返回空串。
std::string ReadStringArg(const flutter::EncodableValue* arguments,
                          const char* key) {
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (!map) return "";
  const auto it = map->find(flutter::EncodableValue(key));
  if (it == map->end()) return "";
  const auto* value = std::get_if<std::string>(&it->second);
  return value ? *value : "";
}

/// 从 MethodCall 的参数 map 里取整数。Dart int 过通道后可能是 int32 或
/// int64，两种都收。缺失时返回 |fallback|。
int ReadIntArg(const flutter::EncodableValue* arguments, const char* key,
               int fallback) {
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (!map) return fallback;
  const auto it = map->find(flutter::EncodableValue(key));
  if (it == map->end()) return fallback;
  if (const auto* narrow = std::get_if<int32_t>(&it->second)) {
    return static_cast<int>(*narrow);
  }
  if (const auto* wide = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(*wide);
  }
  return fallback;
}

}  // namespace

TaskbarPlayerHandler::TaskbarPlayerHandler(
    flutter::BinaryMessenger* messenger, HWND window)
    : messenger_(messenger),
      channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, "cyrene/taskbar_player",
          &flutter::StandardMethodCodec::GetInstance())) {
  // 任务栏播放器窗口是自建顶层窗口，不挂在主窗口下，因此用不到主窗口句柄。
  (void)window;
}

TaskbarPlayerHandler::~TaskbarPlayerHandler() = default;

void TaskbarPlayerHandler::RegisterChannels() {
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        OnMethodCall(call, std::move(result));
      });
}

void TaskbarPlayerHandler::OnMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "openPlayer") {
    HandleOpenPlayer(call, std::move(result));
    return;
  }
  if (method == "closePlayer") {
    HandleClosePlayer(std::move(result));
    return;
  }
  if (method == "setAlignment") {
    HandleSetAlignment(call, std::move(result));
    return;
  }
  if (method == "beginDrag") {
    if (player_window_) player_window_->BeginDrag();
    result->Success();
    return;
  }
  if (method == "isTaskbarAvailable") {
    const bool available =
        ::FindWindowW(L"Shell_TrayWnd", nullptr) != nullptr;
    result->Success(flutter::EncodableValue(available));
    return;
  }
  result->NotImplemented();
}

void TaskbarPlayerHandler::HandleOpenPlayer(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto alignment = TaskbarPlayerWindow::ParseAlignment(
      ReadStringArg(call.arguments(), "alignment"));

  // 已存在则只更新对齐并重新定位（幂等）：重复调 openPlayer 不该销毁重建，
  // 那会让子引擎重启、播放器闪一下。
  if (player_window_) {
    player_window_->SetAlignment(alignment);
    player_window_->Reposition();
    result->Success(flutter::EncodableValue(true));
    return;
  }

  const auto mode =
      TaskbarPlayerWindow::ParseMode(ReadStringArg(call.arguments(), "mode"));
  const int x = ReadIntArg(call.arguments(), "x", 0);
  const int y = ReadIntArg(call.arguments(), "y", 0);

  player_window_ =
      TaskbarPlayerWindow::Create(messenger_, alignment, mode, x, y);
  if (!player_window_) {
    result->Error("create_failed", "Failed to create taskbar player window");
    return;
  }
  result->Success(flutter::EncodableValue(true));
}

void TaskbarPlayerHandler::HandleClosePlayer(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  player_window_.reset();
  result->Success();
}

void TaskbarPlayerHandler::HandleSetAlignment(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (!player_window_) {
    // 播放器没开着时改对齐不是错误：设置项可以先改，下次开启时生效。
    result->Success(flutter::EncodableValue(false));
    return;
  }
  player_window_->SetAlignment(TaskbarPlayerWindow::ParseAlignment(
      ReadStringArg(call.arguments(), "alignment")));
  result->Success(flutter::EncodableValue(true));
}
