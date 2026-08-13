#include "taskbar_player_window.h"

#include <dwmapi.h>
#include <windowsx.h>

#include <algorithm>
#include <optional>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "flutter/standard_method_codec.h"

namespace {

// ==================== 尺寸常量（逻辑像素，按 DPI 缩放后使用） ====================

/// 播放器条的逻辑宽度。任务栏高度直接用系统的，不自己定。
constexpr int kLogicalWidth = 260;

/// 空白区不足以容纳播放器时的兜底 X（逻辑像素）。
constexpr int kFallbackLogicalX = 260;

/// 靠右模式下与系统托盘之间留的间隙（逻辑像素）。
constexpr int kTrayGapLogical = 8;

/// 动态重定位轮询周期。任务栏图标会随打开的窗口数量增减而左右移动，而
/// Explorer 不会就此广播任何消息，只能低频轮询。2s 对用户足够跟手，开销
/// 可忽略。仅 kPinned 形态下启用——悬浮时位置归用户，不该被自动挪走。
constexpr UINT kRepositionTimerId = 1;
constexpr UINT kRepositionIntervalMs = 2000;

/// 吸附判定的容差（逻辑像素）。窗口矩形与任务栏矩形的垂直距离小于它时，
/// 松手即吸附回任务栏。取值偏宽松：用户「大致拖回去」就应该吸附成功，
/// 精确对齐是我们的事，不该让用户去瞄准。
constexpr int kSnapThresholdLogical = 60;

// ==================== 窗口类 ====================

constexpr const wchar_t kClassName[] = L"CyreneTaskbarPlayer";

bool RegisterWindowClass() {
  WNDCLASS wc{};
  wc.lpfnWndProc = TaskbarPlayerWindow::WndProc;
  wc.hInstance = ::GetModuleHandle(nullptr);
  wc.hCursor = ::LoadCursor(nullptr, IDC_ARROW);
  wc.lpszClassName = kClassName;
  // hbrBackground = 0：不画背景，透明像素透出任务栏。
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

// ==================== 任务栏几何 ====================

HWND FindTaskbar() {
  return ::FindWindowW(L"Shell_TrayWnd", nullptr);
}

/// 任务栏矩形（屏幕坐标，物理像素）。
bool GetTaskbarRect(RECT* out) {
  HWND taskbar = FindTaskbar();
  if (!taskbar) return false;
  return ::GetWindowRect(taskbar, out) != FALSE;
}

/// 任务栏所在显示器的 DPI。进程本身是 PerMonitorV2（见 runner.exe.manifest），
/// 因此这里拿到的是真实 DPI，与 GetWindowRect 的物理像素同一坐标系。
///
/// ⚠️ 进程若不是 DPI-aware，EnumChildWindows 拿到的任务栏子窗口会被系统的
/// DPI 虚拟化整体抹平（实测返回 0 个可见子窗口），空白区扫描会彻底失效。
UINT GetTaskbarDpi() {
  HWND taskbar = FindTaskbar();
  if (taskbar) {
    UINT dpi = ::GetDpiForWindow(taskbar);
    if (dpi > 0) return dpi;
  }
  return USER_DEFAULT_SCREEN_DPI;
}

int ScaleForTaskbar(int logical) {
  return ::MulDiv(logical, static_cast<int>(GetTaskbarDpi()),
                  USER_DEFAULT_SCREEN_DPI);
}

/// 任务栏上一段被占用的横向区间（物理像素，屏幕坐标）。
struct Span {
  LONG left;
  LONG right;
};

struct EnumSpanData {
  std::vector<Span>* spans;
  LONG taskbar_width;
};

BOOL CALLBACK CollectSpanProc(HWND hwnd, LPARAM lparam) {
  auto* data = reinterpret_cast<EnumSpanData*>(lparam);
  if (!::IsWindowVisible(hwnd)) return TRUE;

  RECT r{};
  if (!::GetWindowRect(hwnd, &r)) return TRUE;

  const LONG width = r.right - r.left;
  // 宽度为 0 的占位控件（TrayDummySearchControl）与铺满整条任务栏的容器
  // （DesktopWindowContentBridge / CoreWindow）都不代表真正被占用的区域。
  if (width <= 0 || width >= data->taskbar_width - 10) return TRUE;

  data->spans->push_back(Span{r.left, r.right});
  return TRUE;
}

/// 收集任务栏上被占用的区间，按左边界排序。
///
/// 只扫 Shell_TrayWnd 的子孙窗口。我们自己的窗口是 owned 而非 child，
/// 不在枚举范围内，因此不会把自己算成障碍物。
std::vector<Span> CollectOccupiedSpans(const RECT& taskbar_rect) {
  std::vector<Span> spans;
  HWND taskbar = FindTaskbar();
  if (!taskbar) return spans;

  EnumSpanData data{&spans, taskbar_rect.right - taskbar_rect.left};
  ::EnumChildWindows(taskbar, CollectSpanProc,
                     reinterpret_cast<LPARAM>(&data));

  std::sort(spans.begin(), spans.end(),
            [](const Span& a, const Span& b) { return a.left < b.left; });
  return spans;
}

/// 在任务栏空白处求一个 X 坐标（物理像素）。
///
/// Win11 居中布局下典型的占用情况是：左缘天气/小组件、居中的图标组
/// （ReBarWindow32）、右侧系统托盘（TrayNotifyWnd）。因此「最宽空白」通常
/// 是左缘到图标组之间那一段。
///
/// 注意：不查 FindWindowW("Button", "Start")。那是 Win10 的开始按钮，
/// Win11 上恒定找不到（实测返回 NULL），查了也是白查。
LONG ComputeTaskbarX(const RECT& taskbar_rect,
                     LONG player_width,
                     TaskbarPlayerWindow::Alignment alignment) {
  // 靠右：紧贴系统托盘左侧，不参与空白扫描——托盘右边没有可用空白。
  if (alignment == TaskbarPlayerWindow::Alignment::kRight) {
    HWND taskbar = FindTaskbar();
    if (taskbar) {
      HWND tray = ::FindWindowExW(taskbar, nullptr, L"TrayNotifyWnd", nullptr);
      RECT tray_rect{};
      if (tray && ::IsWindowVisible(tray) && ::GetWindowRect(tray, &tray_rect)) {
        return tray_rect.left - player_width - ScaleForTaskbar(kTrayGapLogical);
      }
    }
    return taskbar_rect.right - player_width - ScaleForTaskbar(200);
  }

  const std::vector<Span> spans = CollectOccupiedSpans(taskbar_rect);
  if (spans.empty()) {
    return taskbar_rect.left + ScaleForTaskbar(kFallbackLogicalX);
  }

  // 靠左：从左往右扫，取**第一段**放得下的空白并在其中居中。
  if (alignment == TaskbarPlayerWindow::Alignment::kLeft) {
    LONG scan_x = taskbar_rect.left;
    for (const Span& span : spans) {
      const LONG gap = span.left - scan_x;
      if (gap >= player_width) return scan_x + (gap - player_width) / 2;
      if (span.right > scan_x) scan_x = span.right;
    }
    const LONG tail_gap = taskbar_rect.right - scan_x;
    if (tail_gap >= player_width) {
      return scan_x + (tail_gap - player_width) / 2;
    }
    return taskbar_rect.left + ScaleForTaskbar(8);
  }

  // 居中：取**最宽**的空白并在其中居中。
  LONG cursor = taskbar_rect.left;
  LONG max_gap = 0;
  LONG best_x = cursor;
  for (const Span& span : spans) {
    const LONG gap = span.left - cursor;
    if (gap > max_gap) {
      max_gap = gap;
      best_x = cursor;
    }
    if (span.right > cursor) cursor = span.right;
  }
  const LONG tail_gap = taskbar_rect.right - cursor;
  if (tail_gap > max_gap) {
    max_gap = tail_gap;
    best_x = cursor;
  }

  if (max_gap >= player_width) return best_x + (max_gap - player_width) / 2;
  return taskbar_rect.left + ScaleForTaskbar(kFallbackLogicalX);
}

/// 目标窗口矩形：X 由空白扫描决定，Y/高度直接跟随任务栏。
bool ComputeTargetRect(TaskbarPlayerWindow::Alignment alignment, RECT* out) {
  RECT taskbar_rect{};
  if (!GetTaskbarRect(&taskbar_rect)) return false;

  const LONG height = taskbar_rect.bottom - taskbar_rect.top;
  if (height <= 0) return false;

  LONG width = ScaleForTaskbar(kLogicalWidth);
  // 任务栏窄到放不下时收敛到任务栏宽度，别把窗口甩到屏幕外。
  width = std::min<LONG>(width, taskbar_rect.right - taskbar_rect.left);

  const LONG x = ComputeTaskbarX(taskbar_rect, width, alignment);
  out->left = x;
  out->top = taskbar_rect.top;
  out->right = x + width;
  out->bottom = taskbar_rect.top + height;
  return true;
}

/// 窗口当前位置是否「贴近任务栏」，即松手后应当吸附回去。
///
/// 只看垂直方向：横向位置由空白扫描重算，用户拖到任务栏左边还是右边都
/// 一样会被吸到空白区，因此横向不参与判定（否则用户把窗口拖到任务栏正上方
/// 但偏左，会因为「横向不重叠」而吸附失败，很反直觉）。
bool ShouldSnapToTaskbar(const RECT& window_rect) {
  RECT taskbar_rect{};
  if (!GetTaskbarRect(&taskbar_rect)) return false;

  const LONG tolerance = ScaleForTaskbar(kSnapThresholdLogical);

  // 与任务栏在垂直方向上重叠，或窗口底边落在任务栏上沿附近。
  const bool vertically_overlaps =
      window_rect.bottom > taskbar_rect.top - tolerance &&
      window_rect.top < taskbar_rect.bottom + tolerance;
  return vertically_overlaps;
}

}  // namespace

// ==================== Alignment / Mode 解析 ====================

TaskbarPlayerWindow::Alignment TaskbarPlayerWindow::ParseAlignment(
    const std::string& value) {
  if (value == "left") return Alignment::kLeft;
  if (value == "right") return Alignment::kRight;
  return Alignment::kCenter;
}

TaskbarPlayerWindow::Mode TaskbarPlayerWindow::ParseMode(
    const std::string& value) {
  if (value == "floating") return Mode::kFloating;
  return Mode::kPinned;
}

// ==================== Create（工厂） ====================

std::unique_ptr<TaskbarPlayerWindow> TaskbarPlayerWindow::Create(
    flutter::BinaryMessenger* main_messenger,
    Alignment alignment,
    Mode mode,
    int floating_x,
    int floating_y) {
  static bool registered = RegisterWindowClass();
  if (!registered) return nullptr;

  // 尺寸在两种形态下一致（样式不变，只是位置不同），因此都从任务栏几何取。
  RECT target{};
  if (!ComputeTargetRect(alignment, &target)) return nullptr;
  const int width = static_cast<int>(target.right - target.left);
  const int height = static_cast<int>(target.bottom - target.top);

  int x = static_cast<int>(target.left);
  int y = static_cast<int>(target.top);
  if (mode == Mode::kFloating) {
    x = floating_x;
    y = floating_y;
  }

  // 引擎先创建（不依赖窗口句柄）。DartProject 用 "data" 作为 assets 路径，
  // 与 main.cpp / flutter_window.cpp / desktop_lyrics_window.cpp 一致。
  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments({"taskbar-player"});
  auto controller =
      std::make_unique<flutter::FlutterViewController>(width, height, project);
  if (!controller->engine() || !controller->view()) {
    return nullptr;
  }
  RegisterPlugins(controller->engine());

  // WS_EX_TOOLWINDOW：不进任务栏/Alt-Tab（否则播放器自己会在任务栏留一个
  // 按钮，很荒谬）。WS_EX_TOPMOST 让它浮在任务栏之上——这是与桌面歌词
  // （HWND_BOTTOM 壁纸层）最本质的区别。
  // 不加 WS_EX_NOACTIVATE / WS_EX_TRANSPARENT：那会硬性阻止点击，
  // 播放/下一首按钮就点不动了。
  HWND hwnd = ::CreateWindowExW(
      WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
      kClassName, L"", WS_POPUP,  // 出生不可见，配置完再 Show
      x, y, width, height,
      nullptr, nullptr, ::GetModuleHandle(nullptr), nullptr);
  if (!hwnd) return nullptr;

  // 用裸 new 而非 make_unique：构造函数私有，且需在 GWLP_USERDATA 关联前完成。
  return std::unique_ptr<TaskbarPlayerWindow>(new TaskbarPlayerWindow(
      main_messenger, hwnd, std::move(controller), alignment, mode));
}

// ==================== 构造 / 析构 ====================

TaskbarPlayerWindow::TaskbarPlayerWindow(
    flutter::BinaryMessenger* main_messenger,
    HWND hwnd,
    std::unique_ptr<flutter::FlutterViewController> controller,
    Alignment alignment,
    Mode mode)
    : main_messenger_(main_messenger),
      sub_messenger_(controller->engine()->messenger()),
      hwnd_(hwnd),
      controller_(std::move(controller)),
      alignment_(alignment),
      mode_(mode),
      main_channel_(
          std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
              main_messenger,
              "cyrene/taskbar_player",
              &flutter::StandardMethodCodec::GetInstance())) {
  ::SetWindowLongPtrW(hwnd_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));

  // Explorer 重启后会广播这条消息，届时旧的 Shell_TrayWnd 已销毁，
  // owner 关系随之失效，必须重新挂接（见 HandleMessage）。
  taskbar_created_message_ = ::RegisterWindowMessageW(L"TaskbarCreated");

  // 把 Flutter 视图子窗口挂进我们的顶层窗口并铺满客户区。
  HWND view = controller_->view()->GetNativeWindow();
  ::SetParent(view, hwnd_);
  RECT client{};
  ::GetClientRect(hwnd_, &client);
  ::MoveWindow(view, client.left, client.top, client.right - client.left,
               client.bottom - client.top, TRUE);

  EnableWindowTransparency(hwnd_);
  AttachToTaskbar();
  RegisterChannels();

  // 显示并置顶：SW_SHOWNA 不抢焦点（播放器不该在启用时打断用户输入）。
  ::ShowWindow(hwnd_, SW_SHOWNA);
  ::SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE);

  // 任务栏图标随打开的窗口数量左右移动，Explorer 不广播任何消息，只能低频
  // 轮询。仅固定形态需要——悬浮时位置归用户。
  if (mode_ == Mode::kPinned) {
    ::SetTimer(hwnd_, kRepositionTimerId, kRepositionIntervalMs, nullptr);
  }

  controller_->ForceRedraw();
}

TaskbarPlayerWindow::~TaskbarPlayerWindow() {
  UnregisterChannels();
  if (hwnd_) {
    ::KillTimer(hwnd_, kRepositionTimerId);
    ::SetWindowLongPtrW(hwnd_, GWLP_USERDATA, 0);
    ::DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
  // controller_ 在成员析构时释放；UnregisterChannels 已先撤掉对 messenger 的引用。
}

// ==================== 贴合任务栏 / 定位 ====================

void TaskbarPlayerWindow::AttachToTaskbar() {
  if (!hwnd_) return;
  HWND taskbar = FindTaskbar();
  if (!taskbar) return;
  // owner（不是 parent）：窗口仍是独立顶层窗口，只是跟随任务栏的显示/隐藏
  // 与层级。真 SetParent 进 Explorer 的窗口树在 Win11 的 XAML Islands 架构下
  // 既脆弱又会被重建打断。
  ::SetWindowLongPtrW(hwnd_, GWLP_HWNDPARENT,
                      reinterpret_cast<LONG_PTR>(taskbar));
}

void TaskbarPlayerWindow::SetAlignment(Alignment alignment) {
  if (alignment_ == alignment) return;
  alignment_ = alignment;
  Reposition();
}

void TaskbarPlayerWindow::Reposition() {
  if (!hwnd_) return;

  RECT target{};
  if (!ComputeTargetRect(alignment_, &target)) return;

  // 悬浮形态只跟随尺寸（DPI 变化时那条窄栏也要跟着缩放），位置归用户。
  if (mode_ == Mode::kFloating) {
    RECT current{};
    if (!::GetWindowRect(hwnd_, &current)) return;
    const LONG width = target.right - target.left;
    const LONG height = target.bottom - target.top;
    if (current.right - current.left == width &&
        current.bottom - current.top == height) {
      return;
    }
    ::SetWindowPos(hwnd_, HWND_TOPMOST,
                   static_cast<int>(current.left),
                   static_cast<int>(current.top),
                   static_cast<int>(width), static_cast<int>(height),
                   SWP_NOACTIVATE);
    return;
  }

  RECT current{};
  if (::GetWindowRect(hwnd_, &current) &&
      current.left == target.left && current.top == target.top &&
      current.right == target.right && current.bottom == target.bottom) {
    return;  // 没变化就别动，避免每次轮询都触发一次重绘。
  }

  ::SetWindowPos(hwnd_, HWND_TOPMOST,
                 static_cast<int>(target.left), static_cast<int>(target.top),
                 static_cast<int>(target.right - target.left),
                 static_cast<int>(target.bottom - target.top),
                 SWP_NOACTIVATE);
}

// ==================== 拖拽 / 形态切换 ====================

void TaskbarPlayerWindow::BeginDrag() {
  if (!hwnd_) return;
  // 把控制权交给 Windows 自己的拖拽循环：ReleaseCapture 先放掉 Flutter 视图
  // 子窗口的鼠标捕获（否则拖拽循环收不到后续的鼠标移动），再发一个
  // SC_MOVE 系统命令，系统就会进入标准的窗口移动模态循环（内部自带
  // WM_ENTERSIZEMOVE / WM_EXITSIZEMOVE，后者即我们的松手时机）。
  //
  // 用 WM_SYSCOMMAND 而非 WM_NCLBUTTONDOWN：后者要求 lparam 携带正确的屏幕
  // 坐标，且会先经过 Flutter 的 HandleTopLevelWindowProc（可能被当作非客户区
  // 点击处理掉）。SC_MOVE 没有这些坑，也是 window_manager 的 StartDragging
  // 采用的写法。
  //
  // 拖拽全程零 IPC——若改由 Dart 逐帧上报鼠标位置再调 SetWindowPos，
  // 跨引擎往返会让窗口明显滞后于光标。
  ::ReleaseCapture();
  ::SendMessageW(hwnd_, WM_SYSCOMMAND, SC_MOVE | HTCAPTION, 0);
}

void TaskbarPlayerWindow::OnDragFinished() {
  if (!hwnd_) return;

  RECT current{};
  if (!::GetWindowRect(hwnd_, &current)) return;

  if (ShouldSnapToTaskbar(current)) {
    // 吸附回任务栏：切形态会重启轮询定时器，Reposition 把它精确对齐到空白区。
    SetMode(Mode::kPinned);
    Reposition();
  } else {
    SetMode(Mode::kFloating);
  }
  // 无论吸附与否都回报一次：悬浮位置要持久化，下次启动才能回到原处。
  NotifyModeChanged();
}

void TaskbarPlayerWindow::SetMode(Mode mode) {
  if (mode_ == mode) return;
  mode_ = mode;

  // 固定形态要跟着任务栏图标移动；悬浮形态位置归用户，不能被自动挪走。
  if (mode_ == Mode::kPinned) {
    ::SetTimer(hwnd_, kRepositionTimerId, kRepositionIntervalMs, nullptr);
  } else {
    ::KillTimer(hwnd_, kRepositionTimerId);
  }
}

void TaskbarPlayerWindow::NotifyModeChanged() {
  if (!main_channel_ || !hwnd_) return;

  RECT current{};
  if (!::GetWindowRect(hwnd_, &current)) return;

  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("mode")] = flutter::EncodableValue(
      mode_ == Mode::kFloating ? "floating" : "pinned");
  payload[flutter::EncodableValue("x")] =
      flutter::EncodableValue(static_cast<int32_t>(current.left));
  payload[flutter::EncodableValue("y")] =
      flutter::EncodableValue(static_cast<int32_t>(current.top));

  main_channel_->InvokeMethod(
      "onModeChanged",
      std::make_unique<flutter::EncodableValue>(std::move(payload)));
}

// ==================== 通道注册 + 中继 ====================

void TaskbarPlayerWindow::RegisterChannels() {
  if (!sub_messenger_ || !main_messenger_) return;

  // 1) cyrene/taskbar_player（子引擎侧）：beginDrag 直达原生，零中转。
  //
  //    拖拽 UI 在子引擎里，而 TaskbarPlayerHandler 的方法通道注册在**主**
  //    引擎 messenger 上——子引擎调 beginDrag 打不到那里。这里在子引擎
  //    messenger 上另注册一份，且由 C++ 在子引擎启动时同步完成，早于子引擎
  //    Dart 运行，不可能丢（与桌面歌词的 setHitRects 同一套结构性保证）。
  sub_messenger_->SetMessageHandler(
      "cyrene/taskbar_player",
      [this](const uint8_t* message, size_t message_size,
             flutter::BinaryReply reply) {
        const auto& codec = flutter::StandardMethodCodec::GetInstance();
        auto call = codec.DecodeMethodCall(message, message_size);
        if (!call) {
          reply(nullptr, 0);
          return;
        }
        if (call->method_name() == "beginDrag") {
          // 先回复再拖拽：BeginDrag 会进入 Windows 的模态移动循环，在它
          // 返回前不回复的话，子引擎那侧的 await 会一直挂到用户松手。
          auto encoded = codec.EncodeSuccessEnvelope(nullptr);
          reply(encoded->data(), encoded->size());
          BeginDrag();
          return;
        }
        // 未知方法：回空成功信封，避免 Dart 侧永久挂起。
        auto encoded = codec.EncodeSuccessEnvelope(nullptr);
        reply(encoded->data(), encoded->size());
      });

  // 2) to_sub（主引擎侧 handler）：主窗口 → 子窗口。收主引擎消息，转发给子引擎。
  main_messenger_->SetMessageHandler(
      "cyrene/taskbar_player/to_sub",
      [this](const uint8_t* message, size_t message_size,
             flutter::BinaryReply reply) {
        if (!sub_messenger_ || !hwnd_) {
          reply(nullptr, 0);
          return;
        }
        sub_messenger_->Send(
            "cyrene/taskbar_player/to_sub", message, message_size,
            [reply](const uint8_t* r, size_t rsize) { reply(r, rsize); });
      });

  // 3) to_main（子引擎侧 handler）：子窗口 → 主窗口。收子引擎消息，转发给主引擎。
  sub_messenger_->SetMessageHandler(
      "cyrene/taskbar_player/to_main",
      [this](const uint8_t* message, size_t message_size,
             flutter::BinaryReply reply) {
        if (!main_messenger_) {
          reply(nullptr, 0);
          return;
        }
        main_messenger_->Send(
            "cyrene/taskbar_player/to_main", message, message_size,
            [reply](const uint8_t* r, size_t rsize) { reply(r, rsize); });
      });
}

void TaskbarPlayerWindow::UnregisterChannels() {
  if (main_messenger_) {
    main_messenger_->SetMessageHandler("cyrene/taskbar_player/to_sub", nullptr);
  }
  if (sub_messenger_) {
    sub_messenger_->SetMessageHandler("cyrene/taskbar_player/to_main", nullptr);
    sub_messenger_->SetMessageHandler("cyrene/taskbar_player", nullptr);
  }
}

// ==================== 窗口过程 ====================

LRESULT CALLBACK TaskbarPlayerWindow::WndProc(HWND window, UINT message,
                                              WPARAM wparam,
                                              LPARAM lparam) noexcept {
  TaskbarPlayerWindow* self = reinterpret_cast<TaskbarPlayerWindow*>(
      ::GetWindowLongPtrW(window, GWLP_USERDATA));
  if (self) {
    return self->HandleMessage(window, message, wparam, lparam);
  }
  return ::DefWindowProcW(window, message, wparam, lparam);
}

LRESULT TaskbarPlayerWindow::HandleMessage(HWND window, UINT message,
                                           WPARAM wparam,
                                           LPARAM lparam) noexcept {
  // Explorer 重启：旧 Shell_TrayWnd 已销毁，owner 失效，窗口成了孤儿。
  // 重新挂 owner 并按新任务栏定位。这条消息 id 是运行时注册的，不是常量，
  // 因此只能用 if 而不能进下面的 switch。
  if (taskbar_created_message_ != 0 && message == taskbar_created_message_) {
    AttachToTaskbar();
    Reposition();
    return 0;
  }

  // 先给 Flutter 引擎处理消息的机会（与 flutter_window.cpp 的 MessageHandler 一致）。
  if (controller_) {
    std::optional<LRESULT> result = controller_->HandleTopLevelWindowProc(
        window, message, wparam, lparam);
    if (result) return *result;
  }

  switch (message) {
    case WM_MOUSEACTIVATE:
      // 点播放器不该把焦点从用户正在打字的窗口上抢走，但点击本身要照常
      // 派发给 Flutter（MA_NOACTIVATE 只拒绝激活，不吃掉消息）。
      return MA_NOACTIVATE;

    case WM_WINDOWPOSCHANGING: {
      // 钉在 z-order 顶部：窗口不抢焦点，系统会在别的窗口激活时把它压下去，
      // 拦下每次位置变更强制回到 TOPMOST，才能稳定浮在任务栏之上。
      auto* pos = reinterpret_cast<WINDOWPOS*>(lparam);
      pos->hwndInsertAfter = HWND_TOPMOST;
      pos->flags &= ~SWP_NOZORDER;
      return 0;
    }

    case WM_TIMER:
      if (wparam == kRepositionTimerId) {
        Reposition();
        return 0;
      }
      break;

    case WM_EXITSIZEMOVE:
      // 用户松开鼠标，BeginDrag 起的那次系统拖拽循环到此结束。判定落点：
      // 贴近任务栏就吸附回去，否则定为悬浮。
      OnDragFinished();
      return 0;

    case WM_SETTINGCHANGE:
      // 任务栏自动隐藏、位置、尺寸等变更。
      Reposition();
      return 0;

    case WM_DISPLAYCHANGE:
      // 分辨率/显示器拓扑变化。
      AttachToTaskbar();
      Reposition();
      return 0;

    case WM_DPICHANGED:
      // 跨显示器拖动或系统缩放变更：整条尺寸都要按新 DPI 重算。
      Reposition();
      return 0;

    case WM_SIZE: {
      // 子视图跟随客户区尺寸。
      HWND view = controller_ ? controller_->view()->GetNativeWindow() : nullptr;
      if (view) {
        RECT client{};
        ::GetClientRect(hwnd_, &client);
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
