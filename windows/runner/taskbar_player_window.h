#ifndef RUNNER_TASKBAR_PLAYER_WINDOW_H_
#define RUNNER_TASKBAR_PLAYER_WINDOW_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>

#include <windows.h>

/// 任务栏播放器窗口（自托管第三个 Flutter 引擎）。
///
/// 与 DesktopLyricsWindow 同一套路子：runner 直接创建顶层 WS_POPUP 窗口并在
/// 其中跑一个独立的 FlutterViewController（entrypoint args = "taskbar-player"，
/// 对应 main.dart 的子窗口入口分支）。
///
/// 与桌面歌词的关键差异：
/// - z-order 相反：歌词钉在 HWND_BOTTOM（壁纸层），这里钉在 HWND_TOPMOST
///   并把 owner 设为 Shell_TrayWnd，使窗口浮在任务栏之上；
/// - 命中测试相反：歌词默认整窗穿透、命中矩形内才可点，这里整窗可交互
///   （本来就只有播放器那一小条），因此不需要 setHitRects 那套机制；
/// - 位置是算出来的：扫描任务栏上已被占用的横向区间，落在最宽的空白处。
///
/// 关于「贴合」的实现（重要）：**没有** SetParent 到 Shell_TrayWnd，也没有用
/// AppBar（SHAppBarMessage/ABM_*）。真嵌入 Explorer 的窗口树既脆弱又会被
/// Win11 的 XAML Islands 架构打断。这里只是把 owner 设为任务栏
/// （SetWindowLongPtrW + GWLP_HWNDPARENT），窗口仍是独立顶层弹出窗口，
/// 借 owner 关系跟随任务栏的显示/隐藏与层级——纯视觉贴合，零侵入。
///
/// 通道设计（复用桌面歌词那套中继，换一组通道名）：
/// - `cyrene/taskbar_player/to_sub`：主→子，主窗口推送播放状态；
/// - `cyrene/taskbar_player/to_main`：子→主，子窗口回传播放控制命令。
/// 两者走原始字节中继：一侧 SetMessageHandler 收到消息后用对端 messenger 的
/// Send 转发，reply 原样回传。两侧 Dart 全用标准 MethodChannel。
class TaskbarPlayerWindow {
 public:
  /// 窗口在任务栏空白区里的水平对齐方式。
  enum class Alignment { kLeft, kCenter, kRight };

  /// 窗口形态。
  /// - kPinned：固定在任务栏空白区，位置由空白扫描算出，随任务栏变化跟进；
  /// - kFloating：被用户拖出任务栏，自由悬浮，位置由用户决定。
  enum class Mode { kPinned, kFloating };

  static Alignment ParseAlignment(const std::string& value);
  static Mode ParseMode(const std::string& value);

  /// 创建并显示任务栏播放器窗口。|main_messenger| 为主引擎的 messenger，
  /// 用于挂 to_sub 中继与形态变更回调。
  ///
  /// |mode| 为 kFloating 时窗口出生在 (|floating_x|, |floating_y|)（物理像素）；
  /// 为 kPinned 时忽略这两个参数，位置由空白扫描算出。失败返回 nullptr。
  static std::unique_ptr<TaskbarPlayerWindow> Create(
      flutter::BinaryMessenger* main_messenger,
      Alignment alignment,
      Mode mode,
      int floating_x,
      int floating_y);

  ~TaskbarPlayerWindow();

  TaskbarPlayerWindow(const TaskbarPlayerWindow&) = delete;
  TaskbarPlayerWindow& operator=(const TaskbarPlayerWindow&) = delete;

  HWND hwnd() const { return hwnd_; }
  Mode mode() const { return mode_; }

  /// 改变对齐方式并立即重新定位。仅在 kPinned 形态下有视觉效果。
  void SetAlignment(Alignment alignment);

  /// 按当前任务栏几何重新计算位置与尺寸。任务栏尺寸/DPI/显示器变化，
  /// 以及 Explorer 重启后都要调它。kFloating 形态下只跟随尺寸、不改位置。
  void Reposition();

  /// 把窗口交给 Windows 自己的拖拽循环（ReleaseCapture +
  /// WM_NCLBUTTONDOWN/HTCAPTION）。由 Dart 侧在 onPanStart 时调用一次即可，
  /// 拖拽过程中不需要任何 IPC——这是「跟手」的关键。
  void BeginDrag();

  // 注册窗口类时作为 lpfnWndProc，必须可访问。
  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam) noexcept;

 private:
  TaskbarPlayerWindow(
      flutter::BinaryMessenger* main_messenger,
      HWND hwnd,
      std::unique_ptr<flutter::FlutterViewController> controller,
      Alignment alignment,
      Mode mode);

  LRESULT HandleMessage(HWND window, UINT message, WPARAM wparam,
                        LPARAM lparam) noexcept;

  void RegisterChannels();
  void UnregisterChannels();

  /// 把 owner 设为 Shell_TrayWnd，使窗口跟随任务栏的显示/隐藏与层级。
  void AttachToTaskbar();

  /// 拖拽结束后判定落点：贴近任务栏则吸附回 kPinned，否则转为 kFloating。
  void OnDragFinished();

  /// 切换形态。会启停重定位定时器，并把新形态回报给主窗口（用于持久化）。
  void SetMode(Mode mode);

  /// 把形态与当前位置回报给主窗口 Dart 侧（`onModeChanged`）。
  void NotifyModeChanged();

  flutter::BinaryMessenger* main_messenger_ = nullptr;  // 主引擎 messenger（非所有）
  flutter::BinaryMessenger* sub_messenger_ = nullptr;   // 子引擎 messenger（非所有）
  HWND hwnd_ = nullptr;
  std::unique_ptr<flutter::FlutterViewController> controller_;
  Alignment alignment_ = Alignment::kCenter;
  Mode mode_ = Mode::kPinned;

  /// 主引擎侧的方法通道，用于把形态变更回报给 Dart（持久化用）。
  /// 与 TaskbarPlayerHandler 用的是同一个通道名，方向相反（原生→Dart）。
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      main_channel_;

  /// Explorer 重启后广播的消息 id（RegisterWindowMessageW("TaskbarCreated")）。
  /// 收到后要重新挂 owner 并重新定位，否则窗口会变成孤儿悬在原处。
  UINT taskbar_created_message_ = 0;
};

#endif  // RUNNER_TASKBAR_PLAYER_WINDOW_H_
