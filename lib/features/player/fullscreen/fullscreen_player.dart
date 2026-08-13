import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart' hide RepeatMode;
// 只取进度指示器：本文件按原版样式移植，避免 miuix 全量导入与原版符号撞名。
import 'package:flutter_miuix/miuix.dart'
    show MiuixCircularProgressIndicator, MiuixProgressIndicatorColors;
import 'package:flutter_svg/flutter_svg.dart';

import '../../../application/audio_sources/audio_source_preferences_controller.dart';
import '../../../application/auth/account_session_controller.dart';
import '../../../domain/models/media_url.dart';
import '../../../application/playback/playback_controller.dart';
import '../../../application/stores/fullscreen_settings_store.dart';
import '../../../domain/lyrics/lyric_fonts.dart';
import '../../../domain/models/audio_quality.dart';
import '../../../domain/models/music_source.dart';
import '../../../domain/models/track.dart';
import '../../../domain/playback/playback_state.dart';
import '../../../domain/playback/player_display_settings.dart';
import '../../../domain/playback/repeat_mode.dart';
import '../../../infrastructure/services/playlist_service.dart';
import '../../../presentation/cyrene/cyrene_toast.dart';
import 'add_to_playlist_sheet.dart';
import 'audio_visualizer.dart';
import 'lyric_scroll_view.dart';
import 'player_settings_sheet.dart';
import 'roulette_lyric_view.dart';
import 'single_line_lyric_view.dart';

/// 全屏播放器（移动端，对应 Next.js FullscreenPlayer 的 isMobile 分支）。
///
/// Apple Music 风格：环境模糊背景 + 大封面 + 标题/收藏/歌手/循环 + 进度条
/// （含副歌高亮与音质选择）+ 播放控制 + 动作行（歌词/信息/翻译）+ 滑出歌词面板
/// + 沉浸模式。SuperCyrene 与桌面胶囊栏不在移植范围内。
class FullscreenPlayer extends StatefulWidget {
  const FullscreenPlayer({
    super.key,
    required this.playback,
    required this.audioSources,
    required this.account,
  });

  final PlaybackController playback;
  final AudioSourcePreferencesController audioSources;
  final AccountSessionController account;

  @override
  State<FullscreenPlayer> createState() => _FullscreenPlayerState();
}

/// 右侧面板模式（歌词 / 歌曲信息）。均衡器面板依赖 Web Audio，暂不移植。
enum _PanelMode { lyrics, info }

class _FullscreenPlayerState extends State<FullscreenPlayer> {
  FullscreenSettingsStore get _settings => FullscreenSettingsStore.instance;

  bool _showLyrics = false;
  _PanelMode _panelMode = _PanelMode.lyrics;
  double? _dragProgress;

  List<int> _inPlaylistIds = const [];
  String? _checkedTrackKey;

  @override
  void initState() {
    super.initState();
    widget.playback.addListener(_onPlaybackChange);
    widget.audioSources.addListener(_onChange);
    widget.account.addListener(_onChange);
    _settings.addListener(_onChange);
    _refreshPlaylistStatus();
  }

  @override
  void dispose() {
    widget.playback.removeListener(_onPlaybackChange);
    widget.audioSources.removeListener(_onChange);
    widget.account.removeListener(_onChange);
    _settings.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _onPlaybackChange() {
    if (!mounted) return;
    setState(() {});
    // 曲目切换时重新检查收藏状态。
    final track = widget.playback.state.currentTrack;
    if (track != null && track.key != _checkedTrackKey) {
      _refreshPlaylistStatus();
    }
  }

  Future<void> _refreshPlaylistStatus() async {
    final track = widget.playback.state.currentTrack;
    final token = widget.account.token;
    if (track == null || token == null) {
      if (mounted) {
        setState(() {
          _inPlaylistIds = const [];
          _checkedTrackKey = track?.key;
        });
      }
      return;
    }
    _checkedTrackKey = track.key;
    final result = await PlaylistService.instance.checkTrackInPlaylists(
      token,
      track.id,
      track.source.wireName,
    );
    if (!mounted) return;
    // 若期间曲目已切换则丢弃结果。
    if (widget.playback.state.currentTrack?.key != track.key) return;
    setState(() => _inPlaylistIds = result.playlistIds);
  }

  bool get _isFavorited => _inPlaylistIds.isNotEmpty;

  Future<void> _onHeartTap(Track track) async {
    final token = widget.account.token;
    if (token == null) {
      _toast('请先登录后再收藏');
      return;
    }
    // 未收藏或存在于多个歌单：打开管理面板；仅在一个歌单时直接移除。
    if (_inPlaylistIds.length != 1) {
      final changed = await AddToPlaylistSheet.show(
        context,
        token: token,
        track: track,
        showOnlyJoinedInitially: _inPlaylistIds.isNotEmpty,
      );
      if (changed == true) await _refreshPlaylistStatus();
      return;
    }
    final ok = await PlaylistService.instance.removeTrackFromPlaylist(
      token,
      _inPlaylistIds.first,
      track.id,
      track.source.wireName,
    );
    _toast(ok ? '已从歌单中移除' : '从歌单移除失败');
    if (ok) await _refreshPlaylistStatus();
  }

  void _toast(String message) {
    if (!mounted) return;
    CyreneToast.show(message);
  }

  String _formatTime(Duration d) {
    final total = d.inSeconds.abs();
    final minutes = total ~/ 60;
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  RepeatMode _nextRepeat(RepeatMode mode) => switch (mode) {
    RepeatMode.all => RepeatMode.one,
    RepeatMode.one => RepeatMode.shuffle,
    RepeatMode.shuffle => RepeatMode.all,
    RepeatMode.off => RepeatMode.all,
  };

  String _repeatAsset(RepeatMode mode) => switch (mode) {
    RepeatMode.one => 'assets/icons/MaterialSymbolsRepeatOneRounded.svg',
    RepeatMode.shuffle => 'assets/icons/BxShuffle.svg',
    RepeatMode.all || RepeatMode.off => 'assets/icons/LucideRepeat.svg',
  };

  @override
  Widget build(BuildContext context) {
    final state = widget.playback.state;
    final track = state.currentTrack;
    if (track == null) {
      return const SizedBox.shrink();
    }

    final immersive = _settings.isImmersiveMode;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _AmbientBackground(picUrl: track.picUrl),
          if (immersive) _ImmersiveCover(picUrl: track.picUrl),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _topBar(track),
                Expanded(child: _mainContent(state, track)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(Track track) => AnimatedOpacity(
    duration: const Duration(milliseconds: 250),
    opacity: _showLyrics ? 0 : 1,
    child: IgnorePointer(
      ignoring: _showLyrics,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _iconButton(
              icon: Icons.keyboard_arrow_down,
              size: 28,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            _iconButton(
              icon: Icons.more_horiz,
              size: 22,
              onTap: () =>
                  PlayerSettingsSheet.show(context, trackSource: track.source),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _iconButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 24,
    Color? color,
  }) => Material(
    color: Colors.transparent,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          size: size,
          color: color ?? Colors.white.withValues(alpha: 0.6),
        ),
      ),
    ),
  );

  // --- main content ---

  Widget _mainContent(PlaybackState state, Track track) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: Offset(_showLyrics ? 0.15 : -0.15, 0),
          end: Offset.zero,
        ).animate(animation);
        return SlideTransition(
          position: slide,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: _showLyrics
          ? _lyricsPanel(state, track)
          : _coverAndControls(state, track),
    );
  }

  Widget _coverAndControls(PlaybackState state, Track track) =>
      SingleChildScrollView(
        key: const ValueKey('cover'),
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          children: [
            if (!_settings.hideAlbumCover && !_settings.isImmersiveMode) ...[
              const SizedBox(height: 8),
              _AlbumCover(picUrl: track.picUrl, isPlaying: state.isPlaying),
              const SizedBox(height: 20),
              if (_settings.audioVisualization)
                AudioVisualizer(isPlaying: state.isPlaying),
              const SizedBox(height: 20),
            ] else
              const SizedBox(height: 24),
            _titleRow(track),
            const SizedBox(height: 4),
            _artistRow(track),
            _repeatRow(state),
            const SizedBox(height: 12),
            _progress(state, track),
            const SizedBox(height: 20),
            _playbackButtons(state),
            const SizedBox(height: 20),
            _actionRow(track),
          ],
        ),
      );

  Widget _titleRow(Track track) => Row(
    children: [
      Expanded(
        child: Text(
          track.name.isEmpty ? '未在播放' : track.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
            height: 1.1,
            letterSpacing: -0.5,
          ),
        ),
      ),
      GestureDetector(
        onTap: () => _onHeartTap(track),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            Icons.favorite_border,
            size: 24,
            color: _isFavorited
                ? const Color(0xFFEF4444)
                : Colors.white.withValues(alpha: 0.3),
          ),
        ),
      ),
    ],
  );

  Widget _artistRow(Track track) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      track.artists.isEmpty ? '未知歌手' : track.artists,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.5),
        fontSize: 17,
        fontWeight: FontWeight.w500,
      ),
    ),
  );

  Widget _repeatRow(PlaybackState state) => Align(
    alignment: Alignment.centerRight,
    child: _svgActionButton(
      asset: _repeatAsset(state.repeatMode),
      active: state.repeatMode != RepeatMode.all && state.repeatMode != RepeatMode.off,
      onTap: () => widget.playback.setRepeatMode(_nextRepeat(state.repeatMode)),
    ),
  );

  Widget _progress(PlaybackState state, Track track) {
    final duration = state.duration;
    final positionMs = state.position.inMilliseconds.toDouble();
    final durationMs = duration.inMilliseconds.toDouble();
    final ratio = durationMs > 0
        ? (positionMs / durationMs).clamp(0.0, 1.0)
        : 0.0;
    final displayRatio = _dragProgress ?? ratio;
    final displayPosition = Duration(
      milliseconds: (displayRatio * durationMs).round(),
    );
    final remaining = duration - displayPosition;

    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
            thumbColor: Colors.white,
            overlayColor: Colors.white.withValues(alpha: 0.15),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: displayRatio.clamp(0.0, 1.0),
            onChanged: durationMs > 0
                ? (value) => setState(() => _dragProgress = value)
                : null,
            onChangeEnd: (value) {
              widget.playback.seek(
                Duration(milliseconds: (value * durationMs).round()),
              );
              setState(() => _dragProgress = null);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _timeText(_formatTime(displayPosition)),
              _qualityButton(),
              _timeText('-${_formatTime(remaining)}'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _timeText(String text) => Text(
    text,
    style: TextStyle(
      color: Colors.white.withValues(alpha: 0.5),
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );

  Widget _qualityButton() {
    final quality = widget.audioSources.state.quality;
    return GestureDetector(
      onTap: _showQualityMenu,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          _qualityLabel(quality),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _playbackButtons(PlaybackState state) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _svgPlaybackButton(
        asset: 'assets/icons/icon_rewind.svg',
        size: 40,
        onTap: widget.playback.playPrevious,
      ),
      const SizedBox(width: 32),
      _svgPlaybackButton(
        asset: state.isPlaying
            ? 'assets/icons/icon_pause.svg'
            : 'assets/icons/icon_play.svg',
        size: 52,
        loading: state.isLoading,
        onTap: widget.playback.togglePlay,
      ),
      const SizedBox(width: 32),
      _svgPlaybackButton(
        asset: 'assets/icons/icon_forward.svg',
        size: 40,
        onTap: widget.playback.playNext,
      ),
    ],
  );

  Widget _svgPlaybackButton({
    required String asset,
    required VoidCallback onTap,
    double size = 40,
    bool loading = false,
  }) => GestureDetector(
    onTap: loading ? null : onTap,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: loading
          ? MiuixCircularProgressIndicator(
              size: size,
              strokeWidth: 2.5,
              colors: const MiuixProgressIndicatorColors(
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                backgroundColor: Colors.transparent,
              ),
            )
          : SvgPicture.asset(
              asset,
              width: size,
              height: size,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
    ),
  );

  Widget _actionRow(Track track) {
    final hasTranslation =
        (track.tlyric?.isNotEmpty ?? false) ||
        (track.ytlrc?.isNotEmpty ?? false);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _svgActionButton(
          asset: 'assets/icons/icon_lyrics.svg',
          active: _showLyrics && _panelMode == _PanelMode.lyrics,
          onTap: () => setState(() {
            if (_showLyrics && _panelMode == _PanelMode.lyrics) {
              _showLyrics = false;
            } else {
              _panelMode = _PanelMode.lyrics;
              _showLyrics = true;
            }
          }),
        ),
        const SizedBox(width: 32),
        _actionButton(
          icon: Icons.info_outline,
          active: _showLyrics && _panelMode == _PanelMode.info,
          onTap: () => setState(() {
            if (_showLyrics && _panelMode == _PanelMode.info) {
              _showLyrics = false;
            } else {
              _panelMode = _PanelMode.info;
              _showLyrics = true;
            }
          }),
        ),
        if (hasTranslation) ...[
          const SizedBox(width: 32),
          _actionButton(
            icon: Icons.translate,
            active: _settings.showTranslation,
            onTap: _settings.toggleTranslation,
          ),
        ],
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.transparent,
      ),
      child: Icon(
        icon,
        size: 24,
        color: Colors.white.withValues(alpha: active ? 1 : 0.3),
      ),
    ),
  );

  Widget _svgActionButton({
    required String asset,
    required bool active,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.transparent,
      ),
      child: SvgPicture.asset(
        asset,
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(
          Colors.white.withValues(alpha: active ? 1 : 0.3),
          BlendMode.srcIn,
        ),
      ),
    ),
  );

  // --- lyrics / info panel ---

  Widget _lyricsPanel(PlaybackState state, Track track) => GestureDetector(
    key: const ValueKey('lyrics'),
    onTap: () => setState(() => _showLyrics = false),
    behavior: HitTestBehavior.opaque,
    child: Column(
      children: [
        _panelHeader(track),
        Expanded(
          child: GestureDetector(
            onTap: () {},
            child: _panelMode == _PanelMode.info
                ? _SongInfoView(track: track)
                : _lyricsForStyle(state, track),
          ),
        ),
        SizedBox(height: MediaQuery.viewPaddingOf(context).bottom + 12),
      ],
    ),
  );

  Widget _lyricsForStyle(PlaybackState state, Track track) {
    final fontFamily = flutterFamilyForFontValue(_settings.lyricFontFamily);
    switch (_settings.lyricDisplayStyle) {
      case LyricDisplayStyle.singleLine:
        return SingleLineLyricView(
          track: track,
          position: state.position,
          animation: _settings.singleLineAnimation,
          fontSize: _settings.lyricFontSize,
          fontFamily: fontFamily,
          showTranslation: _settings.showTranslation,
          onSeek: widget.playback.seek,
        );
      case LyricDisplayStyle.roulette:
        return RouletteLyricView(
          track: track,
          position: state.position,
          onSeek: widget.playback.seek,
          showTranslation: _settings.showTranslation,
          fontSize: _settings.lyricFontSize,
          fontFamily: fontFamily,
          centered: _settings.hideAlbumCover,
        );
      case LyricDisplayStyle.scroll:
        return LyricScrollView(
          track: track,
          position: state.position,
          isPlaying: state.isPlaying,
          onSeek: widget.playback.seek,
          showTranslation: _settings.showTranslation,
          fontSize: _settings.lyricFontSize,
          fontFamily: fontFamily,
          centered: _settings.hideAlbumCover,
        );
    }
  }

  Widget _panelHeader(Track track) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _CoverImage(picUrl: track.picUrl, size: 48),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.name.isEmpty ? '未在播放' : track.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                track.artists.isEmpty ? '未知歌手' : track.artists,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        _iconButton(
          icon: Icons.more_horiz,
          size: 22,
          onTap: () =>
              PlayerSettingsSheet.show(context, trackSource: track.source),
        ),
      ],
    ),
  );

  // --- quality menu ---

  void _showQualityMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final current = widget.audioSources.state.quality;
        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xF20A0A0A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '音质选择',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
              for (final option in _qualityOptions())
                ListTile(
                  dense: true,
                  title: Text(
                    option.$2,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  subtitle: Text(
                    option.$3,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                  trailing: current == option.$1
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : null,
                  onTap: () {
                    widget.audioSources.setQuality(option.$1);
                    Navigator.of(sheetContext).pop();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  List<(AudioQuality, String, String)> _qualityOptions() {
    final isNetease =
        widget.playback.state.currentTrack?.source == MusicSource.netease;
    // 网易云专属音质（higher/dolby/jyeffect/sky/jymaster）仅网易云可选；
    // 其余平台只保留通用档位，避免选了不生效的音质。
    final neteaseExtras = <(AudioQuality, String, String)>[
      (AudioQuality.higher, '较高音质', '192kbps，介于标准与极高之间'),
      (AudioQuality.jyeffect, '高清环绕声', 'Audio Vivid，沉浸体验'),
      (AudioQuality.sky, '沉浸环绕声', '全景声，空间音频'),
      (AudioQuality.dolby, '杜比全景声', 'Dolby Atmos 空间音频'),
      (AudioQuality.jymaster, '超清母带', '录音室母带级音质'),
    ];
    return [
      (AudioQuality.standard, '标准音质', '128kbps，节省流量'),
      (AudioQuality.exHigh, '极高音质', '320kbps，音质细腻'),
      (AudioQuality.lossless, '无损音质', 'FLAC，CD 级音质'),
      (AudioQuality.hiRes, 'Hi-Res 音质', '24bit/96kHz 及以上'),
      if (isNetease) ...neteaseExtras,
    ];
  }

  String _qualityLabel(AudioQuality quality) => switch (quality) {
    AudioQuality.standard => 'STANDARD',
    AudioQuality.higher => 'HIGHER',
    AudioQuality.exHigh => 'EXHIGH',
    AudioQuality.lossless => 'LOSSLESS',
    AudioQuality.hiRes => 'HIRES',
    AudioQuality.jyeffect => 'JYEFFECT',
    AudioQuality.sky => 'SKY',
    AudioQuality.dolby => 'DOLBY',
    AudioQuality.jymaster => 'JYMASTER',
  };
}

/// 环境模糊背景：封面放大模糊 + 黑色叠层（对应 AMLLBackground 的静态近似）。
class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground({required this.picUrl});

  final String picUrl;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: Colors.black),
      if (picUrl.isNotEmpty)
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: Opacity(
            opacity: 0.8,
            child: _AmbientImage(picUrl: picUrl),
          ),
        ),
      ColoredBox(color: Colors.black.withValues(alpha: 0.2)),
    ],
  );
}

/// 环境背景封面图：兼容网络 URL 与本地内嵌 data URI。
class _AmbientImage extends StatelessWidget {
  const _AmbientImage({required this.picUrl});

  final String picUrl;

  @override
  Widget build(BuildContext context) {
    if (isDataUriImage(picUrl)) {
      final bytes = decodeDataUriImage(picUrl);
      if (bytes != null) {
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        );
      }
      return const SizedBox.shrink();
    }
    return CachedNetworkImage(
      imageUrl: picUrl,
      httpHeaders: imageHeaders(picUrl),
      fit: BoxFit.cover,
      errorWidget: (_, _, _) => const SizedBox.shrink(),
    );
  }
}

/// 沉浸模式顶部封面：顶部 55% 高度，向下渐隐（对应移动端 immersive cover）。
class _ImmersiveCover extends StatelessWidget {
  const _ImmersiveCover({required this.picUrl});

  final String picUrl;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.55;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: height,
      child: IgnorePointer(
        child: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.white70,
              Colors.white24,
              Colors.transparent,
            ],
            stops: [0.0, 0.35, 0.7, 1.0],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _CoverImage(picUrl: picUrl, fit: BoxFit.cover),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.2),
                      Colors.black.withValues(alpha: 0.4),
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Apple Music 风格大封面：圆角 14，播放时 scale 1.0 / 暂停 0.92，投影。
class _AlbumCover extends StatelessWidget {
  const _AlbumCover({required this.picUrl, required this.isPlaying});

  final String picUrl;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final size = (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 380.0);
    return AnimatedScale(
      scale: isPlaying ? 1.0 : 0.92,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: 60,
              offset: Offset(0, 20),
            ),
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: _CoverImage(picUrl: picUrl, size: size),
        ),
      ),
    );
  }
}

/// 统一封面图片：加载失败或空 URL 时回退到「CYRENE」占位。
class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.picUrl, this.size, this.fit = BoxFit.cover});

  final String picUrl;
  final double? size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      color: const Color(0xFF1A1A1A),
      alignment: Alignment.center,
      child: Text(
        'CYRENE',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.1),
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    if (picUrl.isEmpty) return fallback;
    // 本地音轨的内嵌封面是 data:image/...;base64 URI，CachedNetworkImage 不认。
    if (isDataUriImage(picUrl)) {
      final bytes = decodeDataUriImage(picUrl);
      if (bytes != null) {
        return Image.memory(
          bytes,
          width: size,
          height: size,
          fit: fit,
          errorBuilder: (_, _, _) => fallback,
        );
      }
      return fallback;
    }
    return CachedNetworkImage(
      imageUrl: picUrl,
      httpHeaders: imageHeaders(picUrl),
      width: size,
      height: size,
      fit: fit,
      errorWidget: (_, _, _) => fallback,
    );
  }
}

/// 歌曲信息面板（对应 SongInfoPanel 的移动端近似）：展示标题、歌手、专辑、来源。
class _SongInfoView extends StatelessWidget {
  const _SongInfoView({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    children: [
      _row('歌曲', track.name),
      _row('歌手', track.artists),
      _row('专辑', track.album),
      _row('来源', _sourceLabel(track.source)),
    ],
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value.isEmpty ? '—' : value,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ],
    ),
  );

  String _sourceLabel(MusicSource source) => switch (source) {
    MusicSource.netease => '网易云音乐',
    MusicSource.qq => 'QQ 音乐',
    MusicSource.kugou => '酷狗音乐',
    MusicSource.kuwo => '酷我音乐',
    MusicSource.apple => 'Apple Music',
    MusicSource.spotify => 'Spotify',
    MusicSource.qishui => '汽水音乐',
    MusicSource.local => '本地音乐',
  };
}
