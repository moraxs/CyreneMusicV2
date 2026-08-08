import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_svg/flutter_svg.dart';

import '../../../application/auth/account_session_controller.dart';
import '../../../application/playback/playback_controller.dart';
import '../../../domain/models/track.dart';
import '../../../domain/playback/repeat_mode.dart';
import '../../../infrastructure/services/playlist_service.dart';
import '../../../presentation/cyrene/cyrene_toast.dart';
import '../desktop_fullscreen_player_route.dart';
import '../fullscreen/add_to_playlist_sheet.dart';
import 'super_cyrene_song_gallery.dart';

class SuperCyreneControlPanel extends StatefulWidget {
  const SuperCyreneControlPanel({
    super.key,
    required this.playback,
    required this.account,
    required this.track,
    required this.cover,
    required this.chatLyrics,
    required this.onChatLyricsChanged,
  });

  final PlaybackController playback;
  final AccountSessionController account;
  final Track? track;
  final ImageProvider? cover;
  final bool chatLyrics;
  final ValueChanged<bool> onChatLyricsChanged;

  @override
  State<SuperCyreneControlPanel> createState() =>
      _SuperCyreneControlPanelState();
}

class _SuperCyreneControlPanelState extends State<SuperCyreneControlPanel> {
  bool _open = false;
  bool _hoveringLauncher = false;
  List<int> _playlistIds = const [];
  int _favoriteRequest = 0;

  @override
  void initState() {
    super.initState();
    _refreshFavorite();
  }

  @override
  void didUpdateWidget(covariant SuperCyreneControlPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track?.key != widget.track?.key ||
        oldWidget.account.token != widget.account.token) {
      _refreshFavorite();
    }
  }

  Future<void> _refreshFavorite() async {
    final request = ++_favoriteRequest;
    final track = widget.track;
    final token = widget.account.token;
    if (track == null || token == null) {
      if (mounted) setState(() => _playlistIds = const []);
      return;
    }
    final result = await PlaylistService.instance.checkTrackInPlaylists(
      token,
      track.id,
      track.source.wireName,
    );
    if (!mounted || request != _favoriteRequest) return;
    setState(() => _playlistIds = result.playlistIds);
  }

  Future<void> _toggleFavorite() async {
    final track = widget.track;
    if (track == null) return;
    final token = widget.account.token;
    if (token == null) {
      CyreneToast.show('请先登录后再收藏');
      return;
    }
    if (_playlistIds.length == 1) {
      final ok = await PlaylistService.instance.removeTrackFromPlaylist(
        token,
        _playlistIds.first,
        track.id,
        track.source.wireName,
      );
      CyreneToast.show(ok ? '已从歌单中移除' : '从歌单移除失败');
      if (ok) await _refreshFavorite();
      return;
    }
    final changed = await AddToPlaylistSheet.show(
      context,
      token: token,
      track: track,
      showOnlyJoinedInitially: _playlistIds.isNotEmpty,
    );
    if (changed == true) await _refreshFavorite();
  }

  RepeatMode _nextRepeat(RepeatMode mode) => switch (mode) {
    RepeatMode.all => RepeatMode.one,
    RepeatMode.one => RepeatMode.shuffle,
    RepeatMode.shuffle || RepeatMode.off => RepeatMode.all,
  };

  @override
  Widget build(BuildContext context) {
    final activeLauncher = _open || _hoveringLauncher;
    return SizedBox(
      width: 256,
      height: 560,
      child: Stack(
        alignment: Alignment.bottomLeft,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            bottom: 64,
            child: IgnorePointer(
              ignoring: !_open,
              child: AnimatedSlide(
                offset: _open ? Offset.zero : const Offset(0, .035),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                child: AnimatedScale(
                  scale: _open ? 1 : .98,
                  alignment: Alignment.bottomLeft,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: _open ? 1 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: _Panel(
                      playback: widget.playback,
                      track: widget.track,
                      cover: widget.cover,
                      favorite: _playlistIds.isNotEmpty,
                      chatLyrics: widget.chatLyrics,
                      onChatLyricsChanged: widget.onChatLyricsChanged,
                      onClose: () => setState(() => _open = false),
                      onFavorite: _toggleFavorite,
                      onQueue: () => Navigator.of(context, rootNavigator: true)
                          .push(
                        DesktopFullscreenPlayerRoute(
                          builder: (_) => SuperCyreneSongGallery(
                            playback: widget.playback,
                            account: widget.account,
                          ),
                        ),
                      ),
                      onRepeat: () {
                        final mode = widget.playback.state.repeatMode;
                        widget.playback.setRepeatMode(_nextRepeat(mode));
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          MouseRegion(
            onEnter: (_) => setState(() => _hoveringLauncher = true),
            onExit: (_) => setState(() => _hoveringLauncher = false),
            child: AnimatedSlide(
              offset: !_open && _hoveringLauncher
                  ? const Offset(0, -.04)
                  : Offset.zero,
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: () => setState(() => _open = !_open),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _open
                        ? Colors.white.withValues(alpha: .12)
                        : activeLauncher
                        ? Colors.white.withValues(alpha: .08)
                        : Colors.black.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(
                        alpha: activeLauncher ? .30 : .15,
                      ),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x59000000),
                        blurRadius: 40,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: const Icon(
                        Icons.music_note_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.playback,
    required this.track,
    required this.cover,
    required this.favorite,
    required this.chatLyrics,
    required this.onChatLyricsChanged,
    required this.onClose,
    required this.onFavorite,
    required this.onQueue,
    required this.onRepeat,
  });

  final PlaybackController playback;
  final Track? track;
  final ImageProvider? cover;
  final bool favorite;
  final bool chatLyrics;
  final ValueChanged<bool> onChatLyricsChanged;
  final VoidCallback onClose;
  final VoidCallback onFavorite;
  final VoidCallback onQueue;
  final VoidCallback onRepeat;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
      child: Container(
        width: 256,
        decoration: BoxDecoration(
          // Keep the tint light enough for the live AMLL colors to remain
          // visible through the frosted backdrop.
          color: Colors.black.withValues(alpha: .20),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .10)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x73000000),
              blurRadius: 70,
              offset: Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Artwork(track: track, cover: cover, onClose: onClose),
            _SongInfo(track: track),
            _LyricsThemeRow(
              chatLyrics: chatLyrics,
              onChanged: onChatLyricsChanged,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: _PanelProgress(playback: playback),
            ),
            _Transport(playback: playback),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: .05)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      _SmallButton(
                        icon: Icons.queue_music_rounded,
                        onTap: onQueue,
                      ),
                      const SizedBox(width: 4),
                      _SmallButton(
                        icon: favorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: favorite
                            ? const Color(0xFFF87171)
                            : Colors.white.withValues(alpha: .25),
                        onTap: onFavorite,
                      ),
                      const SizedBox(width: 4),
                      _RepeatButton(playback: playback, onTap: onRepeat),
                    ],
                  ),
                  _VolumeControl(playback: playback),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.track,
    required this.cover,
    required this.onClose,
  });
  final Track? track;
  final ImageProvider? cover;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 256,
    height: 256,
    child: Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Colors.white.withValues(alpha: .05),
          child: cover == null
              ? Icon(
                  Icons.music_note_rounded,
                  size: 48,
                  color: Colors.white.withValues(alpha: .15),
                )
              : Image(image: cover!, fit: BoxFit.cover),
        ),
        const Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: 64,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xB3000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: _RoundHoverButton(
            size: 28,
            icon: Icons.close_rounded,
            iconSize: 14,
            onTap: onClose,
          ),
        ),
      ],
    ),
  );
}

class _SongInfo extends StatelessWidget {
  const _SongInfo({required this.track});
  final Track? track;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          track?.name ?? '未在播放',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: -.15,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          track == null
              ? '选择一首歌曲开始播放'
              : '${track!.artists}${track!.album.isEmpty ? '' : ' · ${track!.album}'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .40),
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
}

class _LyricsThemeRow extends StatelessWidget {
  const _LyricsThemeRow({required this.chatLyrics, required this.onChanged});

  final bool chatLyrics;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 36,
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    padding: const EdgeInsets.only(left: 8, right: 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .035),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: .08)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '歌词',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .35),
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.4,
          ),
        ),
        PopupMenuButton<bool>(
          initialValue: chatLyrics,
          onSelected: onChanged,
          color: const Color(0xE6141418),
          elevation: 16,
          position: PopupMenuPosition.under,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
            side: BorderSide(color: Colors.white.withValues(alpha: .10)),
          ),
          itemBuilder: (context) => const [
            PopupMenuItem(value: false, height: 34, child: Text('默认')),
            PopupMenuItem(value: true, height: 34, child: Text('对话')),
          ],
          child: Container(
            width: 112,
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .20),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: Colors.white.withValues(alpha: .10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  chatLyrics ? '对话' : '默认',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .80),
                    fontSize: 11,
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 14,
                  color: Colors.white.withValues(alpha: .45),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _PanelProgress extends StatefulWidget {
  const _PanelProgress({required this.playback});
  final PlaybackController playback;

  @override
  State<_PanelProgress> createState() => _PanelProgressState();
}

class _PanelProgressState extends State<_PanelProgress> {
  double? _scrub;

  String _time(double seconds) {
    if (!seconds.isFinite || seconds <= 0) return '0:00';
    final value = seconds.floor();
    return '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';
  }

  void _update(Offset local, double width, double duration) {
    if (duration <= 0 || width <= 0) return;
    setState(() => _scrub = (local.dx / width).clamp(0, 1) * duration);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Duration>(
    valueListenable: widget.playback.positionListenable,
    builder: (context, position, _) {
      final duration = widget.playback.state.duration.inMilliseconds / 1000;
      final current = _scrub ?? position.inMilliseconds / 1000;
      final fraction = duration <= 0
          ? 0.0
          : (current / duration).clamp(0.0, 1.0);
      return Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              _time(current),
              textAlign: TextAlign.right,
              style: _timeStyle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (event) => _update(
                  event.localPosition,
                  constraints.maxWidth,
                  duration,
                ),
                onHorizontalDragUpdate: (event) => _update(
                  event.localPosition,
                  constraints.maxWidth,
                  duration,
                ),
                onHorizontalDragEnd: (_) {
                  final seek = _scrub;
                  setState(() => _scrub = null);
                  if (seek != null) {
                    widget.playback.seek(
                      Duration(milliseconds: (seek * 1000).round()),
                    );
                  }
                },
                onTapUp: (event) {
                  final seek =
                      (event.localPosition.dx / constraints.maxWidth).clamp(
                        0,
                        1,
                      ) *
                      duration;
                  widget.playback.seek(
                    Duration(milliseconds: (seek * 1000).round()),
                  );
                },
                child: SizedBox(
                  height: 30,
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: SizedBox(
                        height: 6,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ColoredBox(
                              color: Colors.white.withValues(alpha: .15),
                            ),
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: fraction,
                              child: ColoredBox(
                                color: Colors.white.withValues(alpha: .75),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 32, child: Text(_time(duration), style: _timeStyle)),
        ],
      );
    },
  );

  static final _timeStyle = TextStyle(
    color: Colors.white.withValues(alpha: .30),
    fontSize: 9,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

class _Transport extends StatelessWidget {
  const _Transport({required this.playback});
  final PlaybackController playback;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _TransportSide(
          icon: Icons.skip_previous_rounded,
          onTap: playback.playPrevious,
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: playback.togglePlay,
          child: Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x1AFFFFFF), blurRadius: 16)],
            ),
            child: Icon(
              playback.state.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: 25,
              color: Colors.black,
            ),
          ),
        ),
        const SizedBox(width: 12),
        _TransportSide(icon: Icons.skip_next_rounded, onTap: playback.playNext),
      ],
    ),
  );
}

class _TransportSide extends StatelessWidget {
  const _TransportSide({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _RoundHoverButton(
    size: 36,
    icon: icon,
    iconSize: 20,
    baseColor: Colors.transparent,
    iconColor: Colors.white.withValues(alpha: .50),
    onTap: onTap,
  );
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.icon, required this.onTap, this.color});
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => _RoundHoverButton(
    size: 28,
    icon: icon,
    iconSize: 15,
    baseColor: Colors.transparent,
    iconColor: color ?? Colors.white.withValues(alpha: .25),
    onTap: onTap,
  );
}

class _RepeatButton extends StatelessWidget {
  const _RepeatButton({required this.playback, required this.onTap});
  final PlaybackController playback;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mode = playback.state.repeatMode;
    final active = mode != RepeatMode.off;
    final asset = switch (mode) {
      RepeatMode.one => 'assets/icons/MaterialSymbolsRepeatOneRounded.svg',
      RepeatMode.shuffle => 'assets/icons/BxShuffle.svg',
      _ => 'assets/icons/LucideRepeat.svg',
    };
    return GestureDetector(
      onTap: onTap,
      child: SizedBox.square(
        dimension: 28,
        child: Center(
          child: SvgPicture.asset(
            asset,
            width: 15,
            height: 15,
            colorFilter: ColorFilter.mode(
              active
                  ? const Color(0xB37DD3FC)
                  : Colors.white.withValues(alpha: .25),
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }
}

class _VolumeControl extends StatelessWidget {
  const _VolumeControl({required this.playback});
  final PlaybackController playback;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _SmallButton(
        icon: playback.state.volume == 0
            ? Icons.volume_off_rounded
            : Icons.volume_up_rounded,
        color: Colors.white.withValues(alpha: .30),
        onTap: () => playback.setVolume(playback.state.volume > 0 ? 0 : .8),
      ),
      const SizedBox(width: 6),
      SizedBox(
        width: 64,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            activeTrackColor: Colors.white.withValues(alpha: .60),
            inactiveTrackColor: Colors.white.withValues(alpha: .15),
            thumbColor: Colors.white,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            value: playback.state.volume,
            onChanged: playback.setVolume,
          ),
        ),
      ),
    ],
  );
}

class _RoundHoverButton extends StatefulWidget {
  const _RoundHoverButton({
    required this.size,
    required this.icon,
    required this.iconSize,
    required this.onTap,
    this.baseColor = const Color(0x66000000),
    this.iconColor = const Color(0x80FFFFFF),
  });
  final double size;
  final IconData icon;
  final double iconSize;
  final VoidCallback onTap;
  final Color baseColor;
  final Color iconColor;

  @override
  State<_RoundHoverButton> createState() => _RoundHoverButtonState();
}

class _RoundHoverButtonState extends State<_RoundHoverButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: _hovered
              ? Colors.white.withValues(alpha: .10)
              : widget.baseColor,
          shape: BoxShape.circle,
        ),
        child: Icon(
          widget.icon,
          size: widget.iconSize,
          color: _hovered ? Colors.white : widget.iconColor,
        ),
      ),
    ),
  );
}
