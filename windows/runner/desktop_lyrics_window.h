#ifndef RUNNER_DESKTOP_LYRICS_WINDOW_H_
#define RUNNER_DESKTOP_LYRICS_WINDOW_H_

#include <flutter/binary_messenger.h>
#include <flutter/flutter_view_controller.h>

#include <memory>
#include <vector>

#include <windows.h>

/// 桌面歌词覆盖层窗口（自托管第二个 Flutter 引擎）。
///
/// 取代 desktop_multi_window 插件：runner 直接创建顶层 WS_POPUP 窗口并在其中
/// 跑一个独立的 FlutterViewController（entrypoint args = "wallpaper-player"，
/// 对应 main.dart 的子窗口入口分支）。窗口被配置为：
/// - 全屏铺满工作区（排除任务栏）、置底 z-order、不进任务栏/Alt+Tab；
/// - per-pixel alpha（Flutter 透明像素透出壁纸）；
/// - 默认整窗鼠标穿透，命中矩形内才接收点击（设置面板）；
/// - 命中区域内允许激活，否则 MA_NOACTIVATE，避免抢焦点。
///
/// 命中测试的关键点：鼠标先打到 Flutter 视图子窗口（engine 拥有其 WndProc），
/// 因此除顶层 WndProc 外，还要对子窗口做一次子类化，在 WM_NCHITTEST 里按
/// 命中矩形决定 HTCLIENT/HTTRANSPARENT。两处都查同一份 g_hit_rects。
///
/// 通道设计（消灭插件的三跳中转）：
/// - `cyrene/desktop_lyrics`（子引擎侧）：setHitRects 直接写命中矩形，零中转，
///   且由 C++ 在子引擎启动时同步注册，早于子引擎 Dart 运行——这是修复「设置按钮
///   点不动」的结构性保证。
/// - `cyrene/desktop_lyrics/to_sub`：主→子，主窗口推送播放状态（syncState/
///   syncPosition）。
/// - `cyrene/desktop_lyrics/to_main`：子→主，子窗口回传命令（command）与索要状态
///   （requestState）。
/// 后两者走原始字节中继：一侧 SetMessageHandler 收到消息后用对端 messenger 的
/// Send 转发，reply 原样回传。两侧 Dart 全用标准 MethodChannel，不再依赖任何插件。
class DesktopLyricsWindow {
 public:
  /// 创建并显示覆盖层窗口。|main_messenger| 为主引擎的 messenger，用于挂
  /// to_sub 中继。失败返回 nullptr。
  static std::unique_ptr<DesktopLyricsWindow> Create(
      flutter::BinaryMessenger* main_messenger,
      int screen_w,
      int screen_h);

  ~DesktopLyricsWindow();

  DesktopLyricsWindow(const DesktopLyricsWindow&) = delete;
  DesktopLyricsWindow& operator=(const DesktopLyricsWindow&) = delete;

  HWND hwnd() const { return hwnd_; }

  // 顶层窗口过程：注册窗口类时作为 lpfnWndProc，必须可访问。
  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam) noexcept;

 private:
  DesktopLyricsWindow(flutter::BinaryMessenger* main_messenger,
                      HWND hwnd,
                      std::unique_ptr<flutter::FlutterViewController> controller);

  LRESULT HandleMessage(HWND window, UINT message, WPARAM wparam,
                        LPARAM lparam) noexcept;

  static LRESULT CALLBACK SubViewWndProc(HWND window, UINT message,
                                         WPARAM wparam, LPARAM lparam) noexcept;

  void RegisterChannels();
  void UnregisterChannels();

  RECT GetClientArea() const;

  flutter::BinaryMessenger* main_messenger_ = nullptr;  // 主引擎 messenger（非所有）
  flutter::BinaryMessenger* sub_messenger_ = nullptr;   // 子引擎 messenger（非所有）
  HWND hwnd_ = nullptr;
  std::unique_ptr<flutter::FlutterViewController> controller_;
  WNDPROC sub_view_original_proc_ = nullptr;
};

#endif  // RUNNER_DESKTOP_LYRICS_WINDOW_H_
