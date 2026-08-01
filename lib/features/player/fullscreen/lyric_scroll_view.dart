import 'package:flutter/material.dart';

import '../../../domain/lyrics/lyric.dart';
import '../../../domain/lyrics/lyric_parser.dart';
import '../../../domain/lyrics/lyric_timeline.dart';
import '../../../domain/lyrics/lyric_timing.dart';
import '../../../domain/models/track.dart';

/// 全屏播放器滚动歌词（对应 Next.js AMLLLyricPlayer 的滚动样式）。
///
/// - 当前行居中偏上（对齐位置约 15%），自动平滑滚动。
/// - 当前行放大高亮，其余行半透明。
/// - 顶部/底部渐隐遮罩。
/// - 点击某行跳转到该行时间。
/// - 支持翻译显示、字号、字体自定义。
class LyricScrollView extends StatefulWidget {
  const LyricScrollView({
    super.key,
    required this.track,
    required this.position,
    required this.isPlaying,
    required this.onSeek,
    this.showTranslation = true,
    this.fontSize = 34,
    this.fontFamily,
    this.disableSeek = false,
    this.centered = false,
  });

  final Track track;
  final Duration position;
  final bool isPlaying;
  final ValueChanged<Duration> onSeek;
  final bool showTranslation;
  final double fontSize;
  final String? fontFamily;
  final bool disableSeek;

  /// 隐藏封面时歌词居中显示（对应 amll-centered）。
  final bool centered;

  @override
  State<LyricScrollView> createState() => _LyricScrollViewState();
}

class _LyricScrollViewState extends State<LyricScrollView> {
  final _scrollController = ScrollController();
  final _lineKeys = <int, GlobalKey>{};

  List<LyricLine> _lines = const [];
  late LyricTimeline _timeline;
  int _activeIndex = -1;

  @override
  void initState() {
    super.initState();
    _parseLines();
    _updateActiveIndex(initial: true);
  }

  @override
  void didUpdateWidget(covariant LyricScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final trackChanged = widget.track.key != oldWidget.track.key;
    final lyricsChanged =
        widget.track.lyric != oldWidget.track.lyric ||
        widget.track.yrc != oldWidget.track.yrc ||
        widget.track.tlyric != oldWidget.track.tlyric ||
        widget.track.ytlrc != oldWidget.track.ytlrc ||
        widget.showTranslation != oldWidget.showTranslation;
    if (trackChanged || lyricsChanged) {
      _parseLines();
    }
    if (widget.position != oldWidget.position ||
        trackChanged ||
        lyricsChanged) {
      _updateActiveIndex(initial: trackChanged);
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
    _timeline = LyricTimeline(_lines);
    _lineKeys.clear();
    for (var i = 0; i < _lines.length; i++) {
      _lineKeys[i] = GlobalKey();
    }
  }

  void _updateActiveIndex({bool initial = false}) {
    final lookup = lyricLookupPosition(widget.position);
    var index = _timeline.activeLineIndexAt(lookup);
    // activeLineIndexAt 在行间空隙返回 -1；保持上一行高亮以获得连续滚动。
    if (index < 0 && _lines.isNotEmpty) {
      index = _lastResolvedIndexAt(lookup);
    }
    if (index == _activeIndex && !initial) return;
    _activeIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToActive(animate: !initial);
    });
    if (mounted) setState(() {});
  }

  int _lastResolvedIndexAt(Duration position) {
    var candidate = -1;
    for (var i = 0; i < _lines.length; i++) {
      if (_lines[i].start <= position) {
        candidate = i;
      } else {
        break;
      }
    }
    return candidate;
  }

  void _scrollToActive({required bool animate}) {
    if (!_scrollController.hasClients) return;
    if (_activeIndex < 0) return;
    final key = _lineKeys[_activeIndex];
    final ctx = key?.currentContext;
    if (ctx == null) return;

    final box = ctx.findRenderObject() as RenderBox?;
    final viewport = context.findRenderObject() as RenderBox?;
    if (box == null || viewport == null) return;

    final linePosition = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final currentOffset = _scrollController.offset;
    // 对齐到约 32% 高度处（居中偏上）。
    final target =
        currentOffset +
        linePosition -
        viewport.size.height * (widget.centered ? 0.42 : 0.32);
    final clamped = target.clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );
    if (animate) {
      _scrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(clamped);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_lines.isEmpty) {
      return Center(
        child: Text(
          '这首歌还没有歌词',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 16,
            fontFamily: widget.fontFamily,
          ),
        ),
      );
    }

    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.white,
          Colors.white,
          Colors.transparent,
        ],
        stops: [0.0, 0.12, 0.82, 1.0],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: widget.centered ? 32 : 24,
          vertical: MediaQuery.sizeOf(context).height * 0.32,
        ),
        itemCount: _lines.length,
        itemBuilder: (context, index) {
          final line = _lines[index];
          final active = index == _activeIndex;
          return _LyricLineTile(
            key: _lineKeys[index],
            line: line,
            active: active,
            showTranslation: widget.showTranslation,
            fontSize: widget.fontSize,
            fontFamily: widget.fontFamily,
            centered: widget.centered,
            onTap: widget.disableSeek
                ? null
                : () {
                    widget.onSeek(playbackPositionForLyric(line.start));
                  },
          );
        },
      ),
    );
  }
}

class _LyricLineTile extends StatelessWidget {
  const _LyricLineTile({
    super.key,
    required this.line,
    required this.active,
    required this.showTranslation,
    required this.fontSize,
    required this.fontFamily,
    required this.centered,
    required this.onTap,
  });

  final LyricLine line;
  final bool active;
  final bool showTranslation;
  final double fontSize;
  final String? fontFamily;
  final bool centered;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final translation = line.translation;
    final align = centered ? TextAlign.center : TextAlign.start;
    final crossAxis = centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          style: TextStyle(
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.32),
            fontSize: active ? fontSize : fontSize * 0.88,
            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            height: 1.25,
            fontFamily: fontFamily,
          ),
          child: Column(
            crossAxisAlignment: crossAxis,
            children: [
              Text(line.text, textAlign: align),
              if (showTranslation &&
                  translation != null &&
                  translation.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    translation,
                    textAlign: align,
                    style: TextStyle(
                      color: active
                          ? Colors.white.withValues(alpha: 0.7)
                          : Colors.white.withValues(alpha: 0.24),
                      fontSize: fontSize * 0.6,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                      fontFamily: fontFamily,
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
