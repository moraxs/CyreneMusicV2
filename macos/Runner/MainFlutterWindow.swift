import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // 首帧渲染前窗口露出的就是这层底色。NSWindow 默认是白的，于是「还在启动」
    // 和「卡死白屏」长得一模一样，用户只能反馈「打开就是白的」，拿不到任何
    // 线索。换成与 StartupFailureApp 一致的深色：至少一眼能认出是本应用。
    // Flutter 起来后整屏由 Flutter 绘制，这层不会再影响任何观感。
    self.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
