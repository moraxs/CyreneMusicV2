import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../domain/playback/player_display_settings.dart';
import '../../../domain/lyrics/lyric.dart';
import '../../../domain/lyrics/lyric_parser.dart';
import '../../../domain/lyrics/lyric_timing.dart';
import '../../../domain/models/track.dart';

/// 单行歌词（对应 Next.js LyricPlayerSingleLine）。
///
/// 只展示当前行及其上下各 2 行，居中显示；随 [SingleLineAnimation] 呈现
/// 上滑 / 淡入 / 缩放 / 模糊过渡。点击当前行跳转。
class SingleLineLyricView extends StatefulWidget {
  const SingleLineLyricView({
    super.key,
    required this.track,
    required this.position,
    required this.animation,
    required this.onSeek,
    this.showTranslation = true,
    this.fontSize = 34,
    this.fontFamily,
    this.disableSeek = false,
  });

  final Track track;
  final Duration position;
  final SingleLineAnimation animation;
  final ValueChanged<Duration> onSeek;
  final bool showTranslation;
  final double fontSize;
  final String? fontFamily;
  final bool disableSeek;

  @override
  State<SingleLineLyricView> createState() => _SingleLineLyricViewState();
}

class _SingleLineLyricViewState extends State<SingleLineLyricView> {
  List<LyricLine> _lines = const [];
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _parseLines();
    _updateActiveIndex();
  }

  @override
  void didUpdateWidget(covariant SingleLineLyricView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final lyricsChanged =
        widget.track.key != oldWidget.track.key ||
        widget.track.lyric != oldWidget.track.lyric ||
        widget.track.yrc != oldWidget.track.yrc ||
        widget.track.tlyric != oldWidget.track.tlyric ||
        widget.track.ytlrc != oldWidget.track.ytlrc ||
        widget.showTranslation != oldWidget.showTranslation;
    if (lyricsChanged) _parseLines();
    if (lyricsChanged || widget.position != oldWidget.position) {
      _updateActiveIndex();
    }
  }

  void _parseLines() {
    _lines = const LyricParser().parse(
      source: widget.track.source,
      lyric: widget.track.lyric,
      yrc: widget.track.yrc,
      translation: widget.track.tlyric,
      verbatimTranslation: widget.track.ytlrc,
    );
  }

  void _updateActiveIndex() {
    if (_lines.isEmpty) return;
    final lookup = lyricLookupPosition(widget.position);
    var index = 0;
    for (var i = 0; i < _lines.length; i++) {
      if (lookup >= _lines[i].start) {
        index = i;
      } else {
        break;
      }
    }
    if (index != _activeIndex && mounted) {
      setState(() => _activeIndex = index);
    }
  }

  void _handleTap(LyricLine line) {
    if (widget.disableSeek) return;
    widget.onSeek(playbackPositionForLyric(line.start));
  }

  @override
  Widget build(BuildContext context) {
    if (_lines.isEmpty) {
      return Center(
        child: Text(
          '这首歌还没有歌词',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        ),
      );
    }

    final children = <Widget>[];
    for (var index = 0; index < _lines.length; index++) {
      final diff = index - _activeIndex;
      if (diff.abs() > 2) continue;
      children.add(_buildLine(_lines[index], diff));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(alignment: Alignment.center, children: children),
    );
  }

  Widget _buildLine(LyricLine line, int diff) {
    final isActive = diff == 0;

    var offset = Offset.zero;
    var scale = 1.0;
    var blur = 0.0;
    final opacity = isActive ? 1.0 : 0.0;

    switch (widget.animation) {
      case SingleLineAnimation.fade:
        scale = isActive ? 1.0 : 0.95;
      case SingleLineAnimation.zoom:
        scale = isActive ? 1.0 : (diff < 0 ? 1.2 : 0.8);
      case SingleLineAnimation.blur:
        scale = isActive ? 1.0 : 0.95;
        blur = isActive ? 0.0 : 16.0;
      case SingleLineAnimation.slideUp:
        scale = isActive ? 1.0 : 0.95;
        // ±150% 位移，用一个较大的固定像素近似（面板高度未知）。
        final dy = diff < 0 ? -1.5 : (diff > 0 ? 1.5 : 0.0);
        offset = Offset(0, dy);
    }

    Widget content = _lineContent(line);

    if (blur > 0) {
      content = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: content,
      );
    }

    return IgnorePointer(
      ignoring: !isActive,
      child: AnimatedSlide(
        offset: offset,
        duration: const Duration(milliseconds: 1000),
        curve: const Cubic(0.16, 1, 0.3, 1),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 1000),
          curve: const Cubic(0.16, 1, 0.3, 1),
          child: AnimatedOpacity(
            opacity: opacity,
            duration: const Duration(milliseconds: 1000),
            curve: const Cubic(0.16, 1, 0.3, 1),
            child: GestureDetector(
              onTap: () => _handleTap(line),
              behavior: HitTestBehavior.opaque,
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  Widget _lineContent(LyricLine line) {
    final showTranslation =
        widget.showTranslation &&
        (line.translation != null && line.translation!.isNotEmpty);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            line.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontFamily: widget.fontFamily,
              fontSize: widget.fontSize * 1.1,
              fontWeight: FontWeight.bold,
              height: 1.15,
              shadows: const [
                Shadow(
                  color: Color(0x4D000000),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
          ),
          if (showTranslation) ...[
            const SizedBox(height: 12),
            Text(
              line.translation!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontFamily: widget.fontFamily,
                fontSize: widget.fontSize * 0.6,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
