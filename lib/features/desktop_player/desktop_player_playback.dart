import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../application/playback/playback_controller.dart';
import '../../domain/models/track.dart';
import '../../domain/playback/audio_player_gateway.dart';
import '../../domain/playback/playback_snapshot.dart';
import '../../domain/playback/playback_snapshot_store.dart';
import '../../domain/playback/repeat_mode.dart';
import 'desktop_player_bridge.dart';

/// 桌面播放器窗口侧的「只读播放状态」。
///
/// 歌词组件（SuperCyreneClassicLyrics / SuperCyrenePixelLyrics 等）只依赖
/// PlaybackController 的两样东西：`positionListenable` 与 `state.currentTrack`。
/// 因此这里构造一个真实的 PlaybackController 实例，喂给它一个不接音频的
/// gateway，状态全部由主窗口经 [DesktopPlayerBridge] 推送——歌词组件因而
/// 可以零改动复用。
///
/// 音频播放仍由主窗口负责；本窗口只是显示层。
class DesktopPlayerPlayback {
  DesktopPlayerPlayback() {
    _controller = PlaybackController(audio: _gateway, store: _store);
  }

  final _RemoteAudioGateway _gateway = _RemoteAudioGateway();
  final _RemoteSnapshotStore _store = _RemoteSnapshotStore();
  late final PlaybackController _controller;

  PlaybackController get controller => _controller;

  /// 当前曲目是否在默认歌单里。由主窗口解算后随状态推送（子窗口没有登录态，
  /// 也不该自建一套鉴权网络栈）。
  final ValueNotifier<bool> favorite = ValueNotifier<bool>(false);

  /// 收藏功能是否可用（主窗口已登录）。未登录时面板把爱心置灰。
  final ValueNotifier<bool> favoriteAvailable = ValueNotifier<bool>(false);

  /// 注册到子引擎的标准 MethodChannel，开始接收主窗口推送的状态。
  Future<void> bind() async {
    const channel = MethodChannel(DesktopPlayerBridge.toSubChannel);
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case DesktopPlayerBridge.methodSyncState:
          await _applyState(call.arguments as String);
        case DesktopPlayerBridge.methodSyncPosition:
          _gateway.emitPosition(
            Duration(milliseconds: (call.arguments as num).toInt()),
          );
        case DesktopPlayerBridge.methodSyncQueue:
          _applyQueue(call.arguments as String);
      }
      return null;
    });
    debugPrint('[桌面播放器][子窗口] handler 已注册 ($channel)');

    // 主动索要一次全量状态：主窗口创建 sender 时推的第一帧很可能早于
    // 上面的 handler 注册（本方法前面还 await 了 store.init()），那一帧会
    // 丢失。不主动要的话，用户不切歌就永远看不到歌词。
    const inbound = MethodChannel(DesktopPlayerBridge.toMainChannel);
    try {
      await inbound.invokeMethod<void>(DesktopPlayerBridge.methodRequestState);
      debugPrint('[桌面播放器][子窗口] 已索要全量状态');
    } catch (e) {
      debugPrint('[桌面播放器][子窗口] 索要状态失败: $e');
    }
  }

  Future<void> _applyState(String payload) async {
    try {
      final json = jsonDecode(payload) as Map<String, Object?>;
      final trackJson = json['track'] as Map<String, Object?>?;
      final track = trackJson == null ? null : Track.fromJson(trackJson);
      final isPlaying = json['isPlaying'] == true;
      final durationMs = (json['durationMs'] as num?)?.toInt() ?? 0;
      debugPrint('[桌面播放器][子窗口] 收到状态: track=${track?.name}');

      favorite.value = json['favorite'] == true;
      favoriteAvailable.value = json['favoriteAvailable'] == true;

      // 音量 / 循环模式先落到字段：下面 restore() 会用整个快照重建 state，
      // 若不带上它们，每次切歌都会把面板上的音量弹回默认值。
      _volume = ((json['volume'] as num?) ?? _volume).clamp(0.0, 1.0).toDouble();
      _repeatMode = RepeatMode.values.firstWhere(
        (mode) => mode.name == json['repeatMode'],
        orElse: () => _repeatMode,
      );

      // currentTrack 是 PlaybackController 的私有状态，外部只能经
      // playTrack()（会真的去解析播放源、拉音频）或 restore()（从快照读）
      // 设置。显示层不该触发播放，因此走 restore：把远端曲目塞进快照存储
      // 再让 controller 读回来。
      //
      // 去重不能只看 track.key：主窗口的 playTrack() 会 _publish 两次——
      // 先是不带歌词的原始 track，音源解析成功后再发一次带歌词的
      // playableTrack，两者 key 相同。只比 key 会把带歌词的那次丢掉，
      // 表现为「曲目正常显示但一直无歌词」。因此把歌词字段一并纳入比较。
      final signature = track == null
          ? null
          : '${track.key}|${track.lyric?.length ?? 0}'
                '|${track.yrc?.length ?? 0}'
                '|${track.tlyric?.length ?? 0}'
                '|${track.ytlrc?.length ?? 0}';
      if (signature != _lastTrackSignature) {
        _lastTrackSignature = signature;
        // 快照的 queue 用完整队列：展览馆读的是 controller.state.queue，
        // 若这里只塞 [track]，restore() 会把队列削成一首，展览馆里就只剩
        // 一张卡。当前曲目带歌词，队列副本不带（见 encodeQueue），因此把
        // 队列里的同 key 项换成带歌词的 track，其余原样保留。
        _store.snapshot = track == null
            ? null
            : PlaybackSnapshot(
                queue: _mergedQueue(track),
                currentTrackKey: track.key,
                volume: _volume,
                repeatMode: _repeatMode,
              );
        await _controller.restore();
        debugPrint(
          '[桌面播放器][子窗口] restore 完成: '
          'currentTrack=${_controller.state.currentTrack?.name} '
          'lyric=${_controller.state.currentTrack?.lyric?.length ?? 0}字 '
          'queue=${_controller.state.queue.length}首',
        );
      } else {
        // 同一首歌内的音量/循环变更（主窗口那边改的）：restore 不会跑，
        // 直接更新显示态。setter 打到的是空实现 gateway，不会发声。
        if (_controller.state.volume != _volume) {
          await _controller.setVolume(_volume);
        }
        if (_controller.state.repeatMode != _repeatMode) {
          _controller.setRepeatMode(_repeatMode);
        }
      }

      // 注意顺序：_onDuration / _onStatus 都有 currentTrack==null 的守卫，
      // 必须在 restore() 之后 emit，否则被直接丢弃。
      _gateway.emitDuration(Duration(milliseconds: durationMs));
      _gateway.emitStatus(
        isPlaying ? PlaybackStatus.playing : PlaybackStatus.paused,
      );
    } catch (e, s) {
      debugPrint('[桌面播放器][子窗口] 状态解析失败: $e\n$s');
    }
  }

  /// 队列同步：解成真正的 [Track] 并灌进 controller 的 `state.queue`。
  ///
  /// 展览馆（SuperCyreneSongGallery）直接读 `playback.state.queue`，所以队列
  /// 必须落到 controller 里，而不是只存一份旁路列表。
  void _applyQueue(String payload) {
    try {
      final json = jsonDecode(payload) as Map<String, Object?>;
      final tracks = json['tracks'];
      _queue = tracks is List
          ? [
              for (final item in tracks.whereType<Map>())
                Track.fromJson(Map<String, Object?>.from(item)),
            ]
          : const [];
      // setQueue 只改 state.queue 并 notifyListeners，不碰音频。
      _controller.setQueue(_mergedQueue(_controller.state.currentTrack));
      debugPrint('[桌面播放器][子窗口] 队列已同步: ${_queue.length}首');
    } catch (e) {
      debugPrint('[桌面播放器][子窗口] 队列解析失败: $e');
    }
  }

  /// 把队列里与 [current] 同 key 的那项替换成 [current]；队列里没有它时并进去。
  ///
  /// 队列副本经 encodeQueue 剥掉了歌词（否则跨窗口负载爆炸），而当前曲目那份
  /// 是带歌词的。若不做这个替换，PlaybackController.restore() 会从队列里按 key
  /// 取回**无歌词**的那个实例当 currentTrack，桌面歌词就永远是空的。
  ///
  /// [current] 不在 [_queue] 里时必须补进去：restore() 是按 currentTrackKey 到
  /// 队列里找曲目的，找不到就把 currentTrack 置空——面板显示「未在播放」、歌词
  /// 退回占位文案，且此后同一首歌的状态推送都会被 [_lastTrackSignature] 去重，
  /// 永远恢复不了。换队列播放（私人FM、播放历史）时旧队列必然不含新曲目，
  /// 正是这条路径踩的坑。
  List<Track> _mergedQueue(Track? current) {
    if (current == null) return _queue;
    if (!_queue.any((track) => track.key == current.key)) {
      return [current, ..._queue];
    }
    return [
      for (final track in _queue) track.key == current.key ? current : track,
    ];
  }

  String? _lastTrackSignature;
  List<Track> _queue = const [];
  double _volume = 1;
  RepeatMode _repeatMode = RepeatMode.all;

  void dispose() {
    _controller.dispose();
    _gateway.dispose();
    favorite.dispose();
    favoriteAvailable.dispose();
  }
}

/// 不接真实音频的 gateway：只把主窗口推来的状态转成流事件。
class _RemoteAudioGateway implements AudioPlayerGateway {
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _status = StreamController<PlaybackStatus>.broadcast();

  /// 当前曲目由 DesktopPlayerPlayback 经快照存储注入，不走这里。
  void emitPosition(Duration value) => _position.add(value);
  void emitDuration(Duration value) => _duration.add(value);
  void emitStatus(PlaybackStatus value) => _status.add(value);

  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration?> get durationStream => _duration.stream;
  @override
  Stream<PlaybackStatus> get statusStream => _status.stream;

  // 以下为显示层不需要的写操作，全部空实现。
  @override
  Future<Duration?> load(Uri source) async => null;
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _position.close();
    await _duration.close();
    await _status.close();
  }
}

/// 可写的快照源：主窗口推来的曲目塞进这里，再由 controller.restore() 读回。
class _RemoteSnapshotStore implements PlaybackSnapshotStore {
  PlaybackSnapshot? snapshot;

  @override
  Future<PlaybackSnapshot?> read() async => snapshot;

  /// 显示层不持久化任何东西。
  @override
  Future<void> write(PlaybackSnapshot snapshot) async {}
}
