/// 歌词行的绘制。
///
/// 一行歌词的视觉由几层叠加而成，与 AMLL 的 DOM 实现一一对应：
/// - 底色：暗态文字（`--dark-mask-alpha`）
/// - 亮层：随播放进度由左向右推进的渐变遮罩（`--bright-mask-alpha`）
/// - 词级浮动：每个词在自己的时间窗内上浮 0.05em
/// - 长词强调：逐字素缩放、位移与辉光
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/fade_mask.dart';
import '../core/lyric_types.dart';
import '../core/word_animation.dart';
import 'lyric_line_layout.dart';
import 'text_cache.dart';

/// 一个词的动画解算集合，随排版结果一起缓存。
class WordAnimations {
  const WordAnimations({
    required this.float,
    required this.emphasis,
    required this.fadeMask,
  });

  final WordFloatAnimation float;

  /// 仅强调词有
  final EmphasisAnimation? emphasis;

  /// 逐词渐变遮罩解算
  final FadeMaskSolution fadeMask;
}

/// 逐词解算浮动、强调与渐变遮罩。
///
/// 从 [AmllLyricLineView] 内部抽出的纯函数，供 AMLL 与流体云样式共用。
/// 遮罩必须按「视觉行」分组解算：折行后每一行都是独立的水平扫描，
/// 混在一起算会让第二行提前点亮。
List<WordAnimations> solveWordAnimations({
  required LyricLineLayout layout,
  required int lineStartTime,
  required int lineEndTime,
  required List<AmllLyricWord> lineWords,
  required bool isBG,
  required double wordFadeWidth,
}) {
  if (layout.words.isEmpty) return const [];

  final result = List<WordAnimations?>.filled(layout.words.length, null);

  // 该词是否包含行内最后一个词（命中后强调幅度加强）。
  bool isLastWordOfLine(AmllLyricWord word) {
    if (lineWords.isEmpty) return false;
    final lastWord = lineWords.last.word;
    if (lastWord.isEmpty) return false;
    return word.word.contains(lastWord);
  }

  // 按视觉行分组
  final byLine = <int, List<int>>{};
  for (var i = 0; i < layout.words.length; i++) {
    byLine.putIfAbsent(layout.words[i].lineIndex, () => <int>[]).add(i);
  }

  for (final indices in byLine.values) {
    final maskWords = indices
        .map(
          (i) => FadeMaskWord(
            startTime: layout.words[i].word.startTime,
            endTime: layout.words[i].word.endTime,
            width: layout.words[i].size.width,
          ),
        )
        .toList();

    final solutions = solveLineFadeMask(
      words: maskWords,
      lineStartTime: lineStartTime,
      lineEndTime: lineEndTime,
      wordHeight: layout.lineHeight,
      wordFadeWidth: wordFadeWidth,
    );

    for (var k = 0; k < indices.length; k++) {
      final i = indices[k];
      final word = layout.words[i];

      result[i] = WordAnimations(
        float: WordFloatAnimation.forWord(
          word.word,
          lineStartTime,
          isBG: isBG,
        ),
        emphasis: word.shouldEmphasize
            ? EmphasisAnimation.forWord(
                durationMs: word.word.endTime - word.word.startTime,
                delayMs: word.word.startTime - lineStartTime,
                charCount: word.graphemes.length,
                rubyCharCount: word.word.ruby.fold(
                  0,
                  (sum, r) => sum + r.word.length,
                ),
                isLastWordOfLine: isLastWordOfLine(word.word),
                isBG: isBG,
              )
            : null,
        fadeMask: solutions[k],
      );
    }
  }

  return result.map((e) => e!).toList();
}

/// 绘制一行歌词。
///
/// 无状态：所有随时间变化的量都由构造参数传入，因此可安全地被
/// [RepaintBoundary] 复用，且 [shouldRepaint] 能精确判断。
class LyricLinePainter extends CustomPainter {
  const LyricLinePainter({
    required this.layout,
    required this.animations,
    required this.textStyle,
    required this.relativeTimeMs,
    required this.fadeProgress,
    required this.brightAlpha,
    required this.darkAlpha,
    required this.baseColor,
    required this.renderMode,
    required this.enableGlow,
    this.groupOpacity = 1.0,
  });

  /// 排版结果
  final LyricLineLayout layout;

  /// 与 [LyricLineLayout.words] 一一对应的动画解算
  final List<WordAnimations> animations;

  /// 主歌词文字样式（字号即 em 基准）
  final TextStyle textStyle;

  /// 相对歌词行开始时间的当前时间（毫秒）
  final double relativeTimeMs;

  /// 整行渐变进度，0..1
  final double fadeProgress;

  /// 亮态文字的透明度
  final double brightAlpha;

  /// 暗态文字的透明度
  final double darkAlpha;

  /// 文字基色（通常为白）
  final Color baseColor;

  final LyricLineRenderMode renderMode;

  /// 是否绘制强调辉光（性能敏感时可关）
  final bool enableGlow;

  /// 所属组的整体不透明度。
  ///
  /// 直接乘进文字颜色，而不是在外层套 [Opacity] —— 后者每帧都会触发
  /// `saveLayer`（离屏缓冲），是逐帧动画里代价很高的一步。
  final double groupOpacity;

  double get _fontSize => textStyle.fontSize ?? 24;

  @override
  void paint(Canvas canvas, Size size) {
    // 逐行歌词：整行一次绘制，只受 alpha 影响
    if (layout.isNonDynamic) {
      final alpha = renderMode == LyricLineRenderMode.gradient
          ? brightAlpha
          : darkAlpha;
      _drawText(
        canvas,
        layout.plainText,
        Offset.zero,
        baseColor.withValues(alpha: (alpha * groupOpacity).clamp(0.0, 1.0)),
        maxWidth: size.width,
        textAlign: layout.textAlign,
      );
      return;
    }

    for (var i = 0; i < layout.words.length; i++) {
      final word = layout.words[i];
      final anim = i < animations.length ? animations[i] : null;
      _paintWord(canvas, word, anim);
    }
  }

  void _paintWord(Canvas canvas, LaidOutWord word, WordAnimations? anim) {
    // 词级浮动
    final floatOffsetPx =
        (anim?.float.offsetEmAt(relativeTimeMs) ?? 0) * _fontSize;

    canvas.save();
    canvas.translate(word.offset.dx, word.offset.dy + floatOffsetPx);

    if (word.shouldEmphasize && word.graphemes.isNotEmpty) {
      _paintEmphasizedWord(canvas, word, anim);
    } else {
      _paintSimpleWord(canvas, word, anim);
    }

    canvas.restore();
  }

  /// 计算词内某个 x 处的「亮度」：0 = 全暗，1 = 全亮。
  double _brightnessAt(WordAnimations? anim, double x) {
    if (renderMode != LyricLineRenderMode.gradient || anim == null) return 0;
    final brightEdge = anim.fadeMask.brightEdgeAt(fadeProgress);
    final darkEdge = anim.fadeMask.darkEdgeAt(fadeProgress);
    if (x <= brightEdge) return 1;
    if (x >= darkEdge) return 0;
    final span = darkEdge - brightEdge;
    if (span <= 0) return 0;
    return 1 - (x - brightEdge) / span;
  }

  /// 把亮度映射成实际颜色（已乘入组的整体不透明度）。
  Color _colorFor(double brightness) {
    final alpha = darkAlpha + (brightAlpha - darkAlpha) * brightness;
    return baseColor.withValues(
      alpha: (alpha * groupOpacity).clamp(0.0, 1.0),
    );
  }

  void _paintSimpleWord(Canvas canvas, LaidOutWord word, WordAnimations? anim) {
    if (renderMode != LyricLineRenderMode.gradient || anim == null) {
      final color = _colorFor(0);
      _drawText(canvas, word.text, Offset.zero, color);
      _paintRoman(canvas, word, color);
      return;
    }

    final brightEdge = anim.fadeMask.brightEdgeAt(fadeProgress);
    final darkEdge = anim.fadeMask.darkEdgeAt(fadeProgress);

    // 分界完全在词外时省掉 shader，直接单色绘制
    if (darkEdge <= 0) {
      final color = _colorFor(0);
      _drawText(canvas, word.text, Offset.zero, color);
      _paintRoman(canvas, word, color);
      return;
    }
    if (brightEdge >= word.size.width) {
      final color = _colorFor(1);
      _drawText(canvas, word.text, Offset.zero, color);
      _paintRoman(canvas, word, color);
      return;
    }

    // 过渡带横跨该词：用线性渐变一次绘制
    final rect = Rect.fromLTWH(0, 0, word.size.width, word.size.height);
    final shader = _buildFadeShader(rect, brightEdge, darkEdge);
    _drawTextWithPaint(
      canvas,
      word.text,
      Offset.zero,
      baseColor,
      shader: shader,
    );
    _paintRoman(
      canvas,
      word,
      _colorFor(_brightnessAt(anim, word.size.width / 2)),
    );
  }

  /// 构造亮→暗的水平渐变 shader。
  Shader _buildFadeShader(Rect rect, double brightEdge, double darkEdge) {
    final width = rect.width <= 0 ? 1.0 : rect.width;
    final start = (brightEdge / width).clamp(0.0, 1.0);
    final rawEnd = (darkEdge / width).clamp(0.0, 1.0);
    // stops 必须严格递增
    final end = rawEnd <= start ? math.min(1.0, start + 1e-4) : rawEnd;

    final bright = baseColor.withValues(
      alpha: (brightAlpha * groupOpacity).clamp(0.0, 1.0),
    );
    final dark = baseColor.withValues(
      alpha: (darkAlpha * groupOpacity).clamp(0.0, 1.0),
    );

    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[bright, bright, dark, dark],
      stops: <double>[0.0, start, end, 1.0],
    ).createShader(rect);
  }

  void _paintEmphasizedWord(
    Canvas canvas,
    LaidOutWord word,
    WordAnimations? anim,
  ) {
    final emphasis = anim?.emphasis;

    for (var i = 0; i < word.graphemes.length; i++) {
      final g = word.graphemes[i];
      final state = emphasis?.stateAt(relativeTimeMs, i) ?? EmphasisState.none;
      final brightness = _brightnessAt(anim, g.offset.dx + g.size.width / 2);

      canvas.save();
      // 以字素中心为锚点缩放，再叠加强调位移
      final cx = g.offset.dx + g.size.width / 2;
      final cy = g.offset.dy + g.size.height / 2;
      canvas.translate(
        cx + state.offsetXEm * _fontSize,
        cy + state.offsetYEm * _fontSize,
      );
      canvas.scale(state.scale);
      canvas.translate(-cx, -cy);

      final glowAlpha = state.glowAlpha * brightness;
      if (enableGlow && glowAlpha > 0.01 && state.glowRadiusEm > 0) {
        _drawTextWithPaint(
          canvas,
          g.text,
          g.offset,
          const Color(0x00000000),
          shadow: Shadow(
            color: const Color(0xFFFFFFFF).withValues(
              alpha: glowAlpha.clamp(0.0, 1.0),
            ),
            blurRadius: state.glowRadiusEm * _fontSize,
          ),
        );
      }

      _drawText(canvas, g.text, g.offset, _colorFor(brightness));
      canvas.restore();
    }

    _paintRoman(
      canvas,
      word,
      _colorFor(_brightnessAt(anim, word.size.width / 2)),
    );
  }

  void _paintRoman(Canvas canvas, LaidOutWord word, Color color) {
    if (word.romanWord.isEmpty) return;
    final paragraph = LyricTextCache.instance.paragraph(
      text: word.romanWord,
      style: textStyle.copyWith(
        fontSize: _fontSize * 0.5,
        fontWeight: FontWeight.normal,
        height: 1.0,
      ),
      color: color,
    );
    // 音译绘制在词的上方
    canvas.drawParagraph(paragraph, Offset(0, -paragraph.height));
  }

  /// 绘制纯色文字，走段落缓存（热路径）。
  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color, {
    double? maxWidth,
    TextAlign textAlign = TextAlign.left,
  }) {
    if (text.isEmpty) return;
    final paragraph = LyricTextCache.instance.paragraph(
      text: text,
      style: textStyle,
      color: color,
      maxWidth: maxWidth ?? double.infinity,
      textAlign: textAlign,
    );
    canvas.drawParagraph(paragraph, offset);
  }

  /// 绘制带 shader 或阴影的文字。
  ///
  /// 这条路径不能走段落缓存（shader 依赖具体 Rect，辉光每帧都在变），
  /// 但触发频率很低：一行内同一时刻只有一个词处于渐变过渡带内，
  /// 辉光也只在长词强调期间出现。
  void _drawTextWithPaint(
    Canvas canvas,
    String text,
    Offset offset,
    Color color, {
    Shader? shader,
    Shadow? shadow,
  }) {
    if (text.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: textStyle.copyWith(
          color: shader == null ? color : null,
          foreground: shader == null ? null : (Paint()..shader = shader),
          shadows: shadow == null ? const <Shadow>[] : <Shadow>[shadow],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
    painter.dispose();
  }

  @override
  bool shouldRepaint(LyricLinePainter old) {
    return old.relativeTimeMs != relativeTimeMs ||
        old.fadeProgress != fadeProgress ||
        old.brightAlpha != brightAlpha ||
        old.darkAlpha != darkAlpha ||
        old.renderMode != renderMode ||
        old.layout != layout ||
        old.textStyle != textStyle ||
        old.baseColor != baseColor ||
        old.enableGlow != enableGlow ||
        old.groupOpacity != groupOpacity;
  }
}
