import 'dart:async';

import '../../infrastructure/services/history_service.dart';
import '../../infrastructure/services/listening_stats_service.dart';
import '../../domain/models/track.dart';
import '../auth/account_session_controller.dart';
import 'playback_controller.dart';

/// 播放记录桥：监听 [PlaybackController]，把播放行为写入历史与听歌统计。
///
/// - 切歌时：本地历史 +1（[HistoryService.recordPlay]）；已登录另计服务端
///   播放次数（recordPlayCount），并把上一首的实听时长上报为播放事件。
/// - 收听时长：按进度 tick 增量累计（暂停/拖动不计），每满 30 秒落一次
///   本地 [HistoryService.recordTime]。
class PlaybackHistoryRecorder {
  PlaybackHistoryRecorder({required this.playback, required this.account}) {
    playback.addListener(_onPlaybackChanged);
    // 收听时长按高频进度增量累计，须监听独立的 position 通知
    // （主 notifyListeners 已不含 position tick）。
    playback.positionListenable.addListener(_onPositionTick);
    // 与 Next.js 版一致：周期性把累计时长 POST /stats/listening-time，
    // 否则服务端统计（总时长/足迹页）恒为零。
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      ListeningStatsService.instance.syncListeningTime(account.token);
    });
  }

  final PlaybackController playback;
  final AccountSessionController account;

  Timer? _syncTimer;
  String? _lastKey;
  Track? _currentTrack;
  Duration _lastPosition = Duration.zero;
  double _pendingSeconds = 0;
  double _sessionSeconds = 0;

  void _onPlaybackChanged() {
    final state = playback.state;
    final track = state.currentTrack;
    if (track?.key != _lastKey) {
      _flushSession();
      _lastKey = track?.key;
      _currentTrack = track;
      _lastPosition = state.position;
      if (track != null) {
        HistoryService.instance.recordPlay(track);
        final token = account.token;
        if (token != null && token.isNotEmpty) {
          ListeningStatsService.instance.recordPlayCount(track, token);
        }
      }
    }
  }

  /// 高频进度 tick：按增量累计实听时长（暂停/拖动不计）。
  void _onPositionTick() {
    final state = playback.state;
    if (state.currentTrack?.key != _lastKey) {
      // 切歌瞬间可能先来 tick 后来结构通知，跳过本次，交由切歌分支重置基准。
      _lastPosition = state.position;
      return;
    }
    final deltaMs = (state.position - _lastPosition).inMilliseconds;
    _lastPosition = state.position;
    // 只累计正常播放的前进量：负值/大跳视为 seek，不计入时长。
    if (state.isPlaying && deltaMs > 0 && deltaMs < 2000) {
      _pendingSeconds += deltaMs / 1000;
      _sessionSeconds += deltaMs / 1000;
      if (_pendingSeconds >= 30) _flushTime();
    }
  }

  void _flushTime() {
    final track = _currentTrack;
    final seconds = _pendingSeconds.floor();
    if (track == null || seconds <= 0) return;
    _pendingSeconds -= seconds;
    HistoryService.instance.recordTime(
      track.id,
      track.source.wireName,
      seconds,
    );
    // 同步累计到服务端待上报池（由定时器批量 POST）。
    ListeningStatsService.instance.accumulateListeningTime(seconds);
  }

  void _flushSession() {
    _flushTime();
    final track = _currentTrack;
    final seconds = _sessionSeconds.round();
    _sessionSeconds = 0;
    final token = account.token;
    // 5 秒以上的实听才作为一次播放事件上报，避免误触刷屏。
    if (track != null && seconds >= 5 && token != null && token.isNotEmpty) {
      ListeningStatsService.instance.recordPlayEvent(track, token, seconds);
      ListeningStatsService.instance.syncListeningTime(token);
    }
  }

  void dispose() {
    _flushSession();
    _syncTimer?.cancel();
    playback.removeListener(_onPlaybackChanged);
    playback.positionListenable.removeListener(_onPositionTick);
  }
}
