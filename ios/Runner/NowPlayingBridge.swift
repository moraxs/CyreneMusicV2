import AVFoundation
import Flutter
import MediaPlayer
import UIKit

/// iOS 后台播放 + Now Playing 媒体卡片原生桥。
///
/// 为 Flutter 端（`IosNowPlayingService`）提供 MethodChannel
/// `cyrene.music/now_playing`，职责：
/// - 激活 `AVAudioSession` `.playback` 类别（独占音频，锁屏/后台继续出声），
///   后台播放由 Info.plist 的 `UIBackgroundModes = audio` 放行；
/// - 维护 `MPNowPlayingInfoCenter` 的媒体元数据（标题/歌手/专辑/封面/时长/进度）；
/// - 注册 `MPRemoteCommandCenter` 的播放/暂停/上一首/下一首/进度拖拽，回传 Flutter。
///
/// media_kit（libmpv）本身不接管 iOS 音频会话与锁屏媒体信息，故在此补充——
/// 与 Android 端 `MediaNotificationPlugin`、Windows 端 SMTC 同构。
final class NowPlayingBridge {
  static let channelName = "cyrene.music/now_playing"

  private let channel: FlutterMethodChannel

  // 元数据缓存，避免每次同步都全量刷新 NowPlaying 字典。
  private var title = ""
  private var artist = ""
  private var album = ""
  private var durationMs: Int = 0
  private var positionMs: Int = 0
  private var isPlaying = false

  // 封面缓存：同一 URL 只下载/解码一次（与 Android 端 artCache 同策略）。
  private var artUrl = ""
  private var artImage: UIImage?
  private var artTask: URLSessionDataTask?

  // 最近一次音频会话激活失败的原因。启动时 Flutter 端还没挂上 handler，
  // 主动推送会丢，所以先存着，由 `ready` 的返回值带回去。
  private var sessionError: String?

  private var sessionObservers: [NSObjectProtocol] = []

  // 停止出声期间申请的后台执行时间，见 [syncBackgroundTime]。
  private var transitionTask: UIBackgroundTaskIdentifier = .invalid

  init(binaryMessenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    configureAudioSession()
    registerRemoteCommands()
    observeAudioSession()
  }

  func dispose() {
    endTransitionTask()
    for observer in sessionObservers {
      NotificationCenter.default.removeObserver(observer)
    }
    sessionObservers.removeAll()
    channel.setMethodCallHandler(nil)
    // 清空锁屏媒体信息并移除远程命令，避免后台悬挂。
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPRemoteCommandCenter.shared().playCommand.removeTarget(nil)
    MPRemoteCommandCenter.shared().pauseCommand.removeTarget(nil)
    MPRemoteCommandCenter.shared().togglePlayPauseCommand.removeTarget(nil)
    MPRemoteCommandCenter.shared().nextTrackCommand.removeTarget(nil)
    MPRemoteCommandCenter.shared().previousTrackCommand.removeTarget(nil)
    MPRemoteCommandCenter.shared().changePlaybackPositionCommand.removeTarget(nil)
    artTask?.cancel()
  }

  // ==================== Flutter → 原生（状态同步） ====================

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ready":
      // 回传会话现状（进运行日志）与启动时攒下的激活错误（进 crash.log）。
      let session = AVAudioSession.sharedInstance()
      var status: [String: Any] = [
        "category": session.category.rawValue,
        "mode": session.mode.rawValue,
        "otherAudioPlaying": session.isOtherAudioPlaying,
      ]
      if let sessionError = sessionError {
        status["sessionError"] = sessionError
      }
      result(status)
    case "updateTrack":
      guard let args = call.arguments as? [String: Any] else {
        result(nil)
        return
      }
      title = args["title"] as? String ?? ""
      artist = args["artist"] as? String ?? ""
      album = args["album"] as? String ?? ""
      durationMs = (args["durationMs"] as? NSNumber)?.intValue ?? 0
      positionMs = (args["positionMs"] as? NSNumber)?.intValue ?? 0
      isPlaying = args["isPlaying"] as? Bool ?? false
      let url = args["artUrl"] as? String ?? ""
      // 播放前确保会话处于 active（空闲一段时间后系统可能已停用会话，
      // 不重新激活会导致声音无法输出或后台被挂起）。
      activateSessionIfNeeded()
      syncBackgroundTime()
      updateNowPlayingInfo()
      loadArtwork(url)
      result(nil)
    case "updatePlayback":
      guard let args = call.arguments as? [String: Any] else {
        result(nil)
        return
      }
      isPlaying = args["isPlaying"] as? Bool ?? false
      positionMs = (args["positionMs"] as? NSNumber)?.intValue ?? 0
      if isPlaying {
        activateSessionIfNeeded()
      }
      syncBackgroundTime()
      updateNowPlayingInfo()
      result(nil)
    case "updatePosition":
      guard let args = call.arguments as? [String: Any] else {
        result(nil)
        return
      }
      positionMs = (args["positionMs"] as? NSNumber)?.intValue ?? 0
      updatePlaybackProgress()
      result(nil)
    case "clear":
      title = ""
      artist = ""
      album = ""
      artUrl = ""
      artImage = nil
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      artTask?.cancel()
      isPlaying = false
      endTransitionTask()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 元数据变化时全量刷新 NowPlaying 字典（含封面）。
  private func updateNowPlayingInfo() {
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: title,
      MPMediaItemPropertyArtist: artist,
      MPMediaItemPropertyAlbumTitle: album,
    ]
    if durationMs > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = Double(durationMs) / 1000.0
    }
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(positionMs) / 1000.0
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    if let artImage = artImage {
      info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artImage.size) { _ in artImage }
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  /// 进度拖拽/周期更新时只改时间相关字段（封面等不重设）。
  private func updatePlaybackProgress() {
    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    if durationMs > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = Double(durationMs) / 1000.0
    }
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(positionMs) / 1000.0
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  // ==================== 封面异步加载 ====================

  /// 下载并解码封面，完成后刷新 Now Playing 卡片。
  ///
  /// 与 Flutter 侧 imageHeaders（media_url.dart）对齐：网易图片 CDN
  /// （126.net / 163.com）对非官方 UA 返回 403，须伪装官方客户端头；
  /// 其他域名不附加头。同一 URL 只请求一次（url 变化前缓存 artImage）。
  private func loadArtwork(_ url: String) {
    guard !url.isEmpty else {
      artUrl = ""
      artImage = nil
      updateNowPlayingInfo()
      return
    }
    // URL 未变且已缓存/已加载：无需重复请求。
    if url == artUrl {
      if artImage != nil {
        updateNowPlayingInfo()
      }
      return
    }
    artTask?.cancel()
    artUrl = url
    artImage = nil
    guard let endpoint = URL(string: url) else { return }

    var request = URLRequest(url: endpoint)
    request.timeoutInterval = 10
    let lower = url.lowercased()
    if lower.contains("126.net") || lower.contains("163.com") {
      request.setValue(
        "NeteaseMusic/9.0.50 (iPhone; iOS 16.3.1; Scale/3.00)", forHTTPHeaderField: "User-Agent"
      )
    }

    let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      guard let self = self else { return }
      guard let data = data, let image = UIImage(data: data) else {
        // 被新曲目取消的请求不算失败。
        if (error as? URLError)?.code == .cancelled { return }
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        let reason = error?.localizedDescription ?? "HTTP \(code)，无法解码"
        DispatchQueue.main.async { self.log("封面加载失败（\(reason)）: \(url)") }
        return
      }
      DispatchQueue.main.async {
        guard self.artUrl == url else { return }
        self.artImage = image
        self.updateNowPlayingInfo()
      }
    }
    artTask = task
    task.resume()
  }

  // ==================== 原生 → Flutter（按钮事件） ====================

  private func send(_ method: String, _ arguments: Any? = nil) {
    channel.invokeMethod(method, arguments: arguments)
  }

  /// 普通运行日志：Flutter 端只写进「运行日志」，不进 crash.log。
  private func log(_ message: String) {
    send("log", message)
  }

  private func registerRemoteCommands() {
    let center = MPRemoteCommandCenter.shared()

    center.playCommand.addTarget { [weak self] _ in
      self?.send("play")
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      self?.send("pause")
      return .success
    }
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.send("playPause")
      return .success
    }
    center.nextTrackCommand.addTarget { [weak self] _ in
      self?.send("next")
      return .success
    }
    center.previousTrackCommand.addTarget { [weak self] _ in
      self?.send("previous")
      return .success
    }
    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      self?.send("seek", Int(positionEvent.positionTime * 1000))
      return .success
    }
  }

  // ==================== 切歌间隙的后台执行时间 ====================

  /// `UIBackgroundModes = audio` 只在「真的在出声」时保 App 不被挂起。一首歌
  /// 放完、libmpv 停止输出，系统几秒内就会挂起 App：下一首的解析请求挂在半路，
  /// 界面切到了下一首却不出声——和 Android 后台被断网冻结是同一个病。
  ///
  /// 所以从停止出声起申请一段后台执行时间（系统一般给 30 秒左右），够把下一首
  /// 解析完、重新出声；出声后立刻归还。用户手动暂停也会走到这里，到期系统
  /// 收回、照常挂起，不影响省电。
  private func syncBackgroundTime() {
    if isPlaying {
      endTransitionTask()
      return
    }
    guard transitionTask == .invalid else { return }
    transitionTask = UIApplication.shared.beginBackgroundTask(
      withName: "CyreneTrackTransition"
    ) { [weak self] in
      self?.endTransitionTask()
    }
  }

  private func endTransitionTask() {
    guard transitionTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(transitionTask)
    transitionTask = .invalid
  }

  // ==================== 音频会话 ====================

  /// 只记录不干预：打断、音频服务重置都可能让锁屏卡片消失，排查时要能在
  /// 运行日志里看到发生过。
  private func observeAudioSession() {
    let center = NotificationCenter.default
    sessionObservers.append(
      center.addObserver(
        forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
      ) { [weak self] notification in
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }
        switch type {
        case .began:
          self?.log("音频会话被打断（来电、闹钟或其他 App 占用）")
        case .ended:
          self?.log("音频会话打断结束")
        @unknown default:
          break
        }
      })
    sessionObservers.append(
      center.addObserver(
        forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
      ) { [weak self] _ in
        self?.log("系统音频服务已重置")
      })
  }

  /// 激活播放会话：`AVAudioSession.Category.playback` 允许锁屏/后台出声。
  /// 不加 `.mixWithOthers`——音乐播放器应独占音频（其他 App 出声时本播放应暂停）。
  /// 静默失败——即便会话激活失败，App 内播放也不受影响，仅后台能力降级。
  private func configureAudioSession() {
    activateSessionIfNeeded()
  }

  /// 幂等地把会话激活为 `.playback` 类别。
  ///
  /// `setCategory` 每次调用开销可忽略，但同类别重复激活是安全的；系统
  /// （来电、Siri、其他 App 打断）可能中途停用会话，播放前重新激活即可恢复。
  private func activateSessionIfNeeded() {
    let session = AVAudioSession.sharedInstance()
    do {
      if session.category != .playback {
        try session.setCategory(.playback, mode: .default)
      }
      try session.setActive(true)
      sessionError = nil
    } catch {
      let message = "AVAudioSession 激活失败: \(error.localizedDescription)"
      NSLog("[Cyrene] \(message)")
      // 同一原因只报一次：updatePlayback 每次播放都会走到这里。
      if message != sessionError {
        sessionError = message
        send("diagnostic", message)
      }
    }
  }
}
