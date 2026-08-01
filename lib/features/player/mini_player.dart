import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../application/audio_sources/audio_source_preferences_controller.dart';
import '../../application/auth/account_session_controller.dart';
import '../../application/playback/playback_controller.dart';
import '../../domain/models/track.dart';
import '../../domain/playback/playback_state.dart';
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
  });

  final PlaybackController playback;
  final AudioSourcePreferencesController audioSources;
  final AccountSessionController account;

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

  void _openPlayer() {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
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
