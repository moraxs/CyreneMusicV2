import 'package:flutter/material.dart';

import '../../../application/playback/playback_controller.dart';
import '../../../domain/models/music_source.dart';
import '../../../domain/models/track.dart';
import '../mobile/compat/color_extraction_service.dart';
import '../mobile/compat/lyric_line.dart';
import '../mobile/compat/lyric_parser.dart';
import 'sonnet_core/sonnet_canvas.dart';
import 'sonnet_core/sonnet_credits.dart';
import 'sonnet_core/sonnet_program.dart';
import 'sonnet_core/sonnet_tuning.dart';
import 'sonnet_core/sonnet_types.dart';

/// 构象（Sonnet）日系 MG 动态排版与镜头视觉引擎歌词主题。
/// 1:1 逐像素代码级复刻自 Folia (demo/folia-major-main/src/components/visualizer/sonnet)。
class SuperCyreneSonnetLyrics extends StatefulWidget {
  const SuperCyreneSonnetLyrics({
    super.key,
    required this.playback,
    required this.track,
    required this.onTranslationChanged,
    this.cover,
    this.tuning,
    this.lyricsFontScale = 1.0,
  });

  final PlaybackController playback;
  final Track track;
  final ValueChanged<String?> onTranslationChanged;
  final ImageProvider? cover;
  final SonnetTuning? tuning;
  final double lyricsFontScale;

  @override
  State<SuperCyreneSonnetLyrics> createState() =>
      _SuperCyreneSonnetLyricsState();
}

class _SuperCyreneSonnetLyricsState extends State<SuperCyreneSonnetLyrics>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  SonnetProgram _program = SonnetProgram.empty;
  List<LyricLine> _rawLines = const [];
  int _lastTranslationIdx = -2;

  Color _primaryColor = const Color(0xFFFFFFFF);
  Color _secondaryColor = const Color(0xFFC4B5FD);
  Color _accentColor = const Color(0xFFDDD6FE);

  Duration _lastPosition = Duration.zero;
  DateTime _lastPositionTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(days: 1),
    )..repeat();

    _lastPosition = widget.playback.positionListenable.value;
    _lastPositionTime = DateTime.now();

    widget.playback.positionListenable.addListener(_onPositionChanged);
    _adaptTrack();
    _extractThemeColors();
  }

  void _onPositionChanged() {
    _lastPosition = widget.playback.positionListenable.value;
    _lastPositionTime = DateTime.now();
    _updateTranslation();
  }

  double _computeCurrentTimeSec() {
    final baseSec = _lastPosition.inMicroseconds / 1000000.0;
    if (widget.playback.state.isPlaying) {
      final elapsedSec =
          DateTime.now().difference(_lastPositionTime).inMicroseconds /
              1000000.0;
      return baseSec + elapsedSec.clamp(0.0, 0.25);
    }
    return baseSec;
  }

  @override
  void didUpdateWidget(covariant SuperCyreneSonnetLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playback != widget.playback) {
      oldWidget.playback.positionListenable.removeListener(_onPositionChanged);
      widget.playback.positionListenable.addListener(_onPositionChanged);
      _lastPosition = widget.playback.positionListenable.value;
      _lastPositionTime = DateTime.now();
    }
    if (_lyricSignature(oldWidget.track) != _lyricSignature(widget.track)) {
      _adaptTrack();
      _extractThemeColors();
    }
  }

  int _lyricSignature(Track track) => Object.hash(
        track.key,
        track.lyric,
        track.yrc,
        track.tlyric,
        track.ytlrc,
      );

  @override
  void dispose() {
    widget.playback.positionListenable.removeListener(_onPositionChanged);
    _ticker.dispose();
    super.dispose();
  }

  void _extractThemeColors() async {
    final picUrl = widget.track.picUrl;
    if (picUrl.isEmpty) {
      setState(() {
        _primaryColor = const Color(0xFFFFFFFF);
        _secondaryColor = const Color(0xFFC4B5FD);
        _accentColor = const Color(0xFFDDD6FE);
      });
      return;
    }

    try {
      final colors =
          await ColorExtractionService().extractColorsFromUrl(picUrl);
      if (mounted && colors != null) {
        setState(() {
          _primaryColor = const Color(0xFFFFFFFF);
          _accentColor = colors.lightVibrantColor ??
              colors.vibrantColor ??
              const Color(0xFFDDD6FE);
          _secondaryColor = colors.vibrantColor ??
              colors.dominantColor ??
              const Color(0xFFC4B5FD);
        });
      }
    } catch (_) {
      // Fallback to default harmonious palette
    }
  }

  void _adaptTrack() {
    SonnetSceneBuilder.clearCache();
    final lyric = widget.track.lyric;
    final parsed = lyric == null || lyric.isEmpty
        ? const <LyricLine>[]
        : switch (widget.track.source) {
            MusicSource.qq => LyricParser.parseQQLyric(
                lyric,
                translation: widget.track.tlyric,
                qrcLyric: widget.track.yrc,
                qrcTranslation: widget.track.ytlrc,
              ),
            MusicSource.kugou => LyricParser.parseKugouLyric(
                lyric,
                translation: widget.track.tlyric,
              ),
            _ => LyricParser.parseNeteaseLyric(
                lyric,
                translation: widget.track.tlyric,
                yrcLyric: widget.track.yrc,
                yrcTranslation: widget.track.ytlrc,
              ),
          };

    _rawLines = parsed.where((l) => l.text.trim().isNotEmpty).toList();
    _program = compileSonnetProgram(
      _rawLines,
      widget.track.key,
    );
    _lastTranslationIdx = -2;
    _updateTranslation();
  }

  void _updateTranslation() {
    if (_rawLines.isEmpty) {
      if (_lastTranslationIdx != -1) {
        _lastTranslationIdx = -1;
        widget.onTranslationChanged(null);
      }
      return;
    }

    final pos = widget.playback.positionListenable.value;
    var activeIdx = -1;
    for (var i = 0; i < _rawLines.length; i++) {
      final line = _rawLines[i];
      final end =
          line.startTime + (line.lineDuration ?? const Duration(seconds: 4));
      if (pos >= line.startTime && pos <= end) {
        activeIdx = i;
        break;
      }
      if (pos >= line.startTime) {
        activeIdx = i;
      }
    }

    if (activeIdx != _lastTranslationIdx) {
      _lastTranslationIdx = activeIdx;
      final trans = activeIdx >= 0 && activeIdx < _rawLines.length
          ? _rawLines[activeIdx].translation
          : null;
      widget.onTranslationChanged(
          trans?.trim().isNotEmpty == true ? trans : null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ticker,
      builder: (context, _) {
        final curSec = _computeCurrentTimeSec();

        return RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: SonnetPainter(
              program: _program,
              currentTime: curSec,
              tuning: widget.tuning ?? SonnetTuning.defaults,
              primaryColor: _primaryColor,
              secondaryColor: _secondaryColor,
              accentColor: _accentColor,
              creditsMetadata: SonnetCreditsMetadata(
                title: widget.track.name,
                artist: widget.track.artists,
                album: widget.track.album,
              ),
              lyricsFontScale: widget.lyricsFontScale,
            ),
          ),
        );
      },
    );
  }
}
