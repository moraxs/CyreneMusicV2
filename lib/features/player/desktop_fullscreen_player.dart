import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui show lerpDouble;
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../../application/audio_sources/audio_source_preferences_controller.dart';
import '../../application/auth/account_session_controller.dart';
import '../../application/playback/playback_controller.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';
import '../settings/equalizer_page.dart';
import 'classic_record_stage.dart';
import 'desktop_favorite_button.dart';
import 'mobile/compat/lyric_line.dart';
import 'mobile/compat/lyric_parser.dart';
import 'mobile/compat/player_service.dart';
import 'mobile/components/mobile_player_background.dart';
import 'mobile/components/mobile_player_fluid_cloud_lyric_panel.dart';
import 'mobile/components/mobile_player_fluid_cloud_song_wiki_panel.dart';
import 'mobile/components/mobile_player_song_comments.dart';
import 'queue_sheet.dart';
import 'track_artwork.dart';

/// 桌面端专用全屏播放器：左封面、右歌词、底部三段式悬浮胶囊。
class DesktopFullscreenPlayer extends StatefulWidget {
  const DesktopFullscreenPlayer({
    super.key,
    required this.playback,
    required this.audioSources,
    required this.account,
    required this.onSwitchToSuperCyrene,
  });

  final PlaybackController playback;
  final AudioSourcePreferencesController audioSources;
  final AccountSessionController account;
  final VoidCallback onSwitchToSuperCyrene;

  @override
  State<DesktopFullscreenPlayer> createState() =>
      _DesktopFullscreenPlayerState();
}

class _DesktopFullscreenPlayerState extends State<DesktopFullscreenPlayer>
    with WindowListener {
  bool _showLyrics = true;
  bool _showSongInfoPanel = false;
  bool _titleBarVisible = false;
  bool _isMaximized = false;
  Timer? _titleBarHideTimer;
  List<LyricLine> _lyrics = const [];
  int _currentLyricIndex = -1;
  Object? _lastTrack;

  @override
  void initState() {
    super.initState();
    PlayerService().bind(
      widget.playback,
      accountController: widget.account,
      audioSourcesController: widget.audioSources,
    );
    _lastTrack = widget.playback.state.currentTrack;
    _loadLyrics();
    windowManager.addListener(this);
    _syncMaximizedState();
    widget.playback.addListener(_onPlaybackChanged);
    widget.playback.positionListenable.addListener(_updateLyricIndex);
  }

  @override
  void dispose() {
    _titleBarHideTimer?.cancel();
    windowManager.removeListener(this);
    widget.playback.removeListener(_onPlaybackChanged);
    widget.playback.positionListenable.removeListener(_updateLyricIndex);
    super.dispose();
  }

  @override
  void onWindowMaximize() => _setMaximized(true);

  @override
  void onWindowUnmaximize() => _setMaximized(false);

  Future<void> _syncMaximizedState() async {
    _setMaximized(await windowManager.isMaximized());
  }

  void _setMaximized(bool value) {
    if (!mounted || _isMaximized == value) return;
    setState(() => _isMaximized = value);
  }

  void _showTitleBar() {
    _titleBarHideTimer?.cancel();
    if (!_titleBarVisible) setState(() => _titleBarVisible = true);
  }

  void _scheduleTitleBarHide() {
    _titleBarHideTimer?.cancel();
    _titleBarHideTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _titleBarVisible = false);
    });
  }

  void _onPlaybackChanged() {
    final track = widget.playback.state.currentTrack;
    if (!identical(track, _lastTrack)) {
      _lastTrack = track;
      _loadLyrics();
    }
  }

  void _loadLyrics() {
    final track = widget.playback.state.currentTrack;
    if (track == null || track.lyric?.isNotEmpty != true) {
      if (mounted) setState(() => _lyrics = const []);
      return;
    }
    final parsed = LyricParser.parseNeteaseLyric(
      track.lyric!,
      translation: track.tlyric,
      yrcLyric: track.yrc,
      yrcTranslation: track.ytlrc,
      romaji: track.romaji,
    );
    if (!mounted) return;
    setState(() {
      _lyrics = parsed;
      _currentLyricIndex = LyricParser.findCurrentLineIndex(
        parsed,
        widget.playback.positionListenable.value,
      );
    });
  }

  void _updateLyricIndex() {
    if (_lyrics.isEmpty || !mounted) return;
    final next = LyricParser.findCurrentLineIndex(
      _lyrics,
      widget.playback.positionListenable.value,
    );
    if (next != _currentLyricIndex) {
      setState(() => _currentLyricIndex = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.playback,
      builder: (context, _) {
        final state = widget.playback.state;
        final track = state.currentTrack;
        final colors = MiuixTheme.of(context).colors;
        if (track == null) {
          return Material(
            color: colors.background,
            child: const Center(child: Text('还没有选择歌曲')),
          );
        }

        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              const Positioned.fill(
                child: MobilePlayerBackground(isolateRepaints: false),
              ),
              Positioned.fill(
                bottom: 112,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1700),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(56, 62, 56, 20),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final recordSize = math
                              .min(
                                520.0,
                                math.min(
                                  constraints.maxWidth *
                                      (_showLyrics ? .34 : .48),
                                  constraints.maxHeight * .78,
                                ),
                              )
                              .clamp(240.0, 520.0)
                              .toDouble();
                          return Row(
                            children: [
                              Expanded(
                                flex: _showLyrics ? 45 : 10,
                                child: ClassicRecordStage(
                                  track: track,
                                  size: recordSize,
                                  isPlaying: state.isPlaying,
                                ),
                              ),
                              if (_showLyrics) ...[
                                SizedBox(
                                  width: constraints.maxWidth > 1200 ? 56 : 28,
                                ),
                                Expanded(
                                  flex: 55,
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      left: constraints.maxWidth > 1200
                                          ? 24
                                          : 0,
                                      right: constraints.maxWidth > 1200
                                          ? 36
                                          : 0,
                                    ),
                                    child: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 320,
                                      ),
                                      switchInCurve: Curves.easeOutCubic,
                                      switchOutCurve: Curves.easeInCubic,
                                      transitionBuilder: (child, animation) =>
                                          FadeTransition(
                                            opacity: animation,
                                            child: SlideTransition(
                                              position: Tween<Offset>(
                                                begin: const Offset(.035, 0),
                                                end: Offset.zero,
                                              ).animate(animation),
                                              child: child,
                                            ),
                                          ),
                                      child: _showSongInfoPanel
                                          ? _DesktopSongInfoPanel(
                                              key: ValueKey('song-info'),
                                              track: track,
                                            )
                                          : MobilePlayerFluidCloudLyricsPanel(
                                              key: const ValueKey('lyrics'),
                                              lyrics: _lyrics,
                                              currentLyricIndex:
                                                  _currentLyricIndex,
                                              showTranslation: true,
                                              showRomaji: true,
                                              visibleLineCount: 7,
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 32,
                child: MouseRegion(
                  onEnter: (_) => _showTitleBar(),
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !_titleBarVisible,
                  child: AnimatedSlide(
                    offset: _titleBarVisible
                        ? Offset.zero
                        : const Offset(0, -1),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: _titleBarVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOut,
                      child: MouseRegion(
                        onEnter: (_) => _showTitleBar(),
                        onExit: (_) => _scheduleTitleBarHide(),
                        child: _FullscreenTitleBar(
                          title: track.name.isEmpty
                              ? 'Cyrene Player'
                              : track.name,
                          isMaximized: _isMaximized,
                          onSwitchToSuperCyrene: widget.onSwitchToSuperCyrene,
                          onExitFullscreen: () => Navigator.of(context).pop(),
                          onMinimize: windowManager.minimize,
                          onToggleMaximize: () => _isMaximized
                              ? windowManager.unmaximize()
                              : windowManager.maximize(),
                          onClose: windowManager.close,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 28,
                right: 28,
                bottom: 24,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _UtilityCapsule(
                      playback: widget.playback,
                      lyricsVisible: _showLyrics && !_showSongInfoPanel,
                      songInfoVisible: _showLyrics && _showSongInfoPanel,
                      onToggleLyrics: () => setState(() {
                        if (_showSongInfoPanel || !_showLyrics) {
                          _showSongInfoPanel = false;
                          _showLyrics = true;
                        } else {
                          _showLyrics = false;
                        }
                      }),
                      onSongInfo: () => setState(() {
                        if (_showLyrics && _showSongInfoPanel) {
                          _showLyrics = false;
                          _showSongInfoPanel = false;
                        } else {
                          _showLyrics = true;
                          _showSongInfoPanel = true;
                        }
                      }),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _MainCapsule(
                        playback: widget.playback,
                        account: widget.account,
                      ),
                    ),
                    const SizedBox(width: 16),
                    _ExpandableVolume(playback: widget.playback),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Hover-revealed window bar matching SuperCyreneFullscreen.tsx. The buttons
/// intentionally stay outside [DragToMoveArea], while the title and all
/// remaining horizontal space form one uninterrupted native drag region.
class _FullscreenTitleBar extends StatelessWidget {
  const _FullscreenTitleBar({
    required this.title,
    required this.isMaximized,
    required this.onSwitchToSuperCyrene,
    required this.onExitFullscreen,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
  });

  final String title;
  final bool isMaximized;
  final VoidCallback onSwitchToSuperCyrene;
  final VoidCallback onExitFullscreen;
  final VoidCallback onMinimize;
  final VoidCallback onToggleMaximize;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Container(
        height: 52,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xA6000000),
              Color(0x59000000),
              Color(0x1A000000),
              Colors.transparent,
            ],
            stops: [0, .4, .72, 1],
          ),
        ),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              const SizedBox(width: 16),
              _FullscreenCaptionButton(
                icon: CupertinoIcons.chevron_down,
                iconSize: 18,
                tooltip: '折叠全屏播放器',
                onPressed: onExitFullscreen,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: DragToMoveArea(
                  child: Container(
                    height: 44,
                    color: Colors.transparent,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .3),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.05,
                      ),
                    ),
                  ),
                ),
              ),
              _FullscreenCaptionButton(
                icon: Icons.auto_awesome_rounded,
                iconSize: 15,
                tooltip: '切换到 SuperCyrene 播放器',
                onPressed: onSwitchToSuperCyrene,
              ),
              const _TitleBarDivider(),
              _FullscreenCaptionButton(
                icon: CupertinoIcons.minus,
                tooltip: '最小化窗口',
                onPressed: onMinimize,
              ),
              _FullscreenCaptionButton(
                icon: isMaximized
                    ? CupertinoIcons.square_on_square
                    : CupertinoIcons.square,
                iconSize: isMaximized ? 13 : 11,
                tooltip: isMaximized ? '还原窗口' : '最大化窗口',
                onPressed: onToggleMaximize,
              ),
              _FullscreenCaptionButton(
                icon: CupertinoIcons.xmark,
                tooltip: '关闭窗口',
                closeButton: true,
                onPressed: onClose,
              ),
              const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TitleBarDivider extends StatelessWidget {
  const _TitleBarDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 12,
    margin: const EdgeInsets.symmetric(horizontal: 3),
    color: Colors.white.withValues(alpha: .1),
  );
}

class _FullscreenCaptionButton extends StatelessWidget {
  const _FullscreenCaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 15,
    this.closeButton = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double iconSize;
  final bool closeButton;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: iconSize),
      color: Colors.white.withValues(alpha: .3),
      style: IconButton.styleFrom(
        fixedSize: const Size(30, 30),
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        hoverColor: closeButton
            ? Colors.red.withValues(alpha: .6)
            : Colors.white.withValues(alpha: .1),
        highlightColor: closeButton
            ? Colors.red.withValues(alpha: .75)
            : Colors.white.withValues(alpha: .15),
      ),
    ),
  );
}

/// Desktop counterpart of the Next.js SongInfoPanel. Netease tracks use the
/// complete wiki page; other sources still keep their basic metadata in the
/// same right-hand panel instead of falling back to a dialog.
class _DesktopSongInfoPanel extends StatelessWidget {
  const _DesktopSongInfoPanel({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    if (track.source == MusicSource.netease) {
      return const MobilePlayerFluidCloudSongWikiPanel();
    }

    return ListView(
      key: ValueKey(track.key),
      padding: const EdgeInsets.fromLTRB(20, 34, 20, 72),
      children: [
        Text(
          track.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          track.artists,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .68),
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (track.album.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.album_outlined,
                size: 16,
                color: Colors.white.withValues(alpha: .5),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  track.album,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .5),
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 32),
        _SongInfoMetaCard(track: track),
        if (track.source == MusicSource.qq) ...[
          const SizedBox(height: 30),
          MobilePlayerSongComments(track: track),
        ],
      ],
    );
  }
}

class _SongInfoMetaCard extends StatelessWidget {
  const _SongInfoMetaCard({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: .08)),
    ),
    child: Wrap(
      spacing: 32,
      runSpacing: 18,
      children: [
        _meta('音源', track.source.wireName.toUpperCase()),
        if (track.duration != null) _meta('时长', _time(track.duration!)),
        _meta('歌曲 ID', track.id),
      ],
    ),
  );

  Widget _meta(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: .42),
          fontSize: 12,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _UtilityCapsule extends StatelessWidget {
  const _UtilityCapsule({
    required this.playback,
    required this.lyricsVisible,
    required this.songInfoVisible,
    required this.onToggleLyrics,
    required this.onSongInfo,
  });

  final PlaybackController playback;
  final bool lyricsVisible;
  final bool songInfoVisible;
  final VoidCallback onToggleLyrics;
  final VoidCallback onSongInfo;

  @override
  Widget build(BuildContext context) => _Capsule(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _CapsuleButton(
          icon: Icons.queue_music_rounded,
          iconSize: 22,
          tooltip: '播放列表',
          onPressed: () => QueueSheet.show(context, playback),
        ),
        const SizedBox(width: 6),
        _CapsuleButton(
          icon: lyricsVisible
              ? CupertinoIcons.quote_bubble_fill
              : CupertinoIcons.quote_bubble,
          iconSize: 20,
          tooltip: lyricsVisible ? '关闭歌词面板' : '打开歌词面板',
          selected: lyricsVisible,
          onPressed: onToggleLyrics,
        ),
        const SizedBox(width: 6),
        _CapsuleButton(
          icon: songInfoVisible
              ? CupertinoIcons.info_circle_fill
              : CupertinoIcons.info_circle,
          iconSize: 21,
          selected: songInfoVisible,
          tooltip: '歌曲信息',
          onPressed: onSongInfo,
        ),
        const SizedBox(width: 6),
        _CapsuleButton(
          icon: Icons.tune_rounded,
          iconSize: 21,
          tooltip: '均衡器',
          onPressed: () => Navigator.of(context).push(
            CupertinoPageRoute<void>(builder: (_) => const EqualizerPage()),
          ),
        ),
      ],
    ),
  );
}



class _MainCapsule extends StatelessWidget {
  const _MainCapsule({required this.playback, required this.account});

  final PlaybackController playback;
  final AccountSessionController account;

  @override
  Widget build(BuildContext context) {
    final state = playback.state;
    final track = state.currentTrack!;
    final theme = MiuixTheme.of(context);
    return _Capsule(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TrackArtwork(track: track, size: 50, borderRadius: 14),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 90, maxWidth: 170),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.body1.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  track.artists,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.body2.copyWith(
                    color: Colors.white.withValues(alpha: .6),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _CapsuleButton(
            icon: CupertinoIcons.backward_fill,
            iconSize: 22,
            tooltip: '上一首',
            onPressed: playback.playPrevious,
          ),
          const SizedBox(width: 2),
          _CapsuleButton(
            icon: state.isPlaying
                ? CupertinoIcons.pause_fill
                : CupertinoIcons.play_fill,
            iconSize: 28,
            tooltip: state.isPlaying ? '暂停' : '播放',
            emphasized: true,
            onPressed: state.isLoading ? null : playback.togglePlay,
          ),
          const SizedBox(width: 2),
          _CapsuleButton(
            icon: CupertinoIcons.forward_fill,
            iconSize: 22,
            tooltip: '下一首',
            onPressed: playback.playNext,
          ),
          const SizedBox(width: 12),
          Expanded(child: _SeekControl(playback: playback)),
          const SizedBox(width: 10),
          DesktopFavoriteButton(
            playback: playback,
            account: account,
          ),
        ],
      ),
    );
  }
}

class _SeekControl extends StatefulWidget {
  const _SeekControl({required this.playback});
  final PlaybackController playback;

  @override
  State<_SeekControl> createState() => _SeekControlState();
}

class _SeekControlState extends State<_SeekControl> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Duration>(
    valueListenable: widget.playback.positionListenable,
    builder: (context, position, _) {
      final duration = widget.playback.state.duration;
      final fraction = duration.inMilliseconds <= 0
          ? 0.0
          : (position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0)
                .toDouble();
      final displayValue = _dragValue ?? fraction;
      final displayPosition = Duration(
        milliseconds: (duration.inMilliseconds * displayValue).round(),
      );
      final remaining = duration > displayPosition
          ? duration - displayPosition
          : Duration.zero;

      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ProgressTimeLabel(_time(displayPosition)),
          const SizedBox(width: 10),
          Expanded(
            child: _ModernProgressBar(
              value: displayValue,
              duration: duration,
              enabled: duration > Duration.zero,
              onChangeStart: (value) => setState(() => _dragValue = value),
              onChanged: (value) => setState(() => _dragValue = value),
              onChangeEnd: (value) {
                widget.playback.seek(duration * value);
                setState(() => _dragValue = null);
              },
            ),
          ),
          const SizedBox(width: 10),
          _ProgressTimeLabel('-${_time(remaining)}'),
        ],
      );
    },
  );
}

class _ModernProgressBar extends StatefulWidget {
  const _ModernProgressBar({
    required this.value,
    required this.duration,
    required this.enabled,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double value;
  final Duration duration;
  final bool enabled;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_ModernProgressBar> createState() => _ModernProgressBarState();
}

class _ModernProgressBarState extends State<_ModernProgressBar>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  bool _dragging = false;
  double? _hoverFraction;
  double? _dragFraction;

  late final AnimationController _animController;
  late final Animation<double> _hoverAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _hoverAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  double _calcFraction(double dx, double width) {
    if (width <= 0) return 0.0;
    return (dx / width).clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final activeFraction = (_dragFraction ?? widget.value).clamp(0.0, 1.0).toDouble();

    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) {
        if (!widget.enabled) return;
        setState(() => _hovered = true);
        _animController.forward();
      },
      onExit: (_) {
        setState(() {
          _hovered = false;
          _hoverFraction = null;
        });
        if (!_dragging) {
          _animController.reverse();
        }
      },
      onHover: (event) {
        if (!widget.enabled) return;
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        final width = box.size.width;
        final frac = _calcFraction(event.localPosition.dx, width);
        if (_hoverFraction != frac) {
          setState(() => _hoverFraction = frac);
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final hoverFrac = _hoverFraction;
          final hoverTime = (hoverFrac != null && widget.duration > Duration.zero)
              ? Duration(
                  milliseconds:
                      (widget.duration.inMilliseconds * hoverFrac).round(),
                )
              : null;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: widget.enabled
                ? (details) {
                    final next = _calcFraction(details.localPosition.dx, width);
                    widget.onChangeStart(next);
                    widget.onChangeEnd(next);
                  }
                : null,
            onHorizontalDragStart: widget.enabled
                ? (details) {
                    final next = _calcFraction(details.localPosition.dx, width);
                    setState(() {
                      _dragging = true;
                      _dragFraction = next;
                    });
                    _animController.forward();
                    widget.onChangeStart(next);
                  }
                : null,
            onHorizontalDragUpdate: widget.enabled
                ? (details) {
                    final next = _calcFraction(details.localPosition.dx, width);
                    setState(() {
                      _dragFraction = next;
                      _hoverFraction = next;
                    });
                    widget.onChanged(next);
                  }
                : null,
            onHorizontalDragEnd: widget.enabled
                ? (_) {
                    final endValue = _dragFraction ?? widget.value;
                    widget.onChangeEnd(endValue);
                    setState(() {
                      _dragging = false;
                      _dragFraction = null;
                    });
                    if (!_hovered) {
                      _animController.reverse();
                    }
                  }
                : null,
            child: SizedBox(
              height: 36,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _hoverAnim,
                      builder: (context, _) => CustomPaint(
                        painter: _ModernProgressPainter(
                          value: activeFraction,
                          hoverFraction: _hoverFraction,
                          hoverProgress: _hoverAnim.value,
                        ),
                      ),
                    ),
                  ),
                  if (hoverTime != null && (_hovered || _dragging))
                    Positioned(
                      top: -2,
                      left: (width * (hoverFrac ?? 0.0) - 22).clamp(
                        0.0,
                        math.max(0.0, width - 44.0),
                      ),
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: _hoverAnim.value,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xEB1A1C23),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                                width: 0.8,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Text(
                              _time(hoverTime),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                fontFeatures: [FontFeature.tabularFigures()],
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ModernProgressPainter extends CustomPainter {
  const _ModernProgressPainter({
    required this.value,
    required this.hoverFraction,
    required this.hoverProgress,
  });

  final double value;
  final double? hoverFraction;
  final double hoverProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final trackHeight = ui.lerpDouble(4.0, 6.0, hoverProgress)!;
    final trackTop = (size.height - trackHeight) / 2;
    final trackRect = Rect.fromLTWH(0, trackTop, size.width, trackHeight);
    final trackRRect = RRect.fromRectAndRadius(
      trackRect,
      Radius.circular(trackHeight / 2),
    );

    // 1. 底轨
    final bgPaint = Paint()
      ..color = Colors.white.withValues(
        alpha: ui.lerpDouble(0.16, 0.22, hoverProgress)!,
      );
    canvas.drawRRect(trackRRect, bgPaint);

    // 2. 悬停幽灵预览轨
    if (hoverFraction != null && hoverProgress > 0) {
      final hFrac = hoverFraction!.clamp(0.0, 1.0);
      final ghostWidth = size.width * hFrac;
      if (ghostWidth > 0) {
        final ghostRect = Rect.fromLTWH(0, trackTop, ghostWidth, trackHeight);
        canvas.save();
        canvas.clipRRect(trackRRect);
        canvas.drawRect(
          ghostRect,
          Paint()..color = Colors.white.withValues(alpha: 0.14 * hoverProgress),
        );
        canvas.restore();
      }
    }

    // 3. 已播放进度轨
    final clampedVal = value.clamp(0.0, 1.0);
    final activeWidth = size.width * clampedVal;
    if (activeWidth > 0) {
      final activeRect = Rect.fromLTWH(0, trackTop, activeWidth, trackHeight);
      canvas.save();
      canvas.clipRRect(trackRRect);
      final activePaint = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.95),
            Colors.white,
          ],
        ).createShader(activeRect);
      canvas.drawRect(activeRect, activePaint);
      canvas.restore();
    }

    // 4. 滑块 (Thumb)
    final thumbRadius = ui.lerpDouble(0.0, 5.5, hoverProgress)!;
    if (thumbRadius > 0.5) {
      final thumbCenter = Offset(
        activeWidth.clamp(thumbRadius, size.width - thumbRadius),
        size.height / 2,
      );

      canvas.drawCircle(
        thumbCenter + const Offset(0, 1.5),
        thumbRadius,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.28 * hoverProgress)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
      );

      canvas.drawCircle(
        thumbCenter,
        thumbRadius,
        Paint()..color = Colors.white,
      );

      canvas.drawCircle(
        thumbCenter,
        thumbRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = Colors.white.withValues(alpha: 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ModernProgressPainter oldDelegate) =>
      value != oldDelegate.value ||
      hoverFraction != oldDelegate.hoverFraction ||
      hoverProgress != oldDelegate.hoverProgress;
}

class _ProgressTimeLabel extends StatelessWidget {
  const _ProgressTimeLabel(this.value);

  final String value;

  @override
  Widget build(BuildContext context) => Text(
    value,
    style: TextStyle(
      color: Colors.white.withValues(alpha: .6),
      fontSize: 11.5,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
      letterSpacing: 0.2,
    ),
  );
}

class _ExpandableVolume extends StatefulWidget {
  const _ExpandableVolume({required this.playback});
  final PlaybackController playback;

  @override
  State<_ExpandableVolume> createState() => _ExpandableVolumeState();
}

class _ExpandableVolumeState extends State<_ExpandableVolume> {
  bool _hovered = false;
  double _lastVolume = .8;

  @override
  Widget build(BuildContext context) {
    final volume = widget.playback.state.volume;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: _hovered ? 210 : 64,
        child: _Capsule(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              if (_hovered) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: _DragBar(
                    value: volume,
                    onChanged: widget.playback.setVolume,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              _CapsuleButton(
                icon: volume <= 0
                    ? CupertinoIcons.volume_off
                    : (volume < 0.5
                        ? CupertinoIcons.volume_down
                        : CupertinoIcons.volume_up),
                iconSize: 21,
                tooltip: volume <= 0 ? '取消静音' : '静音',
                onPressed: () {
                  if (volume > 0) {
                    _lastVolume = volume;
                    widget.playback.setVolume(0);
                  } else {
                    widget.playback.setVolume(_lastVolume);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DragBar extends StatelessWidget {
  const _DragBar({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => onChanged(
          (d.localPosition.dx / constraints.maxWidth)
              .clamp(0.0, 1.0)
              .toDouble(),
        ),
        onHorizontalDragUpdate: (d) => onChanged(
          (d.localPosition.dx / constraints.maxWidth)
              .clamp(0.0, 1.0)
              .toDouble(),
        ),
        child: SizedBox(
          height: 24,
          child: CustomPaint(
            painter: _GlassTrackPainter(
              value: value.clamp(0.0, 1.0).toDouble(),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassTrackPainter extends CustomPainter {
  const _GlassTrackPainter({required this.value});

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    const trackHeight = 4.5;
    final trackTop = (size.height - trackHeight) / 2;
    final trackRect = Rect.fromLTWH(0, trackTop, size.width, trackHeight);
    final trackRRect = RRect.fromRectAndRadius(
      trackRect,
      const Radius.circular(trackHeight / 2),
    );

    // 背景底轨
    canvas.drawRRect(
      trackRRect,
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );

    if (value <= 0) return;

    // 激活轨
    final activeWidth = size.width * value;
    final activeRect = Rect.fromLTWH(0, trackTop, activeWidth, trackHeight);
    canvas.save();
    canvas.clipRRect(trackRRect);
    canvas.drawRect(
      activeRect,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    canvas.restore();

    // 滑块
    final thumbCenter = Offset(
      activeWidth.clamp(4.5, size.width - 4.5),
      size.height / 2,
    );
    canvas.drawCircle(
      thumbCenter + const Offset(0, 1),
      4.5,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    canvas.drawCircle(
      thumbCenter,
      4.5,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      thumbCenter,
      4.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(_GlassTrackPainter oldDelegate) =>
      value != oldDelegate.value;
}

class _Capsule extends StatelessWidget {
  const _Capsule({
    required this.child,
    this.padding = const EdgeInsets.all(6),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .14),
            blurRadius: 24,
            spreadRadius: -2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: GlassContainer(
        shape: const LiquidRoundedSuperellipse(borderRadius: 999),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 64,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}


class _CapsuleButton extends StatefulWidget {
  const _CapsuleButton({
    this.icon,
    this.vector,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.emphasized = false,
    this.iconSize = 20,
  }) : assert((icon == null) != (vector == null));

  final IconData? icon;
  final MiuixVectorIcon? vector;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final bool emphasized;
  final double iconSize;

  @override
  State<_CapsuleButton> createState() => _CapsuleButtonState();
}

class _CapsuleButtonState extends State<_CapsuleButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final selected = widget.selected;
    final emphasized = widget.emphasized;
    final buttonSize = emphasized ? 48.0 : 44.0;


    final Color backgroundColor;
    final Border? border;
    final List<BoxShadow>? shadows;

    if (!enabled) {
      backgroundColor = Colors.transparent;
      border = null;
      shadows = null;
    } else if (selected) {
      backgroundColor = Colors.white.withValues(alpha: _hovered ? 0.28 : 0.22);
      border = Border.all(
        color: Colors.white.withValues(alpha: 0.35),
        width: 0.8,
      );
      shadows = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.18),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];
    } else if (emphasized) {
      backgroundColor = Colors.white.withValues(alpha: _hovered ? 0.24 : 0.16);
      border = Border.all(
        color: Colors.white.withValues(alpha: _hovered ? 0.32 : 0.20),
        width: 0.8,
      );
      shadows = [
        BoxShadow(
          color: Colors.white.withValues(alpha: _hovered ? 0.15 : 0.08),
          blurRadius: 10,
        ),
      ];
    } else if (_hovered) {
      backgroundColor = Colors.white.withValues(alpha: 0.12);
      border = Border.all(
        color: Colors.white.withValues(alpha: 0.18),
        width: 0.8,
      );
      shadows = null;
    } else {
      backgroundColor = Colors.transparent;
      border = null;
      shadows = null;
    }

    final Color iconColor;
    if (!enabled) {
      iconColor = Colors.white.withValues(alpha: 0.25);
    } else if (selected || emphasized) {
      iconColor = Colors.white;
    } else if (_hovered) {
      iconColor = Colors.white.withValues(alpha: 0.95);
    } else {
      iconColor = Colors.white.withValues(alpha: 0.68);
    }

    final double scale;
    if (_pressed) {
      scale = 0.92;
    } else if (_hovered) {
      scale = emphasized ? 1.06 : 1.04;
    } else {
      scale = emphasized ? 1.02 : 1.0;
    }

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: buttonSize,
            height: buttonSize,

            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
              border: border,
              boxShadow: shadows,
            ),
            child: Center(
              child: AnimatedScale(
                scale: scale,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                child: widget.icon != null
                    ? Icon(
                        widget.icon,
                        size: widget.iconSize,
                        color: iconColor,
                      )
                    : MiuixIcon(
                        vector: widget.vector,
                        size: widget.iconSize,
                        tint: iconColor,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


String _time(Duration value) {
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
