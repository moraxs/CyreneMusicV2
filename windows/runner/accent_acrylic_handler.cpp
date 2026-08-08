#include "accent_acrylic_handler.h"

#include <dwmapi.h>

namespace {

// WCA_* / ACCENT_* 常量未随 SDK 头文件暴露，照抄参考实现
// （cyrene_music_tauri 的 apply_wallpaper_acrylic）与 window-vibrancy。
constexpr DWORD kWcaAccentPolicy = 19;
constexpr DWORD kAccentEnableAcrylicBlurBehind = 4;

// ACCENT_POLICY：与 Win10 1809+ 的 SetWindowCompositionAttribute 一致。
// 着色字段 GradientColor 为 AARRGGBB（A 在高字节），见 HandleApply。
struct AccentPolicy {
  DWORD state;
  DWORD flags;
  DWORD color;
  DWORD animation_id;
};

struct WindowCompositionAttributeData {
  DWORD attribute;
  void* data;
  SIZE_T size_of_data;
};

// SetWindowCompositionAttribute 不在标准头文件，动态加载。
typedef BOOL(WINAPI* SetWindowCompositionAttributeFn)(
    HWND, WindowCompositionAttributeData*);

// 从 EncodableMap 取键值；缺失时返回 nullptr，由调用方决定如何处理。
const flutter::EncodableValue* MapValue(const flutter::EncodableMap& map,
                                        const char* key) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return nullptr;
  }
  return &it->second;
}

}  // namespace

AccentAcrylicHandler::AccentAcrylicHandler(
    flutter::BinaryMessenger* messenger, HWND window)
    : messenger_(messenger),
      window_(window),
      channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, "cyrene/accent_acrylic",
          &flutter::StandardMethodCodec::GetInstance())) {}

AccentAcrylicHandler::~AccentAcrylicHandler() {}

void AccentAcrylicHandler::RegisterChannels() {
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        OnMethodCall(call, std::move(result));
      });
}

void AccentAcrylicHandler::OnMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "apply") {
    if (const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments())) {
      HandleApply(*args, std::move(result));
      return;
    }
    result->Error("bad_args", "apply(argb) requires a map argument");
    return;
  }
  result->NotImplemented();
}

void AccentAcrylicHandler::HandleApply(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto* argb_value = MapValue(args, "argb");
  if (!argb_value || !std::holds_alternative<int64_t>(*argb_value)) {
    result->Error("bad_args", "argb(int) is required");
    return;
  }
  const DWORD argb = static_cast<DWORD>(
      static_cast<uint32_t>(std::get<int64_t>(*argb_value) & 0xFFFFFFFF));

  // 先复位 Mica / 系统 backdrop，避免与 ACCENT 亚克力叠加冲突。
  // DWMWA_SYSTEMBACKDROP_TYPE / DWMWA_MICA_EFFECT 未随旧 SDK 头文件暴露，
  // 按 Win11 常量定义（与 flutter_acrylic / window-vibrancy 一致）。
  const DWORD kSystembackdropType = 38;
  const DWORD kMicaEffect = 1029;
  DWORD backdrop_none = 0;
  BOOL mica_off = FALSE;
  DwmSetWindowAttribute(window_, kSystembackdropType, &backdrop_none,
                        sizeof(backdrop_none));
  DwmSetWindowAttribute(window_, kMicaEffect, &mica_off, sizeof(mica_off));
  // 还原 DWM 扩展边框（至少一个非负边距以保留窗口阴影，与 flutter_acrylic
  // 的复位一致）。
  MARGINS margins = {0, 0, 1, 0};
  DwmExtendFrameIntoClientArea(window_, &margins);

  HMODULE user32 = ::GetModuleHandleW(L"user32.dll");
  if (!user32) {
    result->Error("load_failed", "user32.dll unavailable");
    return;
  }
  auto set_window_composition_attribute =
      reinterpret_cast<SetWindowCompositionAttributeFn>(
          ::GetProcAddress(user32, "SetWindowCompositionAttribute"));
  if (!set_window_composition_attribute) {
    result->Error("unavailable",
                  "SetWindowCompositionAttribute not exported (Win10 1809+)");
    return;
  }

  AccentPolicy policy{};
  policy.state = kAccentEnableAcrylicBlurBehind;
  // 与 window-vibrancy / 参考实现一致：亚克力用 flags=0（非亚克力的
  // blur-behind 才用 2）。
  policy.flags = 0;
  policy.color = argb;
  policy.animation_id = 0;

  WindowCompositionAttributeData data{};
  data.attribute = kWcaAccentPolicy;
  data.data = &policy;
  data.size_of_data = sizeof(policy);

  if (set_window_composition_attribute(window_, &data)) {
    result->Success();
  } else {
    result->Error("apply_failed", "SetWindowCompositionAttribute failed");
  }
}