import 'package:flutter/material.dart';

import '../../application/audio_sources/audio_source_preferences_controller.dart';
import '../../application/auth/account_session_controller.dart';
import '../../application/playback/playback_controller.dart';
import '../../application/stores/fullscreen_settings_store.dart';
import 'desktop_fullscreen_player.dart';
import 'super_cyrene/super_cyrene_fullscreen_player.dart';

/// Owns only the desktop fullscreen player mode transition.
///
/// Keeping this state outside either player lets the classic and SuperCyrene
/// implementations evolve independently instead of growing one monolithic file.
class DesktopFullscreenPlayerHost extends StatelessWidget {
  const DesktopFullscreenPlayerHost({
    super.key,
    required this.playback,
    required this.audioSources,
    required this.account,
  });

  final PlaybackController playback;
  final AudioSourcePreferencesController audioSources;
  final AccountSessionController account;

  @override
  Widget build(BuildContext context) {
    final settings = FullscreenSettingsStore.instance;
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        reverseDuration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.018, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: settings.superCyrenePlayerEnabled
            ? SuperCyreneFullscreenPlayer(
                key: const ValueKey('super-cyrene'),
                playback: playback,
                audioSources: audioSources,
                account: account,
                onSwitchToClassic: () =>
                    settings.setSuperCyrenePlayerEnabled(false),
              )
            : DesktopFullscreenPlayer(
                key: const ValueKey('classic'),
                playback: playback,
                audioSources: audioSources,
                account: account,
                onSwitchToSuperCyrene: () =>
                    settings.setSuperCyrenePlayerEnabled(true),
              ),
      ),
    );
  }
}
