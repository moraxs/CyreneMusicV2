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
///
/// 这里还兜着**返回键退出**：布局断点是按宽度判的（>=900 走桌面壳），所以平板
/// 也会渲染这套桌面播放器，可它的退出入口只有「悬停顶部浮出的标题栏折叠键」和
/// Esc——触摸屏不产生 hover 事件、平板也没键盘，两条路同时断掉，用户就被锁在
/// 全屏播放器里出不去了。返回键是触摸设备上唯一还在的退出手势，必须接住。
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

  /// 返回键 = 最小化播放器：pop 掉这条全屏路由，回到外壳的迷你播放器，
  /// 播放本身不受影响（路由只是揭幕层，PlaybackController 在外壳里活着）。
  ///
  /// 用 `canPop: false` + 手动 pop 而不是靠 Navigator 的默认行为：这样退出只有
  /// 这一个出口，桌面端也能顺带接住带返回手势的输入设备。`Navigator.pop` 不走
  /// PopScope 的拦截，不会自己递归回来。
  void _minimize(BuildContext context) {
    // 退场动画期间路由已不是 current，此时再 pop 会连外壳那层一起弹掉——
    // 连按两下返回键就会把用户直接扔出播放页面。
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final settings = FullscreenSettingsStore.instance;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _minimize(context);
      },
      child: AnimatedBuilder(
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
      ),
    );
  }
}
