import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../application/audio_sources/audio_source_preferences_controller.dart';
import '../../../application/auth/account_session_controller.dart';
import '../../../application/playback/playback_controller.dart';
import '../../../application/stores/fullscreen_settings_store.dart';
import '../super_cyrene/super_cyrene_fullscreen_player.dart';
import 'mobile_fullscreen_player_route.dart';

/// 移动端是否应打开 SuperCyrene 全屏播放器。
///
/// 外观设置里选了 SuperCyrene 且是移动端（安卓/iOS）时为 true。桌面端有自己
/// 的 [DesktopFullscreenPlayerHost]，不走这里。
bool shouldOpenMobileSuperCyrene() {
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    return FullscreenSettingsStore.instance.superCyrenePlayerEnabled;
  }
  return false;
}

/// 移动端打开 SuperCyrene 全屏播放器（横屏页）。
void pushMobileSuperCyrenePlayer(
  BuildContext context, {
  required PlaybackController playback,
  required AudioSourcePreferencesController audioSources,
  required AccountSessionController account,
}) {
  Navigator.of(context).push(
    MobileFullscreenPlayerRoute(
      builder: (_) => MobileFullscreenPlayerHost(
        playback: playback,
        audioSources: audioSources,
        account: account,
      ),
    ),
  );
}

/// 移动端全屏播放器的 SuperCyrene 承载壳。
///
/// 移动端进入全屏播放器时（见 music_app_shell / mini_player 的 _openPlayer），
/// 若外观设置里选了 SuperCyrene，就 push 本壳（经 [MobileFullscreenPlayerRoute]）
/// 显示 SuperCyrene 播放器；否则照旧 push 流体云的 [MobilePlayerPage]。
///
/// 本壳只关心一件事：`superCyrenePlayerEnabled` 是否仍为 true。为 true 就渲染
/// SuperCyrene；一旦用户点了「切回经典」（onSwitchToClassic 会把该字段置 false），
/// 移动端没有桌面那种同屏切换，直接 pop 回到流体云播放器。
class MobileFullscreenPlayerHost extends StatefulWidget {
  const MobileFullscreenPlayerHost({
    super.key,
    required this.playback,
    required this.audioSources,
    required this.account,
  });

  final PlaybackController playback;
  final AudioSourcePreferencesController audioSources;
  final AccountSessionController account;

  @override
  State<MobileFullscreenPlayerHost> createState() =>
      _MobileFullscreenPlayerHostState();
}

class _MobileFullscreenPlayerHostState extends State<MobileFullscreenPlayerHost> {
  @override
  void initState() {
    super.initState();
    // 监听设置变化，捕捉「切回经典」。
    FullscreenSettingsStore.instance.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    FullscreenSettingsStore.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    if (!FullscreenSettingsStore.instance.superCyrenePlayerEnabled) {
      // 用户切回了经典：pop 本壳，回到流体云播放器。
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 若字段已被外部置 false（例如测试里直接改设置），就不渲染 SuperCyrene，
    // 交给上层 pop。
    return SuperCyreneFullscreenPlayer(
      playback: widget.playback,
      audioSources: widget.audioSources,
      account: widget.account,
      onSwitchToClassic: () =>
          FullscreenSettingsStore.instance.setSuperCyrenePlayerEnabled(false),
    );
  }
}