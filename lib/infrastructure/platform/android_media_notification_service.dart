/// Android 媒体通知桥接（对应 Next.js demo/lib/services/androidMediaNotificationService.ts）。
///
/// 原实现运行在 Tauri Android WebView 中，通过 invoke 调用原生通知。Flutter 端
/// 不存在 Tauri 运行时；歌词通知需改走 MethodChannel，实现留待 TODO。
library;

/// 是否处于 Android Tauri 运行时。Flutter 构建恒为 false；
/// AndroidLyricService 据此跳过通知栏歌词轮询。
bool isAndroidTauriRuntime() => false;
