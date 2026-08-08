import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../mobile/compat/lyric_line.dart';
import '../../mobile/components/fluid_cloud_word_line.dart';
import 'default_article.dart';
import 'default_style.dart';
import 'default_timeline.dart';
import 'default_types.dart';

class SuperCyreneDefaultCanvas extends StatefulWidget {
  const SuperCyreneDefaultCanvas({
    super.key,
    required this.lines,
    required this.position,
  });

  final List<DefaultLine> lines;
  final ValueListenable<Duration> position;

  @override
  State<SuperCyreneDefaultCanvas> createState() =>
      _SuperCyreneDefaultCanvasState();
}

class _SuperCyreneDefaultCanvasState extends State<SuperCyreneDefaultCanvas>
    with SingleTickerProviderStateMixin {
  late final AnimationController _frames;
  DefaultArticleLayout? _article;
  DefaultCamera? _camera;
  Size _layoutSize = Size.zero;
  Duration? _lastFrame;
  int _cameraSourceLine = -1;
  double _retargetStartedAt = 0;
  double _retargetDuration = .09;

  @override
  void initState() {
    super.initState();
    _frames = AnimationController(
      vsync: this,
      duration: const Duration(days: 1),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant SuperCyreneDefaultCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lines, widget.lines)) {
      _article = null;
      _camera = null;
    }
  }

  @override
  void dispose() {
    _frames.dispose();
    super.dispose();
  }

  void _ensureLayout(Size size) {
    if (_article != null && _layoutSize == size) return;
    _layoutSize = size;
    _article = buildDefaultArticleLayout(widget.lines, size);
    final article = _article;
    if (article != null) {
      _camera = DefaultCamera(x: article.width * .5, y: article.height * .5);
      _cameraSourceLine = -1;
      _lastFrame = null;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      _ensureLayout(size);
      final article = _article;
      return AnimatedBuilder(
        // The camera needs a frame-rate ticker. Playback position does not need
        // to rebuild this layer separately because the next frame reads its
        // latest value anyway.
        animation: _frames,
        child: article == null
            ? null
            : _SuperCyreneArticle(
                article: article,
                lines: widget.lines,
                position: widget.position,
              ),
        builder: (context, child) {
          final camera = _camera;
          if (article == null || camera == null) return const SizedBox.expand();
          final elapsed = _frames.lastElapsedDuration ?? Duration.zero;
          final dt = _lastFrame == null
              ? 1 / 60
              : defaultClamp(
                  (elapsed - _lastFrame!).inMicroseconds / 1000000,
                  1 / 240,
                  .05,
                );
          _lastFrame = elapsed;
          final time = widget.position.value.inMicroseconds / 1000000 + .3;
          _updateCamera(article, camera, size, time, elapsed, dt);
          return _buildCameraLayer(article, camera, size, child!);
        },
      );
    },
  );

  Widget _buildCameraLayer(
    DefaultArticleLayout article,
    DefaultCamera camera,
    Size viewport,
    Widget articleChild,
  ) {
    return ClipRect(
      child: Transform.translate(
        offset: Offset(viewport.width * .5, viewport.height * .5),
        child: Transform.scale(
          scale: camera.scale,
          alignment: Alignment.topLeft,
          child: Transform.translate(
            offset: Offset(-camera.x, -camera.y),
            child: SizedBox(
              width: article.width,
              height: article.height,
              child: articleChild,
            ),
          ),
        ),
      ),
    );
  }

  void _updateCamera(
    DefaultArticleLayout article,
    DefaultCamera camera,
    Size viewport,
    double time,
    Duration elapsed,
    double dt,
  ) {
    final lineIndex = findDefaultTimelineLine(widget.lines, time);
    var focusBlock = lineIndex >= 0
        ? article.blockBySourceLineIndex[lineIndex]
        : null;
    focusBlock ??= article.chronologicalBlocks.isEmpty
        ? null
        : article.chronologicalBlocks.first;
    var targetX = article.width * .5;
    var targetY = article.height * .5;
    var targetScale = 1.18;

    final lastLine = article.chronologicalBlocks.isEmpty
        ? null
        : article.chronologicalBlocks.last.line;
    final overviewStart = lastLine == null
        ? double.infinity
        : lastLine.startTime +
              math.max(lastLine.endTime - lastLine.startTime, 0) * .5;
    final overview = time >= overviewStart;

    if (overview) {
      final bounds = article.paperBounds;
      final paddingX = defaultClamp(viewport.width * .2, 120, 280);
      final paddingY = defaultClamp(viewport.height * .2, 96, 220);
      targetX = bounds.center.dx;
      targetY = bounds.center.dy;
      targetScale = defaultClamp(
        math.min(
          viewport.width / math.max(bounds.width + paddingX * 2, 1),
          viewport.height / math.max(bounds.height + paddingY * 2, 1),
        ),
        defaultCameraScaleMin,
        .72,
      );
    } else if (focusBlock != null) {
      final progress = resolveDefaultPrintedProgress(focusBlock, time);
      final base = progress.floor().clamp(0, focusBlock.graphemes.length);
      final fraction = progress - base;
      final baseWidth = focusBlock.glyphOffsets[base];
      final advance = base < focusBlock.graphemes.length
          ? focusBlock.glyphOffsets[base + 1] - focusBlock.glyphOffsets[base]
          : 0;
      targetX = focusBlock.rect.left + baseWidth + advance * fraction;
      targetY = focusBlock.rect.top + focusBlock.lineHeight * .5;
      final minSide = math.max(math.min(viewport.width, viewport.height), 1);
      final targetLineHeight = defaultClamp(minSide * .115, 64, 124);
      targetScale = defaultClamp(
        targetLineHeight / math.max(focusBlock.lineHeight, 1),
        .88,
        2.2,
      );
    }

    final nextSource = overview ? -2 : (focusBlock?.sourceLineIndex ?? -1);
    if (_cameraSourceLine != nextSource) {
      _cameraSourceLine = nextSource;
      _retargetStartedAt = time;
      final rawDuration = focusBlock == null
          ? .18
          : math.max(focusBlock.line.endTime - focusBlock.line.startTime, .08);
      _retargetDuration = overview
          ? defaultClamp(
              math.min(viewport.width, viewport.height) / 1500,
              .38,
              .58,
            )
          : defaultClamp(rawDuration * .075, .075, .13);
    }
    final phase = defaultClamp(
      (time - _retargetStartedAt) / math.max(_retargetDuration, .001),
      0,
      1,
    );
    final boost = 1 - defaultEaseOutCubic(phase);
    final floatPhase = (elapsed.inMicroseconds / 1000000 / 7) * math.pi * 2;
    final attenuation = overview ? .36 : 1.0;
    final screenFloatX = math.sin(floatPhase * .74 + .8) * 18 * .34;
    final screenFloatY =
        (math.sin(floatPhase) * 18 +
            math.sin(floatPhase * .5 + 1.1) * 18 * .22) *
        attenuation;
    targetX -= screenFloatX / math.max(targetScale, .001);
    targetY -= screenFloatY / math.max(targetScale, .001);
    targetScale = defaultClamp(
      targetScale * (1 + math.sin(floatPhase + .9) * .011 * attenuation),
      defaultCameraScaleMin,
      defaultCameraScaleMax,
    );

    final boostedCatchUp = defaultClamp(
      4.8 / math.max(_retargetDuration, .05),
      20,
      54,
    );
    final targetCatchUp =
        1 - math.exp(-dt * defaultMix(11.2, boostedCatchUp, boost));
    camera.focusX += (targetX - camera.focusX) * targetCatchUp;
    camera.focusY += (targetY - camera.focusY) * targetCatchUp;
    camera.focusScale +=
        (targetScale - camera.focusScale) *
        (1 - math.exp(-dt * defaultMix(5.4, 12.8, boost)));
    final spring = defaultMix(
      208,
      defaultClamp(
        15.8 / math.max(_retargetDuration * _retargetDuration, .0064),
        260,
        780,
      ),
      boost,
    );
    final damping = defaultMix(
      24,
      defaultClamp(math.sqrt(spring) * 1.36, 24, 40),
      boost,
    );
    camera.velocityX +=
        ((camera.focusX - camera.x) * spring - camera.velocityX * damping) * dt;
    camera.velocityY +=
        ((camera.focusY - camera.y) * spring - camera.velocityY * damping) * dt;
    camera.x += camera.velocityX * dt;
    camera.y += camera.velocityY * dt;
    final scaleSpring = defaultMix(54, 108, boost);
    final scaleDamping = defaultMix(13.5, 21, boost);
    camera.velocityScale +=
        ((camera.focusScale - camera.scale) * scaleSpring -
            camera.velocityScale * scaleDamping) *
        dt;
    camera.velocityScale = defaultClamp(camera.velocityScale, -1.6, 1.6);
    camera.scale = defaultClamp(
      camera.scale + camera.velocityScale * dt,
      defaultCameraScaleMin,
      defaultCameraScaleMax,
    );
  }
}

/// Static article content separated from the camera's frame-rate rebuild.
///
/// The article may contain hundreds of lyric blocks. It only needs rebuilding
/// when the active line changes, while the outer camera transform moves every
/// frame. Keeping those lifecycles separate removes the largest source of
/// build/layout work during word animation.
class _SuperCyreneArticle extends StatefulWidget {
  const _SuperCyreneArticle({
    required this.article,
    required this.lines,
    required this.position,
  });

  final DefaultArticleLayout article;
  final List<DefaultLine> lines;
  final ValueListenable<Duration> position;

  @override
  State<_SuperCyreneArticle> createState() => _SuperCyreneArticleState();
}

class _SuperCyreneArticleState extends State<_SuperCyreneArticle> {
  late int _activeIndex;

  double get _time =>
      widget.position.value.inMicroseconds / Duration.microsecondsPerSecond +
      .3;

  @override
  void initState() {
    super.initState();
    _activeIndex = findDefaultTimelineLine(widget.lines, _time);
    widget.position.addListener(_handlePosition);
  }

  @override
  void didUpdateWidget(covariant _SuperCyreneArticle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      oldWidget.position.removeListener(_handlePosition);
      widget.position.addListener(_handlePosition);
    }
    if (!identical(oldWidget.lines, widget.lines) ||
        !identical(oldWidget.article, widget.article)) {
      _activeIndex = findDefaultTimelineLine(widget.lines, _time);
    }
  }

  @override
  void dispose() {
    widget.position.removeListener(_handlePosition);
    super.dispose();
  }

  void _handlePosition() {
    final next = findDefaultTimelineLine(widget.lines, _time);
    if (next != _activeIndex && mounted) {
      setState(() => _activeIndex = next);
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [for (final block in widget.article.blocks) _buildBlock(block)],
  );

  Widget _buildBlock(DefaultBlock block) {
    final isActive = block.sourceLineIndex == _activeIndex;
    final distance = _activeIndex >= 0
        ? (block.sourceLineIndex - _activeIndex).abs()
        : 999;
    final waitingBase = block.variant == DefaultBlockVariant.hero ? .06 : .035;
    final inactiveAlpha = _time >= block.line.endTime
        ? (block.variant == DefaultBlockVariant.hero ? .74 : .58) *
              (distance <= 1
                  ? 1
                  : distance <= 2
                  ? .88
                  : distance <= 4
                  ? .65
                  : distance <= 6
                  ? .42
                  : .28)
        : distance <= 0
        ? waitingBase * 3.2
        : distance <= 1
        ? waitingBase * 2.4
        : distance <= 2
        ? waitingBase * 1.6
        : distance <= 4
        ? waitingBase * 1.1
        : waitingBase;
    final lyric = _toFluidCloudLine(block.line);
    return Positioned(
      left: block.rect.left,
      top: block.rect.top,
      width: block.rect.width,
      child: RepaintBoundary(
        child: FluidCloudWordLine(
          key: ValueKey('default-fluid-${block.id}-$isActive'),
          lyric: lyric,
          active: isActive && lyric.hasWordByWord,
          centered: false,
          enableGlow: true,
          wordFadeWidth: .5,
          inactiveAlpha: inactiveAlpha,
          fallbackMaxWidth: block.rect.width,
          positionListenable: widget.position,
          textStyle: TextStyle(
            color: Colors.white,
            fontSize: block.fontPx,
            fontWeight: block.variant == DefaultBlockVariant.hero
                ? FontWeight.w800
                : FontWeight.w600,
            letterSpacing: block.variant == DefaultBlockVariant.hero
                ? -.8
                : -.25,
            height: block.variant == DefaultBlockVariant.hero ? 1.02 : 1.06,
          ),
        ),
      ),
    );
  }
}

LyricLine _toFluidCloudLine(DefaultLine line) => LyricLine(
  startTime: Duration(microseconds: (line.startTime * 1000000).round()),
  text: line.fullText,
  translation: line.translation,
  lineDuration: Duration(
    microseconds: ((line.endTime - line.startTime) * 1000000).round(),
  ),
  words: line.words
      .map(
        (word) => LyricWord(
          startTime: Duration(microseconds: (word.startTime * 1000000).round()),
          duration: Duration(
            microseconds: ((word.endTime - word.startTime) * 1000000).round(),
          ),
          text: word.text,
        ),
      )
      .toList(growable: false),
);
