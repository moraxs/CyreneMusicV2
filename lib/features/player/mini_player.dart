import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../application/audio_sources/audio_source_preferences_controller.dart';
import '../../application/auth/account_session_controller.dart';
import '../../application/playback/playback_controller.dart';
import '../../domain/models/track.dart';
import '../../domain/playback/playback_state.dart';
import 'mini_player_layer.dart' show kFullscreenPlayerRouteName;
import 'mobile/mobile_fullscreen_player_host.dart';
import 'mobile/mobile_player_page.dart';
import 'track_artwork.dart';

/// 全局底部迷你播放器：液态玻璃面板。
///
/// 闲置 [_collapseDelay] 无任何触摸后自动折叠为仅封面（靠左停靠），
/// 点击封面重新展开；展开态点击正文进入全屏播放页，面板内任意触摸都会
/// 重置折叠计时。
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({
    super.key,
    required this.playback,
    required this.audioSources,
    required this.account,
    this.navigatorKey,
  });

  final PlaybackController playback;
  final AudioSourcePreferencesController audioSources;
  final AccountSessionController account;

  /// 用于打开全屏播放器的 Navigator。
  ///
  /// 迷你播放器现在挂在 Navigator **之上**（见 [MiniPlayerLayer]），
  /// `Navigator.of(context)` 找不到祖先，必须由外部把根 Navigator 的 key 传进来。
  /// 为 null 时退回从 context 找（保留给仍在路由树内使用的场景）。
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  /// 无操作多久后折叠为仅封面。
  static const _collapseDelay = Duration(seconds: 5);
  static const _height = 68.0;

  Timer? _collapseTimer;
  var _collapsed = false;

  @override
  void initState() {
    super.initState();
    _restartCollapseTimer();
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    super.dispose();
  }

  void _restartCollapseTimer() {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(_collapseDelay, () {
      if (mounted) setState(() => _collapsed = true);
    });
  }

  void _expand() {
    setState(() => _collapsed = false);
    _restartCollapseTimer();
  }

  NavigatorState? get _navigator =>
      widget.navigatorKey?.currentState ?? Navigator.maybeOf(context);

  void _openPlayer() {
    final navigator = _navigator;
    if (navigator == null) return;
    // 移动端：外观设置选了 SuperCyrene 时进横屏 SuperCyrene 播放器。
    if (shouldOpenMobileSuperCyrene()) {
      pushMobileSuperCyrenePlayer(
        navigator,
        playback: widget.playback,
        audioSources: widget.audioSources,
        account: widget.account,
      );
      return;
    }
    navigator.push(
      CupertinoPageRoute<void>(
        // 标记成全屏播放器路由，好让全局迷你播放器层在它打开时收起自己。
        settings: const RouteSettings(name: kFullscreenPlayerRouteName),
        builder: (_) => MobilePlayerPage(
          playback: widget.playback,
          audioSources: widget.audioSources,
          account: widget.account,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.playback.state;
    final track = state.currentTrack;
    if (track == null) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (!_collapsed) _restartCollapseTimer();
        },
        child: GlassContainer(
          shape: const LiquidRoundedSuperellipse(borderRadius: 20),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) => AnimatedCrossFade(
              duration: const Duration(milliseconds: 280),
              sizeCurve: Curves.easeOutCubic,
              firstCurve: Curves.easeOut,
              secondCurve: Curves.easeOut,
              alignment: Alignment.centerLeft,
              crossFadeState: _collapsed
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: _buildCollapsed(track),
              secondChild: _buildExpanded(
                context,
                state,
                track,
                constraints.maxWidth,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsed(Track track) => Semantics(
    button: true,
    label: '展开迷你播放器：${track.name}',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _expand,
      child: SizedBox.square(
        dimension: _height,
        child: Center(
          child: TrackArtwork(track: track, size: 48, borderRadius: 10),
        ),
      ),
    ),
  );

  Widget _buildExpanded(
    BuildContext context,
    PlaybackState state,
    Track track,
    double fullWidth,
  ) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return Semantics(
      button: true,
      label: '打开正在播放：${track.name}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openPlayer,
        child: SizedBox(
          height: _height,
          // 折叠动画期间 AnimatedCrossFade 会用收窄中的宽度约束隐藏侧的
          // 展开面板；这里强制按完整宽度布局，交给外层 ClipRect 裁剪，
          // 避免 Row 内固定尺寸内容触发 RenderFlex 溢出。
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: fullWidth,
            maxWidth: fullWidth,
            child: Padding(
              padding: const EdgeInsets.only(left: 10, right: 4),
              child: Row(
                children: [
                  TrackArtwork(track: track, size: 48, borderRadius: 10),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textStyles.body2.copyWith(
                            color: colors.onSurfaceContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          track.artists,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textStyles.body2.copyWith(
                            color: colors.onSurfaceVariantSummary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  MiuixIconButton(
                    enabled: !state.isLoading,
                    onPressed: widget.playback.togglePlay,
                    child: state.isLoading
                        ? const MiuixCircularProgressIndicator(
                            size: 18,
                            strokeWidth: 2,
                          )
                        : MiuixIcon(
                            vector: MiuixIcons.extended.byName(
                              state.isPlaying ? 'pause' : 'play',
                            )!,
                            size: 21,
                            tint: colors.onSurfaceContainer,
                          ),
                  ),
                  MiuixIconButton(
                    onPressed: widget.playback.playNext,
                    child: MiuixIcon(
                      vector: MiuixIcons.extended.byName('chevronForward')!,
                      size: 20,
                      tint: colors.onSurfaceContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
