import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

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
                  crossAxisAlignment: CrossAxisAlignment.end,
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
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CapsuleButton(
          vector: MiuixIcons.extended.byName(
            'playlist',
            MiuixIconWeight.demibold,
          )!,
          iconSize: 25,
          tooltip: '播放列表',
          onPressed: () => QueueSheet.show(context, playback),
        ),
        _CapsuleButton(
          vector: MiuixIcons.extended.byName(
            lyricsVisible ? 'notesFill' : 'notes',
            MiuixIconWeight.demibold,
          )!,
          iconSize: 23,
          tooltip: lyricsVisible ? '关闭歌词面板' : '打开歌词面板',
          selected: lyricsVisible,
          onPressed: onToggleLyrics,
        ),
        _CapsuleButton(
          vector: MiuixIcons.extended.byName('info', MiuixIconWeight.demibold)!,
          iconSize: 23,
          selected: songInfoVisible,
          tooltip: '歌曲信息',
          onPressed: onSongInfo,
        ),
        _CapsuleButton(
          vector: MiuixIcons.extended.byName('tune', MiuixIconWeight.demibold)!,
          iconSize: 23,
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
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
      child: Row(
        children: [
          TrackArtwork(track: track, size: 52, borderRadius: 15),
          const SizedBox(width: 12),
          SizedBox(
            width: 150,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.body1.copyWith(
                    color: theme.colors.onSurfaceContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  track.artists,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.body2.copyWith(
                    color: theme.colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _CapsuleButton(
            icon: CupertinoIcons.backward_fill,
            iconSize: 24,
            tooltip: '上一首',
            onPressed: playback.playPrevious,
          ),
          _CapsuleButton(
            icon: state.isPlaying
                ? CupertinoIcons.pause_fill
                : CupertinoIcons.play_fill,
            iconSize: 29,
            tooltip: state.isPlaying ? '暂停' : '播放',
            emphasized: true,
            onPressed: state.isLoading ? null : playback.togglePlay,
          ),
          _CapsuleButton(
            icon: CupertinoIcons.forward_fill,
            iconSize: 24,
            tooltip: '下一首',
            onPressed: playback.playNext,
          ),
          const SizedBox(width: 8),
          Expanded(child: _SeekControl(playback: playback)),
          const SizedBox(width: 8),
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
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PlayerProgressTrack(
            value: displayValue,
            enabled: duration > Duration.zero,
            onChangeStart: (value) => setState(() => _dragValue = value),
            onChanged: (value) => setState(() => _dragValue = value),
            onChangeEnd: (value) {
              widget.playback.seek(duration * value);
              setState(() => _dragValue = null);
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ProgressTimeLabel(_time(displayPosition)),
                _ProgressTimeLabel('-${_time(duration - displayPosition)}'),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _PlayerProgressTrack extends StatefulWidget {
  const _PlayerProgressTrack({
    required this.value,
    required this.enabled,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double value;
  final bool enabled;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_PlayerProgressTrack> createState() => _PlayerProgressTrackState();
}

class _PlayerProgressTrackState extends State<_PlayerProgressTrack> {
  bool _hovered = false;
  bool _dragging = false;
  double? _pendingValue;

  double _valueFor(double dx, double width) =>
      width <= 0 ? 0 : (dx / width).clamp(0.0, 1.0).toDouble();

  @override
  Widget build(BuildContext context) {
    final value = widget.value.clamp(0.0, 1.0).toDouble();
    final showThumb = _hovered || _dragging;
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final thumbSize = showThumb ? 13.0 : 7.0;
          final thumbLeft = (width - thumbSize) * value;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: widget.enabled
                ? (details) {
                    final next = _valueFor(details.localPosition.dx, width);
                    widget.onChangeStart(next);
                    widget.onChangeEnd(next);
                  }
                : null,
            onHorizontalDragStart: widget.enabled
                ? (details) {
                    final next = _valueFor(details.localPosition.dx, width);
                    setState(() {
                      _dragging = true;
                      _pendingValue = next;
                    });
                    widget.onChangeStart(next);
                  }
                : null,
            onHorizontalDragUpdate: widget.enabled
                ? (details) {
                    final next = _valueFor(details.localPosition.dx, width);
                    _pendingValue = next;
                    widget.onChanged(next);
                  }
                : null,
            onHorizontalDragEnd: widget.enabled
                ? (_) {
                    widget.onChangeEnd(_pendingValue ?? widget.value);
                    setState(() {
                      _dragging = false;
                      _pendingValue = null;
                    });
                  }
                : null,
            child: SizedBox(
              height: 26,
              child: Stack(
                alignment: Alignment.centerLeft,
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: _hovered || _dragging ? 7 : 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .22),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: .08),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    width: width * value,
                    child: AnimatedContainer(
                      duration: _dragging
                          ? Duration.zero
                          : const Duration(milliseconds: 90),
                      height: _hovered || _dragging ? 7 : 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .92),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: .18),
                            blurRadius: 5,
                          ),
                        ],
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: _dragging
                        ? Duration.zero
                        : const Duration(milliseconds: 90),
                    curve: Curves.easeOutCubic,
                    left: thumbLeft,
                    width: thumbSize,
                    height: thumbSize,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.black.withValues(alpha: .14),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .26),
                            blurRadius: 7,
                            offset: const Offset(0, 2),
                          ),
                        ],
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

class _ProgressTimeLabel extends StatelessWidget {
  const _ProgressTimeLabel(this.value);

  final String value;

  @override
  Widget build(BuildContext context) => Text(
    value,
    style: TextStyle(
      color: Colors.white.withValues(alpha: .58),
      fontSize: 11,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
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
    final volumeIcon = MiuixIcons.extended.byName(
      volume <= 0 ? 'volumeOff' : 'volumeUp',
      MiuixIconWeight.demibold,
    )!;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: _hovered ? 210 : 56,
        child: _Capsule(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              if (_hovered) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _DragBar(
                    value: volume,
                    onChanged: widget.playback.setVolume,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              _CapsuleButton(
                vector: volumeIcon,
                iconSize: 23,
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
          height: 18,
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
    const trackHeight = 5.0;
    final trackRect = Rect.fromLTWH(
      0,
      (size.height - trackHeight) / 2,
      size.width,
      trackHeight,
    );
    final trackRadius = Radius.circular(trackHeight / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, trackRadius),
      Paint()..color = Colors.black.withValues(alpha: .10),
    );

    if (value <= 0) return;
    final activeRect = Rect.fromLTWH(
      trackRect.left,
      trackRect.top,
      trackRect.width * value,
      trackRect.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(activeRect, trackRadius),
      Paint()..color = Colors.black.withValues(alpha: .30),
    );

    final thumbCenter = Offset(activeRect.right, size.height / 2);
    canvas.drawCircle(
      thumbCenter,
      4.5,
      Paint()..color = Colors.black.withValues(alpha: .36),
    );
    canvas.drawCircle(
      thumbCenter,
      4.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: .22),
    );
  }

  @override
  bool shouldRepaint(_GlassTrackPainter oldDelegate) =>
      value != oldDelegate.value;
}

class _Capsule extends StatelessWidget {
  const _Capsule({required this.child, this.padding = const EdgeInsets.all(6)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .12),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: GlassContainer(
        shape: const LiquidRoundedSuperellipse(borderRadius: 999),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _CapsuleButton extends StatelessWidget {
  const _CapsuleButton({
    this.icon,
    this.vector,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.emphasized = false,
    this.iconSize = 22,
  }) : assert((icon == null) != (vector == null));
  final IconData? icon;
  final MiuixVectorIcon? vector;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final bool emphasized;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final tint = onPressed == null
        ? Colors.white.withValues(alpha: .25)
        : emphasized || selected
        ? Colors.white
        : Colors.white.withValues(alpha: .72);
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: AnimatedScale(
          scale: emphasized ? 1.04 : 1,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: MiuixIcon(
            icon: icon,
            vector: vector,
            size: iconSize,
            tint: tint,
          ),
        ),
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          hoverColor: Colors.white.withValues(alpha: .08),
          highlightColor: Colors.white.withValues(alpha: .13),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
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
