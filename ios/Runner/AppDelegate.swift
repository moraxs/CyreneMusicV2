import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var nowPlayingBridge: NowPlayingBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // iOS 系统媒体会话桥：后台播放 + 锁屏 Now Playing 卡片（详见 NowPlayingBridge）。
    // 通过 pluginRegistry 的 registrar 取 binaryMessenger 建立 MethodChannel。
    if let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "NowPlaying")?.messenger() {
      nowPlayingBridge = NowPlayingBridge(binaryMessenger: messenger)
    }
  }
}
