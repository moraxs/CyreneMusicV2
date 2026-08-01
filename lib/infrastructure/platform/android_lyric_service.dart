import 'android_media_notification_service.dart';

/// Android 通知栏歌词服务（对应 Next.js demo/lib/services/androidLyricService.ts）。
///
/// 原实现通过 Tauri invoke 调用 Android 原生桥接，在系统通知栏滚动显示当前歌词：
/// 定时(300ms)轮询 usePlayerStore 播放进度，用 parseLyrics 解析当前 track 歌词，
/// 匹配活跃行后推送到原生通知栏。Flutter 端需接入播放器状态流与歌词解析器，并通过
/// 平台通道（MethodChannel）桥接 Android 通知。方法签名保留，实现体留待 TODO。
class AndroidLyricService {
  AndroidLyricService._() {
    if (isAndroidTauriRuntime()) {
      _setupListeners();
    }
  }
  static final AndroidLyricService instance = AndroidLyricService._();

  int _lastSentLyricIndex = -1;
  // 解析后的歌词行（对应 LyricLineData[]，待 domain/lyrics 移植后替换具体类型）。
  List<Object> _currentLyrics = const [];
  Object? _currentTrackId;

  /// 设置监听：定时轮询当前播放进度，匹配歌词行并推送到原生通知栏。
  ///
  /// TODO: 原 TS 用 setInterval(300ms) 轮询 usePlayerStore 状态，并通过 parseLyrics
  ///       解析当前 track 的歌词；track 切换时重置解析。Flutter 端需接入播放器状态流
  ///       与歌词解析器（domain/lyrics）。
  void _setupListeners() {
    // TODO: 平台实现 - 订阅播放器状态流，定时(300ms)调用 _checkAndUpdateLyric，
    //       track 切换时重新解析歌词：_currentLyrics = parseLyrics(track);
    //       并重置 _lastSentLyricIndex。
    _currentLyrics = const []; // 占位：track 切换时由平台实现重新填充
    _checkAndUpdateLyric();
  }

  /// 检查并更新当前歌词行。
  void _checkAndUpdateLyric() {
    // TODO: 平台实现 - 根据 currentTime(ms) 匹配 _currentLyrics 中的活跃行，
    //       当 activeIndex != _lastSentLyricIndex 时更新 _lastSentLyricIndex
    //       并调用 _sendToAndroid(trackName, lyricText)。
    if (_currentLyrics.isEmpty || _currentTrackId == null) {
      _hideNotification();
      return;
    }
    if (_lastSentLyricIndex >= 0) {
      _sendToAndroid('', '');
    }
    _lastSentLyricIndex = -1;
  }

  /// 推送歌词到 Android 通知栏。
  ///
  /// TODO: 原 TS 通过 `invoke('android_lyric_notification_update', { payload: { title, lyric } })`。
  void _sendToAndroid(String title, String lyric) {
    try {
      // TODO: 平台实现 - 通过 MethodChannel 调用 android_lyric_notification_update。
    } catch (_) {
      // 与 TS 一致：吞掉警告。
    }
  }

  /// 隐藏通知栏歌词。
  ///
  /// TODO: 原 TS 通过 `invoke('android_lyric_notification_hide')`。
  void _hideNotification() {
    try {
      // TODO: 平台实现 - 通过 MethodChannel 调用 android_lyric_notification_hide。
    } catch (_) {
      // 与 TS 一致：吞掉警告。
    }
  }
}
