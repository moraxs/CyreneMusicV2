import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/lyrics/lyric.dart';
import '../../../domain/lyrics/lyric_parser.dart';
import '../../../domain/lyrics/lyric_timing.dart';
import '../../../domain/models/track.dart';

// 圆弧参数（对应 Next.js LyricPlayerRoulette）。
const double _arcAnglePerLine = 12; // 每行占据的角度（度）
const int _visibleAbove = 3;
const int _visibleBelow = 3;

/// 轮盘歌词（对应 Next.js LyricPlayerRoulette）。
///
/// - 默认模式：歌词沿容器左侧圆心的弧线排列，当前行在正右方水平，
///   上下行向 2 点 / 4 点方向旋转发散。
/// - 隐藏封面（[centered]）模式：退化为居中垂直滚动。
/// - 仅渲染当前行上下各 3 行，点击某行跳转。
class RouletteLyricView extends StatefulWidget {
  const RouletteLyricView({
    super.key,
    required this.track,
    required this.position,
    required this.onSeek,
    this.showTranslation = true,
    this.fontSize = 34,
    this.fontFamily,
    this.disableSeek = false,
    this.centered = false,
  });

  final Track track;
  final Duration position;
  final ValueChanged<Duration> onSeek;
  final bool showTranslation;
  final double fontSize;
  final String? fontFamily;
  final bool disableSeek;

  /// 隐藏封面时居中显示（对应 hideAlbumCover）。
  final bool centered;

  @override
  State<RouletteLyricView> createState() => _RouletteLyricViewState();
}

class _RouletteLyricViewState extends State<RouletteLyricView> {
  List<LyricLine> _lines = const [];
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _parseLines();
    _updateActiveIndex();
  }

  @override
  void didUpdateWidget(covariant RouletteLyricView oldWidget) {
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final children = <Widget>[];
        for (var offset = -_visibleAbove; offset <= _visibleBelow; offset++) {
          final index = _activeIndex + offset;
          if (index < 0 || index >= _lines.length) continue;
          children.add(
            widget.centered
                ? _centeredLine(_lines[index], offset, width, height)
                : _arcLine(_lines[index], offset, width, height),
          );
        }
        return ClipRect(child: Stack(children: children));
      },
    );
  }

  // --- 弧形排列 ---
  Widget _arcLine(LyricLine line, int offset, double width, double height) {
    final isActive = offset == 0;
    final absDiff = offset.abs();
    final angleDeg = offset * _arcAnglePerLine;
    final angleRad = angleDeg * math.pi / 180;

    // 圆心在左侧外部（-100%），半径为容器宽度的 120%。
    const centerXPct = -100.0;
    const radiusPct = 120.0;
    const centerYPct = 50.0;
    final xFrac = (centerXPct + radiusPct * math.cos(angleRad)) / 100;
    final yFrac = (centerYPct + radiusPct * math.sin(angleRad)) / 100;

    final opacity = isActive ? 1.0 : math.max(0.2, 0.65 - absDiff * 0.15);
    final scale = isActive ? 1.0 : math.max(0.65, 0.85 - absDiff * 0.06);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 1000),
      curve: const Cubic(0.16, 1, 0.3, 1),
      left: xFrac * width,
      top: yFrac * height,
      width: width * 0.55,
      child: FractionalTranslation(
        translation: const Offset(0, -0.5),
        child: Transform.rotate(
          angle: angleRad,
          alignment: Alignment.centerLeft,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 600),
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.centerLeft,
              child: _lineContent(line, isActive, TextAlign.left),
            ),
          ),
        ),
      ),
    );
  }

  // --- 居中垂直排列（隐藏封面） ---
  Widget _centeredLine(
    LyricLine line,
    int offset,
    double width,
    double height,
  ) {
    final isActive = offset == 0;
    final absDiff = offset.abs();
    final opacity = isActive ? 1.0 : math.max(0.2, 0.65 - absDiff * 0.15);
    final scale = isActive ? 1.0 : math.max(0.65, 0.85 - absDiff * 0.06);
    // translate(-50%, -50% + offset*6vh)：以容器高度近似 vh。
    final dy = height / 2 + offset * height * 0.06;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 1000),
      curve: const Cubic(0.16, 1, 0.3, 1),
      left: width * 0.05,
      top: dy,
      width: width * 0.9,
      child: FractionalTranslation(
        translation: const Offset(0, -0.5),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 600),
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: _lineContent(line, isActive, TextAlign.center),
          ),
        ),
      ),
    );
  }

  Widget _lineContent(LyricLine line, bool isActive, TextAlign align) {
    final showTranslation =
        widget.showTranslation &&
        (line.translation != null && line.translation!.isNotEmpty);
    final crossAxis = align == TextAlign.center
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    return GestureDetector(
      onTap: () => _handleTap(line),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: crossAxis,
        children: [
          Text(
            line.text,
            textAlign: align,
            style: TextStyle(
              color: Colors.white.withValues(alpha: isActive ? 1 : 0.4),
              fontFamily: widget.fontFamily,
              fontSize: widget.fontSize * 0.9,
              fontWeight: FontWeight.bold,
              height: 1.15,
              shadows: isActive
                  ? const [Shadow(color: Color(0x26FFFFFF), blurRadius: 12)]
                  : null,
            ),
          ),
          if (showTranslation) ...[
            const SizedBox(height: 2),
            Text(
              line.translation!,
              textAlign: align,
              style: TextStyle(
                color: Colors.white.withValues(alpha: isActive ? 0.5 : 0.25),
                fontFamily: widget.fontFamily,
                fontSize: widget.fontSize * 0.45,
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
