#ifndef RUNNER_ACCENT_ACRYLIC_HANDLER_H_
#define RUNNER_ACCENT_ACRYLIC_HANDLER_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include <windows.h>

// 原生真·亚克力（毛玻璃）桥。
//
// Dart 侧 WindowAccentAcrylic（lib/app/desktop/window_accent_acrylic.dart）
// 通过 MethodChannel "cyrene/accent_acrylic" 的 apply(argb) 下行原生调用。
// 原生端用 SetWindowCompositionAttribute + ACCENT_ENABLE_ACRYLICBLURBEHIND
// 让 DWM 实时采样并模糊窗口背后的内容（壁纸/桌面图标/其他窗口），实现真正
// 的“毛玻璃”效果——对应参考实现（cyrene_music_tauri 的
// apply_wallpaper_acrylic）。
//
// 为什么不用 flutter_acrylic 的 WindowEffect.acrylic：Win11 22H2+ 上它走
// DWMWA_SYSTEMBACKDROP_TYPE backdrop（只喷涂壁纸的 Mica 系材质），没有
// ACCENT 这层实时模糊。Mica / 不透明材质仍由 flutter_acrylic 负责，只有
// 亚克力需要这里补原生实现。
class AccentAcrylicHandler {
 public:
  // |messenger| 由 Flutter 引擎持有，生命周期长于本对象；|window| 为宿主
  // 顶层窗口句柄，SetWindowCompositionAttribute / DwmSetWindowAttribute
  // 只认 HWND。
  AccentAcrylicHandler(flutter::BinaryMessenger* messenger, HWND window);
  ~AccentAcrylicHandler();

  AccentAcrylicHandler(const AccentAcrylicHandler&) = delete;
  AccentAcrylicHandler& operator=(const AccentAcrylicHandler&) = delete;

  // 注册 MethodChannel（须在 UI 线程调用一次）。
  void RegisterChannels();

 private:
  using EncodableValue = flutter::EncodableValue;

  void OnMethodCall(
      const flutter::MethodCall<EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);

  // apply(argb: int)：argb 为 AARRGGBB 着色；调用前先复位 DWMWA 系统
  // backdrop 与 Mica，避免与 ACCENT 亚克力叠加冲突。
  void HandleApply(const flutter::EncodableMap& args,
                   std::unique_ptr<flutter::MethodResult<EncodableValue>> result);

  flutter::BinaryMessenger* messenger_;
  HWND window_;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel_;
};

#endif  // RUNNER_ACCENT_ACRYLIC_HANDLER_H_