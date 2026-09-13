/// 把 [V2LyricPlayer] 的状态画出来。
///
/// 每一处绘制都对着 `lyric-player.module.css` / `index.css` 的具体声明：
/// - `.amll-lyric-player { mix-blend-mode: plus-lighter; overflow: hidden }`
/// - `.lyricLine { transform: translateY() scale(); transform-origin: left;
///    filter: blur() }`
/// - `.lyricMainLine > span` 的 `mask-image` 线性渐变 + `mask-position` 动画
/// - `.emphasize > span` 的 `matrix3d` 缩放位移与 `text-shadow` 辉光
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../player/lyric_line_el.dart';
import '../player/lyric_player.dart';
import 'line_layout.dart';
import 'metrics.dart';
import 'word_animations.dart';

class V2LyricPainter extends CustomPainter {
  V2LyricPainter({required this.player, required this.metrics})
    : super(repaint: player);

  final V2LyricPlayer player;
  final V2CssMetrics metrics;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    // `.amll-lyric-player { overflow: hidden; mix-blend-mode: plus-lighter }`
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.plus);
    canvas.clipRect(bounds);

    for (final el in player.currentLyricLineObjects) {
      if (!el.isInSight(size.height, player.overscanPx)) continue;
      _paintLine(canvas, size, el);
    }

    _paintInterludeDots(canvas, size);

    canvas.restore();
  }

  // ------------------------------------------------------------------ 行

  void _paintLine(Canvas canvas, Size size, V2LyricLineEl el) {
    final layout = el.layout;
    if (layout == null) return;
    final line = el.line;
    final top = el.posY.getCurrentPosition();
    final scale = el.scaleSpring.getCurrentPosition() / 100;
    final blur = el.blurValue.value;
    final lineHeight = layout.size.height;

    canvas.save();
    canvas.translate(0, top);

    // `transform-origin: left`（对唱行 `right`），纵向默认 50%
    final originX = line.isDuet ? size.width : 0.0;
    final originY = lineHeight / 2;
    canvas.translate(originX, originY);
    canvas.scale(scale);
    canvas.translate(-originX, -originY);

    // `filter: blur(Npx)`：CSS 的长度就是高斯标准差
    var layers = 0;
    if (blur > 0.01) {
      canvas.saveLayer(
        Rect.fromLTWH(
          -blur * 4,
          -blur * 4,
          size.width + blur * 8,
          lineHeight + blur * 8,
        ),
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: blur,
            sigmaY: blur,
            tileMode: TileMode.decal,
          ),
      );
      layers++;
    }

    // `.lyricBgLine { opacity: ... }`
    final lineOpacity = el.bgOpacity;
    if (lineOpacity < 0.999) {
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, size.width, lineHeight),
        Paint()..color = Color.fromRGBO(0, 0, 0, lineOpacity.clamp(0, 1)),
      );
      layers++;
    }

    _paintLineContent(canvas, el, layout);

    for (var i = 0; i < layers; i++) {
      canvas.restore();
    }
    canvas.restore();
  }

  void _paintLineContent(Canvas canvas, V2LyricLineEl el, V2LineLayout layout) {
    final contentX = layout.paddingLeft;
    var y = layout.paddingTop;

    // ---- `.lyricMainLine` ----
    final bright = el.brightMaskAlpha;
    final dark = el.darkMaskAlpha;
    // 缩放停在 97 以下时明暗遮罩同值，整行透明度恒定 —— 直接折进行级图层，
    // 省掉每个词一个 saveLayer。视觉上与逐词遮罩完全等价。
    final uniformMask = (bright - dark).abs() < 0.0005;
    final mainAlpha = el.mainOpacity.value.clamp(0.0, 1.0);
    final foldedAlpha =
        uniformMask &&
            layout.words.isNotEmpty &&
            layout.words.first.maskFrames.isNotEmpty
        ? mainAlpha * bright
        : mainAlpha;

    final mainRect = Rect.fromLTWH(
      contentX - metrics.fontSize,
      y - metrics.fontSize,
      layout.contentWidth + metrics.fontSize * 2,
      layout.mainSize.height + metrics.fontSize * 2,
    );
    final needMainLayer = foldedAlpha < 0.999;
    if (needMainLayer) {
      canvas.saveLayer(
        mainRect,
        Paint()..color = Color.fromRGBO(0, 0, 0, foldedAlpha),
      );
    }
    canvas.save();
    canvas.translate(contentX, y);
    for (final word in layout.words) {
      _paintWord(canvas, el, layout, word, uniformMask ? null : (bright, dark));
    }
    canvas.restore();
    if (needMainLayer) canvas.restore();

    y += layout.mainSize.height;

    // ---- `.lyricSubLine`（opacity: 0.3）----
    void paintSub(TextPainter? tp) {
      if (tp == null) return;
      final rect = Rect.fromLTWH(contentX, y, layout.contentWidth, tp.height);
      canvas.saveLayer(rect, Paint()..color = const Color(0x4D000000));
      tp.paint(
        canvas,
        Offset(
          el.line.isDuet ? contentX + layout.contentWidth - tp.width : contentX,
          y,
        ),
      );
      canvas.restore();
      y += tp.height;
    }

    paintSub(layout.translation);
    paintSub(layout.roman);
  }

  // ------------------------------------------------------------------ 词

  /// [maskAlphas] 为 null 表示遮罩已被折进行级图层，这里不再逐词处理。
  void _paintWord(
    Canvas canvas,
    V2LyricLineEl el,
    V2LineLayout layout,
    V2RenderWord word,
    (double, double)? maskAlphas,
  ) {
    final isBG = el.line.isBG;
    final em = metrics.lineFontSize(isBG);
    final floatY = word.float.translateYEm(el.elementTime) * em;

    canvas.save();
    canvas.translate(word.x, word.y + floatY);

    final padding = word.padding;
    final wordRect = Rect.fromLTWH(
      -padding,
      -padding,
      word.width + padding * 2,
      word.height + padding * 2,
    );

    final needLayer = maskAlphas != null && word.maskFrames.isNotEmpty;
    if (needLayer) canvas.saveLayer(wordRect, Paint());

    if (word.emphasize) {
      _paintEmphasizedChars(canvas, el, word, em);
    } else {
      word.painter?.paint(canvas, Offset.zero);
    }
    if (word.romanPainter != null) {
      word.romanPainter!.paint(canvas, Offset(0, metrics.lineTextHeight(isBG)));
    }

    if (needLayer) {
      final (bright, dark) = maskAlphas;
      final fadeWidth = word.height * player.wordFadeWidth;
      final progress = layout.totalFadeDuration <= 0
          ? 1.0
          : el.maskTime / layout.totalFadeDuration;
      final offset = evalMaskFrames(word.maskFrames, progress);
      // 渐变原点是元素的 border box 左边缘（文字左边缘往左 1em）
      final edge = word.width + padding + offset;
      final shader = ui.Gradient.linear(
        Offset(edge, 0),
        Offset(edge + math.max(0.01, fadeWidth), 0),
        <Color>[
          Color.fromRGBO(0, 0, 0, bright.clamp(0, 1)),
          Color.fromRGBO(0, 0, 0, dark.clamp(0, 1)),
        ],
      );
      canvas.drawRect(
        wordRect,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = shader,
      );
      canvas.restore();
    }

    canvas.restore();
  }

  void _paintEmphasizedChars(
    Canvas canvas,
    V2LyricLineEl el,
    V2RenderWord word,
    double em,
  ) {
    final emp = word.emp;
    final charHeight = metrics.lineTextHeight(el.line.isBG);
    for (final ch in word.chars) {
      final state = emp == null
          ? V2EmphasizeState.identity
          : emp.stateOf(ch.empIndex, el.elementTime);
      final cx = ch.x + ch.width / 2;
      final cy = charHeight / 2;

      canvas.save();
      // `transform: matrix3d(scale) translate(ox, oy)`，origin 50% 50%
      canvas.translate(cx, cy);
      canvas.scale(state.scale);
      canvas.translate(-cx, -cy);
      canvas.translate(state.offsetXEm * em, state.offsetYEm * em);
      // `emphasize-word-float`（composite: add）
      canvas.translate(0, state.floatYEm * em);

      // `text-shadow: 0 0 <blur>em rgba(255,255,255,<glow>)`
      if (state.glowAlpha > 0.01 && state.glowBlurEm > 0) {
        final sigma = (state.glowBlurEm * em) / 2;
        final spill = sigma * 4;
        canvas.saveLayer(
          Rect.fromLTWH(
            ch.x - spill,
            -spill,
            ch.width + spill * 2,
            charHeight + spill * 2,
          ),
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: sigma,
              sigmaY: sigma,
              tileMode: TileMode.decal,
            )
            ..colorFilter = ColorFilter.mode(
              Color.fromRGBO(255, 255, 255, state.glowAlpha.clamp(0, 1)),
              BlendMode.srcIn,
            ),
        );
        ch.painter.paint(canvas, Offset(ch.x, 0));
        canvas.restore();
      }

      ch.painter.paint(canvas, Offset(ch.x, 0));
      canvas.restore();
    }
  }

  // ------------------------------------------------------------- 间奏圆点

  void _paintInterludeDots(Canvas canvas, Size size) {
    final dots = player.interludeDots;
    if (!dots.enabled || dots.scale <= 0) return;
    final box = metrics.interludeDotsSize;
    final dotSize = metrics.interludeDotSize;
    final top = dots.top;

    canvas.save();
    canvas.translate(dots.left, top);
    // `transform-origin: center`
    canvas.translate(box.width / 2, box.height / 2);
    canvas.scale(dots.scale);
    canvas.translate(-box.width / 2, -box.height / 2);

    var x = metrics.interludeDotsPaddingX;
    final y = metrics.interludeDotsPaddingY;
    for (var i = 0; i < 3; i++) {
      final alpha = dots.dotOpacities[i].clamp(0.0, 1.0);
      if (alpha > 0.001) {
        canvas.drawCircle(
          Offset(x + dotSize / 2, y + dotSize / 2),
          dotSize / 2,
          Paint()..color = metrics.color.withValues(alpha: alpha),
        );
      }
      x +=
          dotSize +
          metrics.interludeDotsGap +
          V2CssMetrics.interludeDotMarginRight;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant V2LyricPainter oldDelegate) =>
      oldDelegate.player != player || oldDelegate.metrics != metrics;
}
