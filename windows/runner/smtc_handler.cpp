#include "smtc_handler.h"

#include <flutter/standard_codec_serializer.h>
#include <flutter/event_stream_handler_functions.h>

#include <chrono>
#include <utility>
#include <vector>

// C++/WinRT 头文件在 /W4 /WX 下可能触发 SDK 自身告警（如 4100/4458），
// 用 pragma 压掉，避免污染应用构建。
#if defined(_MSC_VER)
#pragma warning(push)
#pragma warning(disable : 4100 4189 4324 4458 4702)
#endif
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>
#if defined(_MSC_VER)
#pragma warning(pop)
#endif

// 桌面（Win32）应用通过此 interop 接口按 HWND 获取 SMTC。
#include <systemmediatransportcontrolsinterop.h>

using namespace winrt::Windows::Media;

namespace {

// ==================== EncodableValue 解析 ====================

int64_t AsInt64(const flutter::EncodableValue& value) {
  if (const auto* i32 = std::get_if<int32_t>(&value)) {
    return *i32;
  }
  if (const auto* i64 = std::get_if<int64_t>(&value)) {
    return *i64;
  }
  return 0;
}

bool AsBool(const flutter::EncodableValue& value) {
  if (const auto* boolean = std::get_if<bool>(&value)) {
    return *boolean;
  }
  return false;
}

std::string AsString(const flutter::EncodableValue& value) {
  if (const auto* text = std::get_if<std::string>(&value)) {
    return *text;
  }
  return "";
}

// 从 EncodableMap 取键值；缺失时返回 nullptr，由调用方决定默认值。
const flutter::EncodableValue* MapValue(const flutter::EncodableMap& map,
                                        const std::string& key) {
  const auto it = map.find(flutter::EncodableValue(key));
  return it != map.end() ? &it->second : nullptr;
}

void LogSmtc(const char* message) {
  ::OutputDebugStringA("[SMTC] ");
  ::OutputDebugStringA(message);
  ::OutputDebugStringA("\n");
}

// ==================== SMTC 辅助 ====================

MediaPlaybackAutoRepeatMode ToAutoRepeatMode(const std::string& mode) {
  if (mode == "one") {
    return MediaPlaybackAutoRepeatMode::Track;
  }
  if (mode == "all" || mode == "shuffle") {
    return MediaPlaybackAutoRepeatMode::List;
  }
  return MediaPlaybackAutoRepeatMode::None;
}

std::string RepeatModeName(MediaPlaybackAutoRepeatMode mode) {
  switch (mode) {
    case MediaPlaybackAutoRepeatMode::Track:
      return "one";
    case MediaPlaybackAutoRepeatMode::List:
      return "all";
    default:
      return "off";
  }
}

// 跨线程传递封面内存流的载荷。
//
// 不能直接 make_unique<InMemoryRandomAccessStream>()：C++/WinRT 运行对象
// 从 IUnknown 继承了已删除的 operator new（C2280），禁止堆分配。包进一个
// 普通 struct，由 struct 提供 operator new，成员流在析构时自然释放 COM 引用。
struct ThumbnailMessagePayload {
  winrt::Windows::Storage::Streams::InMemoryRandomAccessStream stream;
};

// 在后台把封面字节写入内存流，完成后把载荷指针 PostMessage 给主窗口
// （kWmSetThumbnail），由 UI 线程设置 SMTC 缩略图。
//
// 为什么不用阻塞等待：C++/WinRT 的 get()/wait() 在 STA（UI）线程上会断言
// "!is_sta_thread()"（阻塞 STA 会死锁），所以写流必须用 co_await 协程。
// 为什么必须回 UI 线程：SMTC 通过 GetForWindow 取得，绑定窗口线程，从后台
// 线程访问会抛 RPC_E_WRONG_THREAD。
winrt::fire_and_forget SetThumbnailAsync(HWND window,
                                         std::vector<uint8_t> bytes,
                                         uint64_t seq) {
  using namespace winrt::Windows::Storage::Streams;
  try {
    auto payload = std::make_unique<ThumbnailMessagePayload>();
    DataWriter writer(payload->stream);
    writer.WriteBytes({bytes.data(), static_cast<uint32_t>(bytes.size())});
    co_await writer.StoreAsync();
    writer.DetachStream();

    // 所有权转移给消息：无论 OnSetThumbnailMessage 是否应用都会释放。
    ThumbnailMessagePayload* raw = payload.release();
    if (!::PostMessageW(window, SmtcHandler::kWmSetThumbnail,
                        static_cast<WPARAM>(seq),
                        reinterpret_cast<LPARAM>(raw))) {
      delete raw;  // 窗口已销毁等导致投递失败，避免泄漏。
    }
  } catch (...) {
    // 封面失败不影响其余 SMTC 功能。
  }
}

}  // namespace

SmtcHandler::SmtcHandler(flutter::BinaryMessenger* messenger, HWND window)
    : messenger_(messenger), window_(window) {}

SmtcHandler::~SmtcHandler() {
  if (smtc_ && initialized_) {
    try {
      if (button_token_) {
        smtc_.ButtonPressed(button_token_);
      }
      if (position_token_) {
        smtc_.PlaybackPositionChangeRequested(position_token_);
      }
      if (repeat_token_) {
        smtc_.AutoRepeatModeChangeRequested(repeat_token_);
      }
    } catch (...) {
      // 析构阶段不做错误处理。
    }
  }
}

void SmtcHandler::RegisterChannels() {
  method_channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger_, "cyrene.music/smtc",
      &flutter::StandardMethodCodec::GetInstance());
  method_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        OnMethodCall(call, std::move(result));
      });

  event_channel_ = std::make_unique<flutter::EventChannel<EncodableValue>>(
      messenger_, "cyrene.music/smtc/events",
      &flutter::StandardMethodCodec::GetInstance());
  event_channel_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [this](const EncodableValue* /*arguments*/,
                 std::unique_ptr<flutter::EventSink<EncodableValue>>&& events) {
            std::lock_guard<std::mutex> lock(sink_mutex_);
            event_sink_ = std::move(events);
            return nullptr;
          },
          [this](const EncodableValue* /*arguments*/) {
            std::lock_guard<std::mutex> lock(sink_mutex_);
            event_sink_.reset();
            return nullptr;
          }));
}

void SmtcHandler::OnMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "init") {
    HandleInit(std::move(result));
  } else if (method == "update") {
    if (const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments())) {
      HandleUpdate(*args);
    }
    result->Success();
  } else if (method == "updatePosition") {
    if (const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments())) {
      if (const auto* position = MapValue(*args, "positionMs")) {
        HandleUpdatePosition(AsInt64(*position));
      }
    }
    result->Success();
  } else if (method == "clear") {
    HandleClear();
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void SmtcHandler::HandleInit(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  try {
    if (!initialized_) {
      // 桌面应用没有 UWP CoreWindow，须用 interop 按 HWND 获取 SMTC；
      // 直接 GetForCurrentView() 在 Win32 宿主下会抛 hresult_error。
      auto interop = winrt::get_activation_factory<
          SystemMediaTransportControls,
          ISystemMediaTransportControlsInterop>();
      winrt::check_hresult(interop->GetForWindow(
          window_, winrt::guid_of<SystemMediaTransportControls>(),
          winrt::put_abi(smtc_)));
      smtc_.IsEnabled(true);
      smtc_.IsPlayEnabled(true);
      smtc_.IsPauseEnabled(true);
      smtc_.IsNextEnabled(true);
      smtc_.IsPreviousEnabled(true);
      smtc_.AutoRepeatMode(MediaPlaybackAutoRepeatMode::None);

      button_token_ =
          smtc_.ButtonPressed({this, &SmtcHandler::OnButtonPressed});
      position_token_ = smtc_.PlaybackPositionChangeRequested(
          {this, &SmtcHandler::OnPositionChangeRequested});
      repeat_token_ = smtc_.AutoRepeatModeChangeRequested(
          {this, &SmtcHandler::OnAutoRepeatModeChangeRequested});

      auto updater = smtc_.DisplayUpdater();
      updater.Type(MediaPlaybackType::Music);
      // 媒体的“所属应用”标识（与进程 AUMID 互补，Chromium/Electron 亦如此
      // 设置）。设置失败不影响其余 SMTC 功能。
      try {
        updater.AppMediaId(winrt::hstring(L"CyreneMusic"));
      } catch (...) {
      }
      updater.Update();
      initialized_ = true;
    }
    result->Success(flutter::EncodableValue(true));
  } catch (const winrt::hresult_error& error) {
    // Windows 10 1803 之前 / 无窗口上下文时 GetForCurrentView 会失败。
    LogSmtc(winrt::to_string(error.message()).c_str());
    result->Success(flutter::EncodableValue(false));
  } catch (...) {
    result->Success(flutter::EncodableValue(false));
  }
}

void SmtcHandler::HandleUpdate(const flutter::EncodableMap& args) {
  if (!initialized_ || !smtc_) {
    return;
  }
  try {
    const auto* title_value = MapValue(args, "title");
    const auto* artist_value = MapValue(args, "artist");
    const auto* album_value = MapValue(args, "album");
    const std::string title = title_value ? AsString(*title_value) : "";
    const std::string artist = artist_value ? AsString(*artist_value) : "";
    const std::string album = album_value ? AsString(*album_value) : "";

    auto updater = smtc_.DisplayUpdater();
    auto music = updater.MusicProperties();
    music.Title(winrt::to_hstring(title));
    music.Artist(winrt::to_hstring(artist));
    music.AlbumTitle(winrt::to_hstring(album));
    updater.Update();

    // 播放状态
    const auto* playing_value = MapValue(args, "isPlaying");
    const bool playing = playing_value ? AsBool(*playing_value) : false;
    smtc_.PlaybackStatus(playing ? MediaPlaybackStatus::Playing
                                 : MediaPlaybackStatus::Paused);

    // 时间轴（进度条 + 拖动 seek）
    const auto* position_value = MapValue(args, "positionMs");
    const auto* duration_value = MapValue(args, "durationMs");
    const int64_t position_ms = position_value ? AsInt64(*position_value) : 0;
    const int64_t duration_ms = duration_value ? AsInt64(*duration_value) : 0;
    last_duration_ms_ = duration_ms;
    SystemMediaTransportControlsTimelineProperties timeline;
    timeline.StartTime(std::chrono::milliseconds(0));
    timeline.Position(std::chrono::milliseconds(position_ms));
    timeline.MinSeekTime(std::chrono::milliseconds(0));
    timeline.MaxSeekTime(std::chrono::milliseconds(duration_ms));
    timeline.EndTime(std::chrono::milliseconds(duration_ms));
    smtc_.UpdateTimelineProperties(timeline);

    // 循环模式（同时映射到 AutoRepeatMode 与 Shuffle）
    const auto* repeat_value = MapValue(args, "repeatMode");
    const std::string repeat = repeat_value ? AsString(*repeat_value) : "";
    smtc_.AutoRepeatMode(ToAutoRepeatMode(repeat));
    smtc_.ShuffleEnabled(repeat == "shuffle");

    // 封面（路径变化时才重新加载）
    const auto* art_value = MapValue(args, "artPath");
    const std::string art_path = art_value ? AsString(*art_value) : "";
    if (!art_path.empty() && art_path != last_art_path_) {
      last_art_path_ = art_path;
      UpdateThumbnail(art_path);
    }
  } catch (const winrt::hresult_error& error) {
    LogSmtc(winrt::to_string(error.message()).c_str());
  } catch (...) {
    // 任一元数据同步失败都不应影响播放器。
  }
}

void SmtcHandler::HandleUpdatePosition(int64_t position_ms) {
  if (!initialized_ || !smtc_) {
    return;
  }
  try {
    // UpdateTimelineProperties 整体替换，须用缓存时长补全 End/MaxSeek，
    // 否则进度条会因 EndTime 归零而错乱。
    SystemMediaTransportControlsTimelineProperties timeline;
    timeline.StartTime(std::chrono::milliseconds(0));
    timeline.Position(std::chrono::milliseconds(position_ms));
    timeline.MinSeekTime(std::chrono::milliseconds(0));
    timeline.MaxSeekTime(std::chrono::milliseconds(last_duration_ms_));
    timeline.EndTime(std::chrono::milliseconds(last_duration_ms_));
    smtc_.UpdateTimelineProperties(timeline);
  } catch (...) {
  }
}

void SmtcHandler::HandleClear() {
  if (!initialized_ || !smtc_) {
    return;
  }
  try {
    smtc_.DisplayUpdater().ClearAll();
    smtc_.PlaybackStatus(MediaPlaybackStatus::Closed);
    last_art_path_.clear();
    last_duration_ms_ = 0;
  } catch (...) {
  }
}

void SmtcHandler::SendEvent(const std::string& event, int64_t position_ms,
                            const std::string& mode) {
  std::lock_guard<std::mutex> lock(sink_mutex_);
  if (!event_sink_) {
    return;
  }
  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("event")] = flutter::EncodableValue(event);
  if (event == "seek") {
    payload[flutter::EncodableValue("positionMs")] =
        flutter::EncodableValue(position_ms);
  }
  if (event == "setRepeatMode") {
    payload[flutter::EncodableValue("mode")] = flutter::EncodableValue(mode);
  }
  event_sink_->Success(flutter::EncodableValue(std::move(payload)));
}

void SmtcHandler::OnButtonPressed(
    SystemMediaTransportControls const& /*sender*/,
    SystemMediaTransportControlsButtonPressedEventArgs const& args) {
  switch (args.Button()) {
    case SystemMediaTransportControlsButton::Play:
      SendEvent("play");
      break;
    case SystemMediaTransportControlsButton::Pause:
      SendEvent("pause");
      break;
    case SystemMediaTransportControlsButton::Next:
      SendEvent("next");
      break;
    case SystemMediaTransportControlsButton::Previous:
      SendEvent("previous");
      break;
    case SystemMediaTransportControlsButton::Stop:
      SendEvent("stop");
      break;
    default:
      break;
  }
}

void SmtcHandler::OnPositionChangeRequested(
    SystemMediaTransportControls const& /*sender*/,
    PlaybackPositionChangeRequestedEventArgs const&
        args) {
  const auto position = args.RequestedPlaybackPosition();
  const int64_t position_ms =
      std::chrono::duration_cast<std::chrono::milliseconds>(position).count();
  SendEvent("seek", position_ms);
}

void SmtcHandler::OnAutoRepeatModeChangeRequested(
    SystemMediaTransportControls const& /*sender*/,
    AutoRepeatModeChangeRequestedEventArgs const&
        args) {
  SendEvent("setRepeatMode",
            /*position_ms=*/0,
            RepeatModeName(args.RequestedAutoRepeatMode()));
}

void SmtcHandler::UpdateThumbnail(const std::string& path) {
  // SMTC（通过 GetForWindow 取得）绑定在 UI 线程上，从后台线程访问会抛
  // RPC_E_WRONG_THREAD（0x8001010E）。早期版本用 fire_and_forget 协程
  // co_await StorageFile::GetFileFromPathAsync 读图，C++/WinRT 默认会在
  // 线程池线程恢复协程，导致缩略图更新静默失败（catch (...) 吞掉异常），
  // 封面不显示。
  //
  // 现在：在 UI 线程同步读取封面文件（网络缓存图通常 < 1MB，耗时毫秒级），
  // 之后交给协程 SetThumbnailAsync 异步写内存流，完成后 PostMessage 回 UI
  // 线程设置缩略图。不能在 UI 线程对 StoreAsync().get() 阻塞等待——C++/WinRT
  // 断言 "!is_sta_thread()"，因为阻塞 STA 会死锁。
  const auto wide_path = winrt::to_hstring(path);
  HANDLE file = ::CreateFileW(wide_path.c_str(), GENERIC_READ,
                              FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                              FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }
  LARGE_INTEGER size{};
  if (!::GetFileSizeEx(file, &size) || size.QuadPart <= 0 ||
      size.QuadPart > 8 * 1024 * 1024) {
    ::CloseHandle(file);
    return;  // 空文件或超大图直接跳过。
  }
  std::vector<uint8_t> bytes(static_cast<size_t>(size.QuadPart));
  DWORD bytes_read = 0;
  const BOOL read_ok = ::ReadFile(file, bytes.data(),
                                  static_cast<DWORD>(bytes.size()),
                                  &bytes_read, nullptr);
  ::CloseHandle(file);
  if (!read_ok || bytes_read != bytes.size()) {
    return;
  }

  SetThumbnailAsync(window_, std::move(bytes), ++thumbnail_seq_);
}

void SmtcHandler::OnSetThumbnailMessage(WPARAM wParam, LPARAM lParam) {
  using namespace winrt::Windows::Storage::Streams;
  ThumbnailMessagePayload* payload =
      reinterpret_cast<ThumbnailMessagePayload*>(lParam);
  // 序号不匹配说明已有更新的封面请求，丢弃旧曲封面。
  if (payload && initialized_ && smtc_ &&
      static_cast<uint64_t>(wParam) == thumbnail_seq_) {
    try {
      auto updater = smtc_.DisplayUpdater();
      updater.Thumbnail(
          RandomAccessStreamReference::CreateFromStream(payload->stream));
      updater.Update();
    } catch (const winrt::hresult_error& error) {
      LogSmtc(winrt::to_string(error.message()).c_str());
    } catch (...) {
      // 封面失败不影响其余 SMTC 功能。
    }
  }
  delete payload;
}

void SmtcHandler::ReleaseThumbnailMessage(LPARAM lParam) {
  delete reinterpret_cast<ThumbnailMessagePayload*>(lParam);
}
