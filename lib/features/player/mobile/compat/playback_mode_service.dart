import 'package:flutter/foundation.dart';

import '../../../../domain/playback/repeat_mode.dart';
import 'player_service.dart';

/// 播放模式（与原版一致的三态）。
enum PlaybackMode {
  sequential,
  repeatOne,
  shuffle,
}

/// 原版 `PlaybackModeService` 兼容层：三态映射到新架构 [RepeatMode]
/// （sequential↔all、repeatOne↔one、shuffle↔shuffle），状态由
/// PlaybackController 持久化，无需另行存储。
class PlaybackModeService extends ChangeNotifier {
  static final PlaybackModeService _instance = PlaybackModeService._internal();
  factory PlaybackModeService() => _instance;
  PlaybackModeService._internal() {
    PlayerService().addListener(notifyListeners);
  }

  PlaybackMode get currentMode => switch (PlayerService().repeatMode) {
    RepeatMode.one => PlaybackMode.repeatOne,
    RepeatMode.shuffle => PlaybackMode.shuffle,
    _ => PlaybackMode.sequential,
  };

  Future<void> toggleMode() async {
    final next =
        PlaybackMode.values[(currentMode.index + 1) % PlaybackMode.values.length];
    await setMode(next);
  }

  Future<void> setMode(PlaybackMode mode) async {
    PlayerService().setRepeatMode(switch (mode) {
      PlaybackMode.sequential => RepeatMode.all,
      PlaybackMode.repeatOne => RepeatMode.one,
      PlaybackMode.shuffle => RepeatMode.shuffle,
    });
    notifyListeners();
  }

  String getModeIcon() => switch (currentMode) {
    PlaybackMode.sequential => '🔁',
    PlaybackMode.repeatOne => '🔂',
    PlaybackMode.shuffle => '🔀',
  };

  String getModeName() => switch (currentMode) {
    PlaybackMode.sequential => '顺序播放',
    PlaybackMode.repeatOne => '单曲循环',
    PlaybackMode.shuffle => '随机播放',
  };
}
