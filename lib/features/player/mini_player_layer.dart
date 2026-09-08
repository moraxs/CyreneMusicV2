import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../application/audio_sources/audio_source_preferences_controller.dart';
import '../../application/auth/account_session_controller.dart';
import '../../application/playback/playback_controller.dart';
import '../../presentation/cyrene/breakpoints.dart';
import 'mini_player.dart';

/// 全屏播放器路由的统一标记名。
///
/// 打在 [RouteSettings.name] 上，供 [MiniPlayerRouteObserver] 识别「当前已经在
/// 全屏播放器里了」——此时不该再往上浮一个迷你播放器。用路由名而不是判断路由
/// 类型，是因为竖屏流体云走的是普通 `CupertinoPageRoute`，没有专属类可认。
const String kFullscreenPlayerRouteName = 'cyrene/fullscreen-player';

/// 迷你播放器的显隐判定。
///
/// 它挂在 Navigator **之上**（见 [MiniPlayerLayer]），所以拿不到路由上下文，
/// 只能靠这个观察者把导航栈的状态送出来。
class MiniPlayerRouteObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = <Route<dynamic>>[];

  final ValueNotifier<bool> _hidden = ValueNotifier<bool>(false);

  /// 当前是否应当隐藏迷你播放器（栈里存在全屏播放器路由）。
  ValueListenable<bool> get hidden => _hidden;

  void _sync() {
    _hidden.value = _stack.any(
      (route) => route.settings.name == kFullscreenPlayerRouteName,
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final at = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (at >= 0) {
      if (newRoute == null) {
        _stack.removeAt(at);
      } else {
        _stack[at] = newRoute;
      }
    } else if (newRoute != null) {
      _stack.add(newRoute);
    }
    _sync();
  }
}

/// 全局迷你播放器层：挂在 Navigator **之上**，因此任何被 push 的页面
/// （歌单详情、搜索、设置……）都盖不住它。
///
/// 以前它是外壳 [MusicAppShell] 里 Scaffold body 的一个 Positioned，
/// 而 push 出来的路由整块盖在外壳上，于是一进歌单详情迷你播放器就没了。
/// 挪到这里之后位置反而更稳：底部偏移固定，切页面时不会跳。
///
/// 桌面/平板（宽 >= 900）不走这里——那边由 DesktopShell 自带 DesktopMiniPlayer，
/// 且它的二级页是内容区内嵌的，本来就不存在被盖住的问题。
class MiniPlayerLayer extends StatelessWidget {
  const MiniPlayerLayer({
    super.key,
    required this.playback,
    required this.audioSources,
    required this.account,
    required this.observer,
    required this.navigatorKey,
  });

  final PlaybackController playback;
  final AudioSourcePreferencesController audioSources;
  final AccountSessionController account;
  final MiniPlayerRouteObserver observer;

  /// 迷你播放器要 push 全屏播放器，但它自己在 Navigator 上方，
  /// `Navigator.of(context)` 找不到祖先，只能靠这个 key。
  final GlobalKey<NavigatorState> navigatorKey;

  /// 底部偏移。取外壳底部标签栏之上的老位置（bottom: 104）并**固定不变**：
  /// 二级页没有标签栏，跟着变会让迷你播放器在切页时上下跳一下。
  static const double _bottomInset = 104;

  @override
  Widget build(BuildContext context) {
    if (isDesktopLayout(context)) return const SizedBox.shrink();

    return ValueListenableBuilder<bool>(
      valueListenable: observer.hidden,
      builder: (context, hidden, _) {
        if (hidden) return const SizedBox.shrink();
        return AnimatedBuilder(
          animation: playback,
          builder: (context, _) {
            if (playback.state.currentTrack == null) {
              return const SizedBox.shrink();
            }
            return Positioned(
              left: 16,
              right: 16,
              bottom: _bottomInset,
              child: MiniPlayer(
                playback: playback,
                audioSources: audioSources,
                account: account,
                navigatorKey: navigatorKey,
              ),
            );
          },
        );
      },
    );
  }
}
