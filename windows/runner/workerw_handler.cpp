#include "workerw_handler.h"

#include <sstream>
#include <string>

#include "flutter/standard_method_codec.h"

namespace {

// ==================== 字符串 / 诊断辅助 ====================

std::string ToUtf8(const wchar_t* text) {
  if (!text || !*text) return "";
  int len = ::WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0, nullptr,
                                   nullptr);
  if (len <= 1) return "";
  std::string out(static_cast<size_t>(len - 1), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, text, -1, out.data(), len, nullptr,
                         nullptr);
  return out;
}

std::string DescribeWindow(HWND hwnd, int depth, HWND ours) {
  wchar_t cls[256] = {};
  ::GetClassNameW(hwnd, cls, 256);
  wchar_t title[256] = {};
  ::GetWindowTextW(hwnd, title, 256);
  RECT r = {};
  ::GetWindowRect(hwnd, &r);

  std::ostringstream os;
  os << std::string(static_cast<size_t>(depth) * 2, ' ') << "0x" << std::hex
     << reinterpret_cast<uintptr_t>(hwnd) << std::dec << " [" << ToUtf8(cls)
     << "] \"" << ToUtf8(title) << "\" rect=" << r.left << "," << r.top << ","
     << r.right << "," << r.bottom
     << " vis=" << (::IsWindowVisible(hwnd) ? 1 : 0);
  if (ours && hwnd == ours) {
    os << "   <<<< 我们的窗口";
  }
  return os.str();
}

void CollectTree(HWND hwnd, int depth, int max_depth, HWND ours,
                 flutter::EncodableList* out) {
  out->push_back(flutter::EncodableValue(DescribeWindow(hwnd, depth, ours)));
  if (depth >= max_depth) return;
  HWND child = ::GetWindow(hwnd, GW_CHILD);
  while (child) {
    CollectTree(child, depth + 1, max_depth, ours, out);
    child = ::GetWindow(child, GW_HWNDNEXT);
  }
}

// ==================== 桌面图标显隐 ====================

/// 查找桌面图标宿主窗口 SHELLDLL_DefView。
HWND FindShellDefView() {
  HWND progman = ::FindWindowW(L"Progman", nullptr);
  if (progman) {
    HWND defview =
        ::FindWindowExW(progman, nullptr, L"SHELLDLL_DefView", nullptr);
    if (defview) return defview;
  }

  HWND found = nullptr;
  ::EnumWindows(
      [](HWND top, LPARAM lparam) -> BOOL {
        HWND defview =
            ::FindWindowExW(top, nullptr, L"SHELLDLL_DefView", nullptr);
        if (defview) {
          *reinterpret_cast<HWND*>(lparam) = defview;
          return FALSE;  // 找到即停
        }
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&found));
  return found;
}

/// 隐藏 / 显示桌面图标。全局副作用：影响整个系统桌面。
/// 调用方必须在关闭桌面播放器时恢复；进程被强杀则用户需手动右键桌面恢复。
bool SetDesktopIconsVisible(bool visible) {
  HWND defview = FindShellDefView();
  if (!defview) return false;
  ::ShowWindow(defview, visible ? SW_SHOW : SW_HIDE);
  return true;
}

}  // namespace

// ==================== WorkerWHandler 类实现 ====================

WorkerWHandler::WorkerWHandler(flutter::BinaryMessenger* messenger,
                               HWND window)
    : messenger_(messenger),
      window_(window),
      channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, "cyrene/workerw",
          &flutter::StandardMethodCodec::GetInstance())) {}

WorkerWHandler::~WorkerWHandler() {
  // 兜底：进程正常退出时若桌面播放器仍开着，closeWindow 不一定会被调用。
  // 桌面图标是全局副作用，绝不能留在隐藏状态。
  SetDesktopIconsVisible(true);
}

void WorkerWHandler::RegisterChannels() {
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        OnMethodCall(call, std::move(result));
      });
}

void WorkerWHandler::OnMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "createLyricsWindow") {
    HandleCreateLyricsWindow(std::move(result));
    return;
  }
  if (method == "closeWindow") {
    HandleCloseWindow(std::move(result));
    return;
  }
  if (method == "dumpDesktopTree") {
    HandleDumpDesktopTree(std::move(result));
    return;
  }
  result->NotImplemented();
}

void WorkerWHandler::HandleCreateLyricsWindow(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  // 已存在则先销毁（幂等重启）。
  if (lyrics_window_) {
    lyrics_window_.reset();
  }

  // 工作区尺寸（排除任务栏）。
  RECT work_area{};
  if (!::SystemParametersInfoW(SPI_GETWORKAREA, 0, &work_area, 0)) {
    work_area = {0, 0, ::GetSystemMetrics(SM_CXSCREEN),
                 ::GetSystemMetrics(SM_CYSCREEN)};
  }
  int screen_w = work_area.right - work_area.left;
  int screen_h = work_area.bottom - work_area.top;

  lyrics_window_ =
      DesktopLyricsWindow::Create(messenger_, screen_w, screen_h);
  if (!lyrics_window_) {
    result->Error("create_failed", "Failed to create desktop lyrics window");
    return;
  }

  bool icons_hidden = SetDesktopIconsVisible(false);

  flutter::EncodableMap response;
  response[flutter::EncodableValue("screenWidth")] =
      flutter::EncodableValue(static_cast<int64_t>(screen_w));
  response[flutter::EncodableValue("screenHeight")] =
      flutter::EncodableValue(static_cast<int64_t>(screen_h));
  response[flutter::EncodableValue("iconsHidden")] =
      flutter::EncodableValue(icons_hidden);
  result->Success(flutter::EncodableValue(response));
}

void WorkerWHandler::HandleCloseWindow(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  // 无论是否还有窗口都先恢复桌面图标：全局副作用，宁可多恢复一次。
  SetDesktopIconsVisible(true);
  lyrics_window_.reset();
  result->Success();
}

void WorkerWHandler::HandleDumpDesktopTree(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  HWND ours = lyrics_window_ ? lyrics_window_->hwnd() : nullptr;
  flutter::EncodableList lines;

  {
    std::ostringstream os;
    os << "our_hwnd=0x" << std::hex << reinterpret_cast<uintptr_t>(ours);
    if (ours) {
      HWND parent = ::GetParent(ours);
      os << " parent=0x" << reinterpret_cast<uintptr_t>(parent) << std::dec;
      wchar_t pcls[256] = {};
      if (parent) ::GetClassNameW(parent, pcls, 256);
      os << " [" << ToUtf8(pcls) << "]"
         << " style=0x" << std::hex << ::GetWindowLongPtrW(ours, GWL_STYLE)
         << " ex=0x" << ::GetWindowLongPtrW(ours, GWL_EXSTYLE) << std::dec
         << " vis=" << (::IsWindowVisible(ours) ? 1 : 0);
    }
    lines.push_back(flutter::EncodableValue(os.str()));
  }

  lines.push_back(flutter::EncodableValue("--- 顶层 Progman / WorkerW ---"));
  struct Ctx {
    flutter::EncodableList* out;
    HWND ours;
  };
  Ctx ctx{&lines, ours};
  ::EnumWindows(
      [](HWND top, LPARAM lp) -> BOOL {
        auto* c = reinterpret_cast<Ctx*>(lp);
        wchar_t cls[256] = {};
        ::GetClassNameW(top, cls, 256);
        if (::wcscmp(cls, L"Progman") == 0 || ::wcscmp(cls, L"WorkerW") == 0) {
          CollectTree(top, 0, 2, c->ours, c->out);
        }
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&ctx));

  result->Success(flutter::EncodableValue(lines));
}
