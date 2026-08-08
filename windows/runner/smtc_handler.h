#ifndef RUNNER_SMTC_HANDLER_H_
#define RUNNER_SMTC_HANDLER_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <mutex>
#include <string>

#include <windows.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>

// Windows 系统媒体传输控件（SMTC）桥接。
//
// Dart 侧 SmtcService（lib/infrastructure/media_notification/smtc_service.dart）
// 通过 MethodChannel "cyrene.music/smtc" 下行状态（init/update/updatePosition/
// clear），原生端通过 EventChannel "cyrene.music/smtc/events" 上行按钮事件
// （play/pause/playPause/next/previous/seek/stop/setRepeatMode）。
//
// 依赖 C++/WinRT（Windows SDK 自带头文件，无需新增 pub 依赖）；必须在
// 应用 UI 线程创建与调用（GetForWindow 要求当前线程有窗口上下文，Flutter 的
// platform thread 即主消息循环线程，满足该要求）。
class SmtcHandler {
 public:
  // 封面就绪的通知消息：后台协程把填好字节的 InMemoryRandomAccessStream*
  // PostMessage 给主窗口，UI 线程在 MessageHandler 中调用 OnSetThumbnailMessage。
  static constexpr UINT kWmSetThumbnail = WM_APP + 1;

  // |messenger| 由 Flutter 引擎持有，生命周期长于本对象。|window| 为宿主顶层
  // 窗口句柄：桌面（Win32）应用没有 UWP CoreWindow，必须通过
  // ISystemMediaTransportControlsInterop::GetForWindow 获取 SMTC。
  SmtcHandler(flutter::BinaryMessenger* messenger, HWND window);
  ~SmtcHandler();

  SmtcHandler(const SmtcHandler&) = delete;
  SmtcHandler& operator=(const SmtcHandler&) = delete;

  // 注册 MethodChannel 与 EventChannel（须在 UI 线程调用一次）。
  void RegisterChannels();

  // 在 UI 线程处理 kWmSetThumbnail：把协程准备好的内存流设为缩略图。
  // |wParam| 为封面请求序号（仅当它仍是最新请求时应用）；|lParam| 为
  // InMemoryRandomAccessStream*，所有权转移给本函数（无论是否应用都释放）。
  void OnSetThumbnailMessage(WPARAM wParam, LPARAM lParam);

  // 释放封面消息里的内存流。消息到达时 handler 可能已被销毁（窗口关闭中），
  // 调用方需在 handler 为空时走此静态路径，避免泄漏流。
  static void ReleaseThumbnailMessage(LPARAM lParam);

 private:
  using EncodableValue = flutter::EncodableValue;

  void OnMethodCall(
      const flutter::MethodCall<EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);

  void HandleInit(std::unique_ptr<flutter::MethodResult<EncodableValue>> result);
  void HandleUpdate(const flutter::EncodableMap& args);
  void HandleUpdatePosition(int64_t position_ms);
  void HandleClear();

  // 向 Dart 侧推送一条事件（线程安全，可在任意线程调用）。
  void SendEvent(const std::string& event, int64_t position_ms = 0,
                 const std::string& mode = "");

  // SMTC 按钮事件（原生 → Dart）。
  void OnButtonPressed(
      winrt::Windows::Media::SystemMediaTransportControls const& sender,
      winrt::Windows::Media::SystemMediaTransportControlsButtonPressedEventArgs
          const& args);
  void OnPositionChangeRequested(
      winrt::Windows::Media::SystemMediaTransportControls const& sender,
      winrt::Windows::Media::PlaybackPositionChangeRequestedEventArgs
          const& args);
  void OnAutoRepeatModeChangeRequested(
      winrt::Windows::Media::SystemMediaTransportControls const& sender,
      winrt::Windows::Media::AutoRepeatModeChangeRequestedEventArgs
          const& args);

  // 在 UI 线程读封面文件字节，交给协程 SetThumbnailAsync 异步写内存流，
  // 完成后 PostMessage 回 UI 线程触发 OnSetThumbnailMessage。
  void UpdateThumbnail(const std::string& path);

  flutter::BinaryMessenger* messenger_;
  HWND window_;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> method_channel_;
  std::unique_ptr<flutter::EventChannel<EncodableValue>> event_channel_;
  std::mutex sink_mutex_;
  std::unique_ptr<flutter::EventSink<EncodableValue>> event_sink_;

  winrt::Windows::Media::SystemMediaTransportControls smtc_{nullptr};
  bool initialized_ = false;
  winrt::event_token button_token_{};
  winrt::event_token position_token_{};
  winrt::event_token repeat_token_{};

  // 封面请求序号，仅 UI 线程访问；用于丢弃过期封面消息（旧曲封面后到）。
  uint64_t thumbnail_seq_ = 0;

  // 最近一次同步的封面路径（仅在变化时重新加载缩略图）。
  std::string last_art_path_;

  // 最近一次已知曲目时长；高频 updatePosition 时用于重建完整时间轴
  // （UpdateTimelineProperties 是整体替换，缺 EndTime 会使进度条错乱）。
  int64_t last_duration_ms_ = 0;
};

#endif  // RUNNER_SMTC_HANDLER_H_
