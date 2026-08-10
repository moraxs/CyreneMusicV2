#include "desktop_lyrics_window.h"

#include <dwmapi.h>
#include <windowsx.h>

#include <algorithm>
#include <mutex>
#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "flutter/standard_method_codec.h"

namespace {

// ==================== 命中区域（窗口客户区坐标，物理像素） ====================
//
// 桌面覆盖层默认整窗穿透；设置面板等需交互区域由 Dart 侧经
// cyrene/desktop_lyrics 的 setHitRects 上报。顶层与子视图两处 WndProc 都查它。

std::mutex g_hit_rects_mutex;
std::vector<RECT> g_hit_rects;

void SetHitRectsLocked(const std::vector<RECT>& rects) {
  std::lock_guard<std::mutex> lock(g_hit_rects_mutex);
  g_hit_rects = rects;
}

bool PointInHitRects(HWND hwnd, POINT screen_pt) {
  POINT pt = screen_pt;
  if (!::ScreenToClient(hwnd, &pt)) return false;
  std::lock_guard<std::mutex> lock(g_hit_rects_mutex);
  for (const RECT& r : g_hit_rects) {
    if (::PtInRect(&r, pt)) return true;
  }
  return false;
}

// ==================== 窗口类 ====================

constexpr const wchar_t kClassName[] = L"CyreneDesktopLyricsOverlay";

bool RegisterWindowClass() {
  WNDCLASS wc{};
  wc.lpfnWndProc = DesktopLyricsWindow::WndProc;
  wc.hInstance = ::GetModuleHandle(nullptr);
  wc.hCursor = ::LoadCursor(nullptr, IDC_ARROW);
  wc.lpszClassName = kClassName;
  // hbrBackground = 0：不画背景，透明像素透出壁纸。
  wc.hbrBackground = nullptr;
  wc.style = CS_HREDRAW | CS_VREDRAW;
  return ::RegisterClassW(&wc) != 0;
}

// ==================== per-pixel alpha ====================

void EnableWindowTransparency(HWND hwnd) {
  HRGN region = ::CreateRectRgn(0, 0, -1, -1);
  DWM_BLURBEHIND bb{};
  bb.dwFlags = DWM_BB_ENABLE | DWM_BB_BLURREGION;
  bb.fEnable = TRUE;
  bb.hRgnBlur = region;
  ::DwmEnableBlurBehindWindow(hwnd, &bb);
  if (region) ::DeleteObject(region);
}

// ==================== 壁纸亚克力（展览馆背景） ====================
//
// Flutter 的 BackdropFilter 只能模糊**本层已绘制的内容**；覆盖层背后是真实的
// 桌面壁纸（含 Wallpaper Engine 的动态壁纸），不在 Flutter 合成树里，纯 Dart
// 无论如何都模糊不到。真正模糊只能交给 DWM。
//
// 与主窗口的 accent_acrylic_handler.cpp 同一套写法（ACCENT_ENABLE_
// ACRYLICBLURBEHIND + SetWindowCompositionAttribute），常量照抄那边。
//
// 只改「窗口的合成属性」，不触碰 z-order、WS_EX 样式与命中测试——
// 展览馆开时打开、关时还原（state=ACCENT_DISABLED）。

constexpr DWORD kWcaAccentPolicy = 19;
constexpr DWORD kAccentDisabled = 0;
constexpr DWORD kAccentEnableAcrylicBlurBehind = 4;

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

typedef BOOL(WINAPI* SetWindowCompositionAttributeFn)(
    HWND, WindowCompositionAttributeData*);

// |argb| 为着色层（A 在高字节）。|enabled| 为 false 时复位为无效果，
// 窗口回到纯 per-pixel alpha 的透明覆盖层。
bool SetWallpaperAcrylic(HWND hwnd, bool enabled, DWORD argb) {
  HMODULE user32 = ::GetModuleHandleW(L"user32.dll");
  if (!user32) return false;
  auto set_window_composition_attribute =
      reinterpret_cast<SetWindowCompositionAttributeFn>(
          ::GetProcAddress(user32, "SetWindowCompositionAttribute"));
  // Win10 1809 之前没有这个导出：直接失败，Dart 侧回退到不模糊的暗蒙版。
  if (!set_window_composition_attribute) return false;

  AccentPolicy policy{};
  policy.state = enabled ? kAccentEnableAcrylicBlurBehind : kAccentDisabled;
  // 亚克力用 flags=0（非亚克力的 blur-behind 才用 2），与主窗口实现一致。
  policy.flags = 0;
  policy.color = enabled ? argb : 0;
  policy.animation_id = 0;

  WindowCompositionAttributeData data{};
  data.attribute = kWcaAccentPolicy;
  data.data = &policy;
  data.size_of_data = sizeof(policy);
  return set_window_composition_attribute(hwnd, &data) != FALSE;
}

// ==================== 子视图子类化 ====================

constexpr wchar_t kSubViewPropName[] = L"CyreneDesktopLyricsOriginalProc";

LRESULT CALLBACK SubViewWndProc(HWND hwnd, UINT message, WPARAM wparam,
                                LPARAM lparam) noexcept {
  if (message == WM_NCHITTEST) {
    // 鼠标先打到 Flutter 视图子窗口（其 WndProc 属于引擎，默认返回 HTCLIENT，
    // 会让整窗可点）。这里按命中矩形收紧：命中内 HTCLIENT，其余 HTTRANSPARENT，
    // 让点击穿透到下层（壁纸/桌面）。注意 ScreenToClient 用顶层窗口做坐标换算。
    POINT pt{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
    HWND top = ::GetAncestor(hwnd, GA_ROOT);
    if (top && PointInHitRects(top, pt)) return HTCLIENT;
    return HTTRANSPARENT;
  }
  WNDPROC original = reinterpret_cast<WNDPROC>(::GetPropW(hwnd, kSubViewPropName));
  if (original) {
    return ::CallWindowProcW(original, hwnd, message, wparam, lparam);
  }
  return ::DefWindowProcW(hwnd, message, wparam, lparam);
}

void SubclassSubView(HWND sub_view) {
  if (!sub_view) return;
  if (::GetPropW(sub_view, kSubViewPropName)) return;  // 已子类化
  LONG_PTR original = ::SetWindowLongPtrW(
      sub_view, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(SubViewWndProc));
  ::SetPropW(sub_view, kSubViewPropName, reinterpret_cast<HANDLE>(original));
}

void UnsubclassSubView(HWND sub_view) {
  if (!sub_view) return;
  WNDPROC original = reinterpret_cast<WNDPROC>(::GetPropW(sub_view, kSubViewPropName));
  if (!original) return;
  ::SetWindowLongPtrW(sub_view, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(original));
  ::RemovePropW(sub_view, kSubViewPropName);
}

}  // namespace

// ==================== Create（工厂） ====================

std::unique_ptr<DesktopLyricsWindow> DesktopLyricsWindow::Create(
    flutter::BinaryMessenger* main_messenger,
    int screen_w,
    int screen_h) {
  static bool registered = RegisterWindowClass();
  if (!registered) return nullptr;

  // 引擎先创建（不依赖窗口句柄）。DartProject 用 "data" 作为 assets 路径，
  // 与 main.cpp / flutter_window.cpp 一致。
  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments({"wallpaper-player"});
  auto controller = std::make_unique<flutter::FlutterViewController>(
      screen_w, screen_h, project);
  if (!controller->engine() || !controller->view()) {
    return nullptr;
  }
  // 子引擎也要注册插件（与原 flutter_window.cpp 子窗口回调一致）。
  RegisterPlugins(controller->engine());

  HWND hwnd = ::CreateWindowExW(
      WS_EX_TOOLWINDOW,  // 不进任务栏/Alt-Tab；不加 NOACTIVATE/TRANSPARENT
                         // （会硬性阻止激活/点击，见原 workerw_handler.cpp:369）
      kClassName, L"", WS_POPUP,  // 出生不可见，配置完再 Show
      0, 0, screen_w, screen_h,
      nullptr, nullptr, ::GetModuleHandle(nullptr), nullptr);
  if (!hwnd) return nullptr;

  // 用裸 new 而非 make_unique：构造函数私有，且需在 GWLP_USERDATA 关联前完成。
  return std::unique_ptr<DesktopLyricsWindow>(
      new DesktopLyricsWindow(main_messenger, hwnd, std::move(controller)));
}

// ==================== 构造 / 析构 ====================

DesktopLyricsWindow::DesktopLyricsWindow(
    flutter::BinaryMessenger* main_messenger,
    HWND hwnd,
    std::unique_ptr<flutter::FlutterViewController> controller)
    : main_messenger_(main_messenger),
      sub_messenger_(controller->engine()->messenger()),
      hwnd_(hwnd),
      controller_(std::move(controller)) {
  ::SetWindowLongPtrW(hwnd_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));

  // 把 Flutter 视图子窗口挂进我们的顶层窗口并铺满客户区。
  HWND view = controller_->view()->GetNativeWindow();
  ::SetParent(view, hwnd_);
  RECT client{};
  ::GetClientRect(hwnd_, &client);
  ::MoveWindow(view, client.left, client.top, client.right - client.left,
               client.bottom - client.top, TRUE);

  EnableWindowTransparency(hwnd_);
  SubclassSubView(view);
  RegisterChannels();

  // 显示并钉底：SW_SHOWNA 不抢焦点；HWND_BOTTOM 让任何普通窗口都盖在歌词之上，
  // 而歌词背后透出的是壁纸层。
  ::ShowWindow(hwnd_, SW_SHOWNA);
  ::SetWindowPos(hwnd_, HWND_BOTTOM, 0, 0, 0, 0,
                 SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE);
  controller_->ForceRedraw();
}

DesktopLyricsWindow::~DesktopLyricsWindow() {
  UnregisterChannels();
  if (controller_ && controller_->view()) {
    HWND view = controller_->view()->GetNativeWindow();
    if (view) UnsubclassSubView(view);
  }
  if (hwnd_) {
    ::SetWindowLongPtrW(hwnd_, GWLP_USERDATA, 0);
    ::DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
  // controller_ 在成员析构时释放；UnregisterChannels 已先撤掉对 messenger 的引用。
}

// ==================== 通道注册 + 中继 ====================

void DesktopLyricsWindow::RegisterChannels() {
  if (!sub_messenger_ || !main_messenger_) return;

  // 1) cyrene/desktop_lyrics（子引擎侧）：setHitRects / setWallpaperAcrylic 直达原生。
  //    StandardMethodCodec 不可拷贝，不能按值捕获进 lambda；在 handler 内取引用。
  sub_messenger_->SetMessageHandler(
      "cyrene/desktop_lyrics",
      [this](const uint8_t* message, size_t message_size,
             flutter::BinaryReply reply) {
        const auto& codec = flutter::StandardMethodCodec::GetInstance();
        auto call = codec.DecodeMethodCall(message, message_size);
        if (!call) {
          reply(nullptr, 0);
          return;
        }
        const std::string& method = call->method_name();
        if (method == "setHitRects") {
          // Dart 侧以 invokeMethod<void>('setHitRects', [l,t,r,b,...]) 调用，
          // arguments 是扁平 int 列表。
          std::vector<RECT> rects;
          const auto* list = std::get_if<flutter::EncodableList>(
              call->arguments());
          if (list) {
            for (size_t i = 0; i + 3 < list->size(); i += 4) {
              RECT r{};
              r.left = static_cast<LONG>(
                  std::get<int32_t>((*list)[i]));
              r.top = static_cast<LONG>(
                  std::get<int32_t>((*list)[i + 1]));
              r.right = static_cast<LONG>(
                  std::get<int32_t>((*list)[i + 2]));
              r.bottom = static_cast<LONG>(
                  std::get<int32_t>((*list)[i + 3]));
              rects.push_back(r);
            }
          }
          SetHitRectsLocked(rects);
          auto encoded = codec.EncodeSuccessEnvelope(nullptr);
          reply(encoded->data(), encoded->size());
          return;
        }
        if (method == "setWallpaperAcrylic") {
          // 参数：{'enabled': bool, 'argb': int}。展览馆开时打开壁纸亚克力，
          // 关时复位。只改窗口合成属性，不动 z-order / 命中测试。
          bool enabled = false;
          DWORD argb = 0;
          if (const auto* args = std::get_if<flutter::EncodableMap>(
                  call->arguments())) {
            const auto enabled_it =
                args->find(flutter::EncodableValue("enabled"));
            if (enabled_it != args->end()) {
              if (const auto* value = std::get_if<bool>(&enabled_it->second)) {
                enabled = *value;
              }
            }
            const auto argb_it = args->find(flutter::EncodableValue("argb"));
            if (argb_it != args->end()) {
              // Dart int 过通道后可能是 int32 或 int64，两种都收。
              if (const auto* value = std::get_if<int32_t>(&argb_it->second)) {
                argb = static_cast<DWORD>(static_cast<uint32_t>(*value));
              } else if (const auto* wide =
                             std::get_if<int64_t>(&argb_it->second)) {
                argb = static_cast<DWORD>(
                    static_cast<uint32_t>(*wide & 0xFFFFFFFF));
              }
            }
          }
          const bool ok = hwnd_ && SetWallpaperAcrylic(hwnd_, enabled, argb);
          const flutter::EncodableValue reply_value(ok);
          auto encoded = codec.EncodeSuccessEnvelope(&reply_value);
          reply(encoded->data(), encoded->size());
          return;
        }
        // 未知方法：回空成功信封，避免 Dart 侧永久挂起。
        auto encoded = codec.EncodeSuccessEnvelope(nullptr);
        reply(encoded->data(), encoded->size());
      });

  // 2) to_sub（主引擎侧 handler）：主窗口 → 子窗口。收主引擎消息，转发给子引擎。
  main_messenger_->SetMessageHandler(
      "cyrene/desktop_lyrics/to_sub",
      [this](const uint8_t* message, size_t message_size,
             flutter::BinaryReply reply) {
        if (!sub_messenger_ || !hwnd_) {
          reply(nullptr, 0);
          return;
        }
        sub_messenger_->Send(
            "cyrene/desktop_lyrics/to_sub", message, message_size,
            [reply](const uint8_t* r, size_t rsize) { reply(r, rsize); });
      });

  // 3) to_main（子引擎侧 handler）：子窗口 → 主窗口。收子引擎消息，转发给主引擎。
  sub_messenger_->SetMessageHandler(
      "cyrene/desktop_lyrics/to_main",
      [this](const uint8_t* message, size_t message_size,
             flutter::BinaryReply reply) {
        if (!main_messenger_) {
          reply(nullptr, 0);
          return;
        }
        main_messenger_->Send(
            "cyrene/desktop_lyrics/to_main", message, message_size,
            [reply](const uint8_t* r, size_t rsize) { reply(r, rsize); });
      });
}

void DesktopLyricsWindow::UnregisterChannels() {
  if (main_messenger_) {
    main_messenger_->SetMessageHandler("cyrene/desktop_lyrics/to_sub", nullptr);
  }
  if (sub_messenger_) {
    sub_messenger_->SetMessageHandler("cyrene/desktop_lyrics/to_main", nullptr);
    sub_messenger_->SetMessageHandler("cyrene/desktop_lyrics", nullptr);
  }
}

// ==================== 窗口过程 ====================

LRESULT CALLBACK DesktopLyricsWindow::WndProc(HWND window, UINT message,
                                              WPARAM wparam,
                                              LPARAM lparam) noexcept {
  DesktopLyricsWindow* self = reinterpret_cast<DesktopLyricsWindow*>(
      ::GetWindowLongPtrW(window, GWLP_USERDATA));
  if (self) {
    return self->HandleMessage(window, message, wparam, lparam);
  }
  return ::DefWindowProcW(window, message, wparam, lparam);
}

LRESULT DesktopLyricsWindow::HandleMessage(HWND window, UINT message,
                                           WPARAM wparam,
                                           LPARAM lparam) noexcept {
  // 先给 Flutter 引擎处理消息的机会（与原 flutter_window.cpp MessageHandler 一致）。
  if (controller_) {
    std::optional<LRESULT> result = controller_->HandleTopLevelWindowProc(
        window, message, wparam, lparam);
    if (result) return *result;
  }

  switch (message) {
    case WM_NCHITTEST: {
      // 顶层窗口的命中测试：命中矩形内 HTCLIENT，否则穿透。鼠标通常先打到子视图，
      // 但显式处理顶层 WndProc 可覆盖拖动等场景。
      POINT pt{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      return PointInHitRects(window, pt) ? HTCLIENT : HTTRANSPARENT;
    }
    case WM_MOUSEACTIVATE: {
      // 命中区域内允许激活（否则 Flutter 手势收不到点击，面板按下去没反应）；
      // 其余位置拒绝激活，点桌面不打扰歌词窗口。
      POINT pt{};
      ::GetCursorPos(&pt);
      return PointInHitRects(window, pt) ? MA_ACTIVATE : MA_NOACTIVATE;
    }
    case WM_WINDOWPOSCHANGING: {
      // 钉在 z-order 底部：去掉 WS_EX_NOACTIVATE 后窗口可被激活（面板才能点），
      // 而激活会把它提到前面挡住别的窗口。拦下每次位置变更，强制回到底部。
      auto* pos = reinterpret_cast<WINDOWPOS*>(lparam);
      pos->hwndInsertAfter = HWND_BOTTOM;
      pos->flags &= ~SWP_NOZORDER;
      return 0;
    }
    case WM_SIZE: {
      // 子视图跟随客户区尺寸。
      HWND view = controller_ ? controller_->view()->GetNativeWindow() : nullptr;
      if (view) {
        RECT client = GetClientArea();
        ::MoveWindow(view, client.left, client.top,
                     client.right - client.left,
                     client.bottom - client.top, TRUE);
      }
      return 0;
    }
    case WM_DESTROY:
      // 不触发 PostQuitMessage：这是子窗口，关闭它不应退出整个应用。
      return 0;
  }
  return ::DefWindowProcW(window, message, wparam, lparam);
}

RECT DesktopLyricsWindow::GetClientArea() const {
  // Win32Window::GetClientArea 是 protected，这里复刻其实现。
  RECT frame;
  ::GetClientRect(hwnd_, &frame);
  return frame;
}
