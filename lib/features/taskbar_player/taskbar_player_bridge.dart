import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../application/playback/playback_controller.dart';

/// 主窗口 ↔ 任务栏播放器子窗口之间的通道常量。
///
/// 与桌面歌词同一套中继机制（见 desktop_player_bridge.dart），换一组通道名：
/// runner 在子引擎 messenger 上注册标准 MethodChannel，主引擎侧再通过原始
/// 字节中继把它们接通到子引擎（见 taskbar_player_window.cpp 的 RegisterChannels）。
///
/// 与桌面歌词的关键差异：**不传歌词、不传队列**。任务栏播放器只有一条
/// 40~50px 高的窄条，显示封面/标题/歌手/播放态/进度，歌词与队列都用不上。
/// 少传即是快——状态推送是每次播放变更都会发生的高频操作。
class TaskbarPlayerBridge {
  TaskbarPlayerBridge._();

  /// 主→子：主窗口推送播放状态。
  static const toSubChannel = 'cyrene/taskbar_player/to_sub';

  /// 子→主：子窗口索要状态 / 回传命令。
  static const toMainChannel = 'cyrene/taskbar_player/to_main';

  /// 子→原生：beginDrag 直达（拖拽）。
  ///
  /// 不能走 [toMainChannel] 再由主窗口转发——拖拽必须在原生侧同步进入
  /// Windows 的模态移动循环，绕一圈主窗口既慢又会错过按下时机。该 handler
  /// 由 C++ 在子引擎启动时同步注册（见 taskbar_player_window.cpp 的
  /// RegisterChannels），早于子引擎 Dart 运行。
  static const directChannel = 'cyrene/taskbar_player';

  static const methodSyncState = 'syncState';
  static const methodRequestState = 'requestState';
  static const methodCommand = 'command';
  static const methodBeginDrag = 'beginDrag';

  /// 把播放状态编码为可跨引擎传输的 JSON 字符串。
  ///
  /// 只挑任务栏那一条窄栏真正会渲染的字段，**不用** Track.toJson——那会把
  /// 四份歌词（lyric/yrc/tlyric/ytlrc）一起塞进来，每次切歌都是几十上百 KB
  /// 的无用负载。
  ///
  /// 也不含播放进度：这条窄栏不画进度条，而进度每 200ms 变一次，推过来
  /// 就是每秒 5 次白白跨引擎往返。
  static String encodeState(PlaybackController playback) {
    final state = playback.state;
    final track = state.currentTrack;
    return jsonEncode({
      'isPlaying': state.isPlaying,
      'hasTrack': track != null,
      'title': track?.name ?? '',
      'artists': track?.artists ?? '',
      'coverUrl': track?.picUrl ?? '',
    });
  }
}

/// 任务栏播放器的显示状态（子窗口侧）。
@immutable
class TaskbarPlayerState {
  const TaskbarPlayerState({
    this.hasTrack = false,
    this.isPlaying = false,
    this.title = '',
    this.artists = '',
    this.coverUrl = '',
  });

  final bool hasTrack;
  final bool isPlaying;
  final String title;
  final String artists;
  final String coverUrl;

  static TaskbarPlayerState fromJson(Map<String, Object?> json) =>
      TaskbarPlayerState(
        hasTrack: json['hasTrack'] == true,
        isPlaying: json['isPlaying'] == true,
        title: json['title']?.toString() ?? '',
        artists: json['artists']?.toString() ?? '',
        coverUrl: json['coverUrl']?.toString() ?? '',
      );
}

/// 主窗口侧：监听 PlaybackController，把状态推送给任务栏播放器子窗口。
///
/// 生命周期与任务栏播放器窗口绑定——窗口关闭时必须 dispose，否则会持续向
/// 一个已销毁的引擎发消息。
///
/// 与 DesktopPlayerStateSender 同构，但精简得多：没有收藏解算（任务栏那条
/// 窄栏放不下爱心，也不值得为它拉一套鉴权网络栈）、没有队列推送、没有进度
/// 推送（不画进度条）。因此**不订阅** positionListenable——那是每 200ms 一
/// 次的高频源。
class TaskbarPlayerStateSender {
  TaskbarPlayerStateSender({required this.playback, this.onShowMain}) {
    playback.addListener(_onStateChanged);
    _inbound.setMethodCallHandler((call) async {
      switch (call.method) {
        case TaskbarPlayerBridge.methodRequestState:
          // 强制推送：子窗口刚起来，它那边一定是空的。这里若走去重，会因为
          // 「负载与上一次推送相同」而被跳过，任务栏播放器就永远空白。
          _pushState(force: true);
        case TaskbarPlayerBridge.methodCommand:
          await _runCommand(call.arguments);
      }
      return null;
    });
    // 不在这里主动推首帧：sender 总是先于窗口创建（要先挂好 toMain 的命令
    // handler，子引擎起来才有人应答），此刻中继 handler 还没注册，推了必然
    // 抛 MissingPluginException。子窗口就绪后会自己发 requestState 来要。
  }

  final PlaybackController playback;

  /// 点击封面时唤起主窗口。由主窗口注入（子引擎自己调 window_manager
  /// 只会作用到它自己那个不可见的顶层窗口上）。
  final Future<void> Function()? onShowMain;

  late final MethodChannel _inbound = const MethodChannel(
    TaskbarPlayerBridge.toMainChannel,
  );
  late final MethodChannel _outbound = const MethodChannel(
    TaskbarPlayerBridge.toSubChannel,
  );

  bool _disposed = false;

  /// 上一次推送的状态负载。PlaybackController 的通知不止来自切歌/播放态
  /// （音量、循环模式等也会触发），去重后只在这条窄栏真正要重绘时才跨引擎。
  String? _lastPayload;

  void _onStateChanged() {
    if (_disposed) return;
    _pushState();
  }

  void _pushState({bool force = false}) {
    if (_disposed) return;
    final payload = TaskbarPlayerBridge.encodeState(playback);
    if (!force && payload == _lastPayload) return;
    _lastPayload = payload;
    _send(TaskbarPlayerBridge.methodSyncState, payload);
  }

  /// 执行子窗口回传的播放控制命令（在主窗口的真实 PlaybackController 上）。
  ///
  /// [arguments] 为 `{'action': String}`。
  Future<void> _runCommand(Object? arguments) async {
    if (arguments is! Map) {
      debugPrint('[任务栏播放器] 命令格式错误: $arguments');
      return;
    }
    switch (arguments['action']?.toString()) {
      case 'togglePlay':
        await playback.togglePlay();
      case 'next':
        await playback.playNext();
      case 'showMain':
        await onShowMain?.call();
      default:
        debugPrint('[任务栏播放器] 未知命令: ${arguments['action']}');
    }
  }

  void _send(String method, Object? arguments) {
    _outbound.invokeMethod<void>(method, arguments).catchError((Object e) {
      // 子窗口可能尚未就绪，或已被销毁。
      debugPrint('[任务栏播放器] 状态推送失败($method): $e');
      return null;
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    playback.removeListener(_onStateChanged);
    _inbound.setMethodCallHandler(null);
  }
}

/// 子窗口侧：接收主窗口推送的状态，并向主窗口回传播放控制命令。
///
/// 任务栏播放器不需要 PlaybackController：它只显示封面/标题/歌手/播放态，
/// 用不到歌词组件，因此不必像桌面歌词那样搭一个假 gateway 的 controller。
/// 一个 ValueNotifier 就够了。
class TaskbarPlayerClient {
  TaskbarPlayerClient();

  final ValueNotifier<TaskbarPlayerState> state =
      ValueNotifier<TaskbarPlayerState>(const TaskbarPlayerState());

  static const MethodChannel _toMain = MethodChannel(
    TaskbarPlayerBridge.toMainChannel,
  );

  /// 注册到子引擎的标准 MethodChannel，开始接收主窗口推送的状态。
  Future<void> bind() async {
    const channel = MethodChannel(TaskbarPlayerBridge.toSubChannel);
    channel.setMethodCallHandler((call) async {
      if (call.method == TaskbarPlayerBridge.methodSyncState) {
        _applyState(call.arguments as String);
      }
      return null;
    });

    // 主动索要一次全量状态：主窗口的 sender 早于本窗口创建，它不会主动推
    // 首帧（那时中继 handler 还没注册）。不主动要的话，用户不切歌就一直
    // 是空白条。
    try {
      await _toMain.invokeMethod<void>(TaskbarPlayerBridge.methodRequestState);
    } catch (e) {
      debugPrint('[任务栏播放器][子窗口] 索要状态失败: $e');
    }
  }

  void _applyState(String payload) {
    try {
      state.value = TaskbarPlayerState.fromJson(
        jsonDecode(payload) as Map<String, Object?>,
      );
    } catch (e) {
      debugPrint('[任务栏播放器][子窗口] 状态解析失败: $e');
    }
  }

  /// [action] 取 togglePlay / next / showMain。
  static Future<void> send(String action) async {
    try {
      await _toMain.invokeMethod<void>(TaskbarPlayerBridge.methodCommand, {
        'action': action,
      });
    } catch (e) {
      debugPrint('[任务栏播放器][子窗口] 命令发送失败($action): $e');
    }
  }

  /// 开始拖拽窗口。原生会接管为 Windows 的模态移动循环，松手后自行判定
  /// 是吸附回任务栏还是转为悬浮，并把结果回报给主窗口持久化。
  ///
  /// 直达原生（不经主窗口中转）：拖拽要在按下的那一刻同步进入系统循环。
  static Future<void> beginDrag() async {
    try {
      await const MethodChannel(
        TaskbarPlayerBridge.directChannel,
      ).invokeMethod<void>(TaskbarPlayerBridge.methodBeginDrag);
    } catch (e) {
      debugPrint('[任务栏播放器][子窗口] 开始拖拽失败: $e');
    }
  }

  void dispose() {
    state.dispose();
  }
}
