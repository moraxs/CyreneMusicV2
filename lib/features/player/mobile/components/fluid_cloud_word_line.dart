/// 流体云样式的「当前行」逐字动画组件。
///
/// 直接复用 AppleMusic（AMLL）的绘制管线：`layoutLyricLine` 排版 +
/// [solveWordAnimations] 解算（词级浮动 / 长词强调 / 软边渐变遮罩）+
/// [LyricLinePainter] 绘制。这样流体云与 AppleMusic 共用同一套逐字动画，
/// 不再是流体云早期那套硬边渐变填充，滚动/点亮不再突兀。
///
/// 与 AMLL 面板的区别仅在于：这里只渲染单独一行，纵向滚动、缩放、透明度、
/// 模糊都交给外层的流体云弹性行处理；并额外支持按视觉行居中（全屏歌词页用），
/// AMLL 引擎本身只有左/右对齐。
///
/// **未点亮的行也必须走这里**（[FluidCloudWordLine.active] = false）：本管线
/// 是逐词测量 + 只在词边界折行，和 Flutter `Text` 自己的断行结果并不一致
/// （逐词宽度求和略宽、行尾空格也算进宽度），两者混用会让同一句歌词在
/// 「点亮前」和「点亮后」折行位置不同，滚动到该行时突然重排。统一由
/// [fluidCloudLineLayout] 排版后，两种状态的折行与高度完全一致。
library;

import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../amll/core/fade_mask.dart';
import '../../amll/core/lyric_types.dart';
import '../../amll/render/lyric_line_layout.dart';
import '../../amll/render/lyric_line_painter.dart';
import '../compat/lyric_line.dart';
import '../compat/player_service.dart';

/// 未唱词的暗态透明度，沿用流体云原本的 0x99FFFFFF ≈ 0.6，
/// 保持流体云的观感，只把动画换成 AMLL 那套。
const double _kFluidDarkAlpha = 0.6;

/// 未点亮行（非活跃行）的文字透明度。
///
/// 原本非活跃行用 `Text` 自带颜色画，alpha 由外层给（面板 0.3 / 全屏 0.35）；
/// 改走绘制管线后由这里统一给，取原来两者的中值，观感不变。
const double _kInactiveAlpha = 0.32;

/// 行末兜底时长（无逐字末词、无 lineDuration、无下一行时）
const int _kFallbackLineDurationMs = 5000;

class FluidCloudWordLine extends StatefulWidget {
  const FluidCloudWordLine({
    super.key,
    required this.lyric,
    required this.textStyle,
    this.active = true,
    this.centered = false,
    this.enableGlow = true,
    this.wordFadeWidth = 0.5,
    this.baseColor = const Color(0xFFFFFFFF),
    this.inactiveAlpha = _kInactiveAlpha,
    this.fallbackMaxWidth = 320,
    this.positionListenable,
  });

  /// 要渲染的歌词行
  final LyricLine lyric;

  /// 是否为当前活跃行。
  ///
  /// true 走逐字渐变 + 词级动画；false 只按同一份排版画纯暗态文字
  /// （不起 ticker、不解算动画）。两者共用排版，因此点亮前后折行一致。
  final bool active;

  /// 主歌词文字样式（字号即 em 基准，字体、字重、行高都取自它）
  final TextStyle textStyle;

  /// 是否按视觉行居中（全屏歌词页 true；主播放器面板 false，走左对齐）
  final bool centered;

  /// 是否绘制长词强调辉光
  final bool enableGlow;

  /// 词渐变过渡带宽度（相对词高的倍数）。AMLL 默认 0.5，tauri 端 1.0。
  final double wordFadeWidth;

  /// 文字基色
  final Color baseColor;

  /// [active] = false 时的文字透明度
  final double inactiveAlpha;

  /// 约束无界时的兜底最大宽度
  final double fallbackMaxWidth;

  /// Optional playback clock used by isolated players such as SuperCyrene.
  ///
  /// Legacy mobile layouts omit this and continue to use [PlayerService].
  /// Passing the clock explicitly prevents the active-line selector and the
  /// word painter from reading different playback positions.
  final ValueListenable<Duration>? positionListenable;

  @override
  State<FluidCloudWordLine> createState() => _FluidCloudWordLineState();
}

/// 一行歌词的排版 + 动画解算结果。
///
/// 动画解算按需触发（未点亮的行只需要排版），排版本身在构造时完成。
class FluidCloudLineSolution {
  FluidCloudLineSolution._(
    this._lineWords,
    this._wordFadeWidth, {
    required this.layout,
    required this.lineStartMs,
    required this.lineEndMs,
  });

  /// 排版结果（点亮前后共用，保证折行一致）
  final LyricLineLayout layout;

  /// 行开始 / 结束时间（毫秒）
  final int lineStartMs;
  final int lineEndMs;

  final List<AmllLyricWord> _lineWords;
  final double _wordFadeWidth;

  List<WordAnimations>? _animations;
  int? _fadeDurationMs;

  /// 内容高度（含折行）
  double get height => layout.size.height;

  /// 逐词动画解算，首次访问时计算
  List<WordAnimations> get animations => _animations ??= solveWordAnimations(
    layout: layout,
    lineStartTime: lineStartMs,
    lineEndTime: lineEndMs,
    lineWords: _lineWords,
    isBG: false,
    wordFadeWidth: _wordFadeWidth,
  );

  /// 整行渐变总时长（毫秒，至少 1）
  int get fadeDurationMs => _fadeDurationMs ??= math.max(
    1,
    lineFadeDuration(
      words: layout.words
          .map(
            (w) => FadeMaskWord(
              startTime: w.word.startTime,
              endTime: w.word.endTime,
              width: w.size.width,
            ),
          )
          .toList(),
      lineStartTime: lineStartMs,
      lineEndTime: lineEndMs,
    ),
  );
}

/// Paint-only animation driver used by the active lyric line.
///
/// Listening through [CustomPainter.repaint] bypasses build and layout for
/// every animation tick. Only the paint phase runs while the word mask moves.
class FluidCloudAnimatedLinePainter extends CustomPainter {
  FluidCloudAnimatedLinePainter({
    required this.timeMs,
    required this.solution,
    required this.textStyle,
    required this.brightAlpha,
    required this.darkAlpha,
    required this.baseColor,
    required this.enableGlow,
  }) : super(repaint: timeMs);

  final ValueListenable<int> timeMs;
  final FluidCloudLineSolution solution;
  final TextStyle textStyle;
  final double brightAlpha;
  final double darkAlpha;
  final Color baseColor;
  final bool enableGlow;

  double get relativeTimeMs => (timeMs.value - solution.lineStartMs).toDouble();

  double get fadeProgress {
    final relative = relativeTimeMs;
    if (relative <= 0) return 0;
    if (relative >= solution.fadeDurationMs) return 1;
    return relative / solution.fadeDurationMs;
  }

  @override
  void paint(Canvas canvas, Size size) {
    LyricLinePainter(
      layout: solution.layout,
      animations: solution.animations,
      textStyle: textStyle,
      relativeTimeMs: relativeTimeMs,
      fadeProgress: fadeProgress,
      brightAlpha: brightAlpha,
      darkAlpha: darkAlpha,
      baseColor: baseColor,
      renderMode: LyricLineRenderMode.gradient,
      enableGlow: enableGlow,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant FluidCloudAnimatedLinePainter oldDelegate) =>
      oldDelegate.timeMs != timeMs ||
      oldDelegate.solution != solution ||
      oldDelegate.textStyle != textStyle ||
      oldDelegate.brightAlpha != brightAlpha ||
      oldDelegate.darkAlpha != darkAlpha ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.enableGlow != enableGlow;
}

/// 把项目的单行歌词转成 AMLL 引擎行。
///
/// 行结束时间优先取逐字末词的结束时间，其次 lineDuration，最后兜底 5s。
AmllLyricLine _toAmllLine(LyricLine lyric) {
  final startMs = lyric.startTime.inMilliseconds;
  final fallbackEndMs =
      startMs +
      ((lyric.lineDuration != null && lyric.lineDuration! > Duration.zero)
          ? lyric.lineDuration!.inMilliseconds
          : _kFallbackLineDurationMs);

  final words = <AmllLyricWord>[];
  var latestEnd = startMs;
  if (lyric.hasWordByWord) {
    for (final w in lyric.words!) {
      final s = w.startTime.inMilliseconds;
      final e = w.endTime.inMilliseconds;
      words.add(AmllLyricWord(word: w.text, startTime: s, endTime: e));
      if (e > latestEnd) latestEnd = e;
    }
  } else {
    words.addAll(
      _evenlyTimedGraphemes(
        lyric.text,
        startTimeMs: startMs,
        endTimeMs: fallbackEndMs,
      ),
    );
    latestEnd = fallbackEndMs;
  }

  int endMs;
  if (latestEnd > startMs) {
    endMs = latestEnd;
  } else if (fallbackEndMs > startMs) {
    endMs = fallbackEndMs;
  } else {
    endMs = startMs + _kFallbackLineDurationMs;
  }

  return AmllLyricLine(words: words, startTime: startMs, endTime: endMs);
}

/// Creates approximate word timing for plain LRC lines.
///
/// Every visible grapheme receives an equal slice of the line duration. Spaces
/// are attached to the preceding grapheme so they keep the original layout but
/// do not introduce a visually empty animation step.
List<AmllLyricWord> _evenlyTimedGraphemes(
  String text, {
  required int startTimeMs,
  required int endTimeMs,
}) {
  final tokens = <String>[];
  for (final grapheme in text.characters) {
    if (grapheme.trim().isEmpty && tokens.isNotEmpty) {
      tokens[tokens.length - 1] += grapheme;
    } else {
      tokens.add(grapheme);
    }
  }

  if (tokens.isEmpty) return const [];
  final durationMs = math.max(1, endTimeMs - startTimeMs);
  return List<AmllLyricWord>.generate(tokens.length, (index) {
    final wordStart =
        startTimeMs + (durationMs * index / tokens.length).round();
    final wordEnd =
        startTimeMs + (durationMs * (index + 1) / tokens.length).round();
    return AmllLyricWord(
      word: tokens[index],
      startTime: wordStart,
      endTime: math.max(wordStart + 1, wordEnd),
    );
  }, growable: false);
}

/// 解算（并缓存）一行歌词的流体云排版。
///
/// 面板的高度测量、未点亮行的绘制、活跃行的逐字动画都必须走这一个入口，
/// 三者才会得到完全一致的折行与高度。
FluidCloudLineSolution fluidCloudLineLayout({
  required LyricLine lyric,
  required TextStyle textStyle,
  required double maxWidth,
  bool centered = false,
  double wordFadeWidth = 0.5,
}) {
  // 宽度取整到 0.5px：LayoutBuilder 给的宽度会有亚像素抖动，
  // 不量化会让缓存永远打不中。
  final quantizedWidth = (maxWidth * 2).roundToDouble() / 2;
  final key = _SolutionKey(
    lineKey: Object.hash(
      lyric.startTime.inMilliseconds,
      lyric.text,
      lyric.lineDuration?.inMilliseconds,
      Object.hashAll(
        lyric.words?.map(
              (word) => Object.hash(
                word.text,
                word.startTime.inMilliseconds,
                word.duration.inMilliseconds,
              ),
            ) ??
            const <Object>[],
      ),
    ),
    style: textStyle,
    maxWidth: quantizedWidth,
    centered: centered,
    wordFadeWidth: wordFadeWidth,
  );

  final cached = _solutionCache.remove(key);
  if (cached != null) {
    _solutionCache[key] = cached; // 标记为最近使用
    return cached;
  }

  final line = _toAmllLine(lyric);
  var layout = layoutLyricLine(
    line: line,
    textStyle: textStyle,
    maxWidth: quantizedWidth,
    isNonDynamic: false,
  );
  if (centered) layout = _centerLayout(layout, quantizedWidth);

  final solution = FluidCloudLineSolution._(
    line.words,
    wordFadeWidth,
    layout: layout,
    lineStartMs: line.startTime,
    lineEndMs: line.endTime,
  );

  if (_solutionCache.length >= _kSolutionCacheMax) {
    for (final k
        in _solutionCache.keys.take(_kSolutionCacheMax ~/ 4).toList()) {
      _solutionCache.remove(k);
    }
  }
  _solutionCache[key] = solution;
  return solution;
}

/// 把每个视觉行整体水平居中（AMLL 引擎只有左/右对齐，居中在这里补）。
LyricLineLayout _centerLayout(LyricLineLayout layout, double containerWidth) {
  if (layout.words.isEmpty) return layout;

  // 每个视觉行的右边缘 = 该行的行宽
  final lineRight = <int, double>{};
  for (final w in layout.words) {
    final r = w.right;
    final cur = lineRight[w.lineIndex];
    if (cur == null || r > cur) lineRight[w.lineIndex] = r;
  }

  final shifted = layout.words.map((w) {
    final width = lineRight[w.lineIndex] ?? 0;
    final shift = math.max(0.0, (containerWidth - width) / 2);
    if (shift <= 0) return w;
    return LaidOutWord(
      word: w.word,
      text: w.text,
      offset: Offset(w.offset.dx + shift, w.offset.dy),
      size: w.size,
      lineIndex: w.lineIndex,
      shouldEmphasize: w.shouldEmphasize,
      graphemes: w.graphemes,
      romanWord: w.romanWord,
    );
  }).toList();

  return LyricLineLayout(
    words: shifted,
    size: Size(containerWidth, layout.size.height),
    lineCount: layout.lineCount,
    lineHeight: layout.lineHeight,
    isNonDynamic: layout.isNonDynamic,
    plainText: layout.plainText,
    textAlign: layout.textAlign,
  );
}

const int _kSolutionCacheMax = 256;

final LinkedHashMap<_SolutionKey, FluidCloudLineSolution> _solutionCache =
    LinkedHashMap<_SolutionKey, FluidCloudLineSolution>();

class _SolutionKey {
  const _SolutionKey({
    required this.lineKey,
    required this.style,
    required this.maxWidth,
    required this.centered,
    required this.wordFadeWidth,
  });

  final int lineKey;
  final TextStyle style;
  final double maxWidth;
  final bool centered;
  final double wordFadeWidth;

  @override
  bool operator ==(Object other) =>
      other is _SolutionKey &&
      other.lineKey == lineKey &&
      other.style == style &&
      other.maxWidth == maxWidth &&
      other.centered == centered &&
      other.wordFadeWidth == wordFadeWidth;

  @override
  int get hashCode =>
      Object.hash(lineKey, style, maxWidth, centered, wordFadeWidth);
}

class _FluidCloudWordLineState extends State<FluidCloudWordLine>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;

  /// 每帧写入的绘制时间（毫秒，带外推）。用 ValueNotifier 只触发重绘、
  /// 不触发 build，避免逐帧重排版。
  final ValueNotifier<int> _timeMs = ValueNotifier<int>(0);

  // 进度外推：PlayerService.position 更新频率低于帧率，用上一次同步点 +
  // 已过时间补偿，避免逐字动画抖动（与 AMLL / 旧卡拉OK 组件一致）。
  Duration _lastSyncPos = Duration.zero;
  Duration _lastSyncElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.active) _startTicker();
  }

  @override
  void didUpdateWidget(FluidCloudWordLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 点亮 / 熄灭时起停 ticker：未点亮的行没有逐帧内容，不该占一个 ticker
    if (widget.active && !oldWidget.active) {
      _startTicker();
    } else if (!widget.active && oldWidget.active) {
      _ticker
        ?..stop()
        ..dispose();
      _ticker = null;
    } else if (widget.active &&
        oldWidget.positionListenable != widget.positionListenable) {
      _syncTime(_position, Duration.zero);
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _timeMs.dispose();
    super.dispose();
  }

  void _startTicker() {
    _syncTime(_position, Duration.zero);
    _ticker = createTicker(_onTick)..start();
  }

  Duration get _position =>
      widget.positionListenable?.value ?? PlayerService().position;

  void _syncTime(Duration pos, Duration elapsed) {
    _lastSyncPos = pos;
    _lastSyncElapsed = elapsed;
    _timeMs.value = pos.inMilliseconds;
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final pos = _position;
    if (pos != _lastSyncPos) {
      _lastSyncPos = pos;
      _lastSyncElapsed = elapsed;
    }

    var extrapolated = pos;
    if (PlayerService().isPlaying) {
      final since = elapsed - _lastSyncElapsed;
      if (since > Duration.zero && since < const Duration(milliseconds: 500)) {
        extrapolated = pos + since;
      }
    }

    final ms = extrapolated.inMilliseconds;
    if (ms != _timeMs.value) _timeMs.value = ms;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.hasBoundedWidth && constraints.maxWidth > 0
            ? constraints.maxWidth
            : widget.fallbackMaxWidth;

        final solution = fluidCloudLineLayout(
          lyric: widget.lyric,
          textStyle: widget.textStyle,
          maxWidth: maxWidth,
          centered: widget.centered,
          wordFadeWidth: widget.wordFadeWidth,
        );
        final layout = solution.layout;
        // 居中时占满可用宽度，让视觉行相对整幅居中；左对齐时用内容宽即可。
        final paintWidth = widget.centered ? maxWidth : layout.size.width;
        final size = Size(paintWidth, layout.size.height);

        // 未点亮：同一份排版画静态暗态文字，不解算动画、不订阅时间
        if (!widget.active) {
          return SizedBox.fromSize(
            size: size,
            child: CustomPaint(
              size: size,
              isComplex: true,
              willChange: false,
              painter: LyricLinePainter(
                layout: layout,
                animations: const [],
                textStyle: widget.textStyle,
                relativeTimeMs: 0,
                fadeProgress: 0,
                brightAlpha: widget.inactiveAlpha,
                darkAlpha: widget.inactiveAlpha,
                baseColor: widget.baseColor,
                renderMode: LyricLineRenderMode.solid,
                enableGlow: false,
              ),
            ),
          );
        }

        return SizedBox.fromSize(
          size: size,
          child: CustomPaint(
            size: size,
            isComplex: true,
            willChange: true,
            painter: FluidCloudAnimatedLinePainter(
              timeMs: _timeMs,
              solution: solution,
              textStyle: widget.textStyle,
              brightAlpha: 1.0,
              darkAlpha: _kFluidDarkAlpha,
              baseColor: widget.baseColor,
              enableGlow: widget.enableGlow,
            ),
          ),
        );
      },
    );
  }
}
