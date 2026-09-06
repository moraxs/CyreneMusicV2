import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'monet_palette.dart';

/// 「莫奈」海报排版的度量。
///
/// 上游把字号写成 `clamp(min, Nvw, max)` 并统一乘上一个大屏系数，列宽与字号因此
/// 同比缩放，折行结果在任何分辨率下都一样。这里把那套换算集中在一处，歌词轨与
/// 海报共用同一份结果——两边各算一份就会在 2K/4K 上错位。
class MonetPosterMetrics {
  const MonetPosterMetrics({
    required this.layoutScale,
    required this.lyricFontPx,
    required this.inactiveFontPx,
    required this.translationFontPx,
  });

  final double layoutScale;
  final double lyricFontPx;
  final double inactiveFontPx;
  final double translationFontPx;
}

typedef MonetContentBuilder =
    Widget Function(BuildContext context, MonetPosterMetrics metrics);

// ——— 上游常量 ———
const double _kRootFontPx = 16;
const double _kRowBaseMaxWidthPx = 1520;
const double _kPortraitBaseMaxPx = 430;
const double _kPortraitInnerBaseMaxPx = 380;
const double _kLargeScreenMinPx = 1536;
const double _kLargeScreenFullPx = 2200;
const double _kLargeScreenMaxScale = 1.16;

/// 上游 `MonetTuning.fontScale` 的默认值。
const double _kFontScale = 1.2;

/// 方形封面相对其列宽的超出比例（`width: 135.135%; margin-left: -35.135%`）。
const double _kPortraitBleedRatio = 0.35135;

const Curve _kIntroCurve = Cubic(.25, 1, .5, 1);
const Duration _kIntroTimeline = Duration(milliseconds: 2400);

/// 上游 `resolveMonetLargeScreenScale`：2xl 以下恒为 1，再宽才整体放大。
double monetLargeScreenScale(double referenceWidth) {
  if (referenceWidth <= _kLargeScreenMinPx) return 1;
  final progress = math.min(
    1.0,
    (referenceWidth - _kLargeScreenMinPx) /
        (_kLargeScreenFullPx - _kLargeScreenMinPx),
  );
  return 1 + (_kLargeScreenMaxScale - 1) * progress;
}

/// 上游 `resolveClampFontPx`：CSS `clamp(minRem, preferredVw, maxRem)`。
double monetClampFontPx(
  double minRem,
  double preferredVw,
  double maxRem,
  double viewportWidth,
) => math.min(
  maxRem * _kRootFontPx,
  math.max(minRem * _kRootFontPx, viewportWidth * (preferredVw / 100)),
);

/// folia「莫奈」的海报式主区域。
///
/// 左栏自上而下是：斜体艺术家名 → 一条竖发丝线 → 歌名 → 大写专辑名 → 内容区
/// （歌词轨 / 歌曲信息）；右栏是一张向左溢出的方形封面。所有位置、
/// 字号、alpha、入场动画的延迟与时长都照搬 `VisualizerMonet.tsx`。
///
/// 本组件不读任何全局单例——封面、调色板、歌词内容全部由外部传入，所以设置页的
/// 缩略预览可以直接复用它（与 `ClassicRecordStage` 同一约定）。
class MonetPoster extends StatefulWidget {
  const MonetPoster({
    super.key,
    required this.title,
    required this.artist,
    required this.album,
    required this.palette,
    required this.cover,
    required this.contentBuilder,
    this.coverFallback,
    this.introKey,
    this.showContent = true,
    this.animate = true,
  });

  final String title;
  final String artist;
  final String album;

  final MonetPalette palette;

  /// 右栏方形封面里的图。为 null 时退到 [coverFallback]，再没有就留一块
  /// primary@0.08 的底。
  final ImageProvider? cover;

  /// 没有 [cover] 时画的替身。设置页预览用它避免发真实网络请求。
  final Widget? coverFallback;

  /// 左栏内容区（歌词轨或歌曲信息面板）。
  final MonetContentBuilder contentBuilder;

  /// 变化时重放入场动画。传当前曲目的 key 即可。
  final Object? introKey;

  final bool showContent;

  /// 关掉后所有入场动画直接停在终态（测试 / 静态预览）。
  final bool animate;

  @override
  State<MonetPoster> createState() => _MonetPosterState();
}

class _MonetPosterState extends State<MonetPoster>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(vsync: this, duration: _kIntroTimeline);
    if (widget.animate) {
      _intro.forward();
    } else {
      _intro.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant MonetPoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.animate) {
      _intro.stop();
      _intro.value = 1;
      return;
    }
    if (widget.introKey != oldWidget.introKey || !oldWidget.animate) {
      _intro.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // 上游所有 `vw` 都读窗口宽度，这里一律换成本组件自己的宽度：真实播放器里
      // 海报本就铺满窗口，两者等价；而设置页那张 640px 的缩略画布只有这样才会
      // 按自己的盒子排版，不会套用显示器的字号再被整体缩小成一团灰。
      final availableWidth = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      final scale = monetLargeScreenScale(availableWidth);
      final metrics = MonetPosterMetrics(
        layoutScale: scale,
        lyricFontPx:
            monetClampFontPx(1.34, 2.75, 2.28, availableWidth) *
            _kFontScale *
            scale,
        inactiveFontPx:
            monetClampFontPx(1.08, 2, 1.48, availableWidth) *
            _kFontScale *
            scale,
        translationFontPx:
            monetClampFontPx(0.94, 1.28, 1.14, availableWidth) *
            _kFontScale *
            scale,
      );

      final rowMaxWidth = _kRowBaseMaxWidthPx * scale;
      final rowWidth = math.min(availableWidth, rowMaxWidth);
      final portraitColumnWidth = _clamp(
        availableWidth * .28,
        220,
        _kPortraitBaseMaxPx * scale,
      );
      final portraitInnerWidth = math.min(
        _clamp(availableWidth * .26, 210, _kPortraitInnerBaseMaxPx * scale),
        math.max(portraitColumnWidth - _portraitSidePadding(rowWidth) - 12, 1.0),
      );
      // 窄窗口下右栏会挤没左栏，上游用 `hidden md:flex` 直接不画它。
      final showPortrait = rowWidth >= 768;

      final horizontalPadding = _columnPaddingX(rowWidth);
      final leftContentWidth = math.max(
        rowWidth -
            (showPortrait ? portraitColumnWidth : 0) -
            horizontalPadding * 2,
        1.0,
      );
      // 封面向左溢出会压到标题上；上游按溢出量反向收窄表头，这里照抄。
      final headerMaxWidth = showPortrait
          ? math.max(
              192.0,
              leftContentWidth -
                  math.max(0.0, _kPortraitBleedRatio * portraitInnerWidth - 48),
            )
          : leftContentWidth;

      return Center(
        child: SizedBox(
          width: rowWidth,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: _columnPaddingY(rowWidth),
                  ),
                  child: _leftColumn(metrics, availableWidth, headerMaxWidth),
                ),
              ),
              if (showPortrait)
                _portraitColumn(
                  columnWidth: portraitColumnWidth,
                  innerWidth: portraitInnerWidth,
                  rightPadding: _portraitSidePadding(rowWidth),
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _leftColumn(
    MonetPosterMetrics metrics,
    double availableWidth,
    double headerMaxWidth,
  ) {
    final palette = widget.palette;
    final artistFontPx = _clamp(
      availableWidth * .018,
      _kRootFontPx,
      1.8 * _kRootFontPx * metrics.layoutScale,
    );
    final titleFontPx = _clamp(
      availableWidth * .033,
      1.45 * _kRootFontPx,
      2.8 * _kRootFontPx * metrics.layoutScale,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _introMotion(
          delay: .15,
          duration: 1.2,
          offset: const Offset(-30, -10),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: headerMaxWidth),
            child: Text(
              widget.artist.trim().isEmpty ? 'Monet' : widget.artist.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: monetAlpha(palette.primary, .96),
                fontSize: artistFontPx,
                fontStyle: FontStyle.italic,
                height: 1.35,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _introScaleY(
          delay: .5,
          duration: 1.5,
          child: Container(
            width: 1,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(.5),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  monetAlpha(palette.primary, .72),
                  monetAlpha(palette.primary, 0),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _introMotion(
          delay: .3,
          duration: 1.3,
          offset: const Offset(-40, 0),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: headerMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title.trim().isEmpty ? 'Monet' : widget.title.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.primary,
                    fontSize: titleFontPx,
                    fontWeight: FontWeight.w600,
                    height: 1.06,
                    shadows: [
                      Shadow(
                        color: monetAlpha(palette.background, .28),
                        blurRadius: 36,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  (widget.album.trim().isEmpty ? 'Monet' : widget.album.trim())
                      .toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: monetAlpha(palette.secondary, .84),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (widget.showContent)
          Flexible(
            child: _introMotion(
              delay: .65,
              duration: 1.2,
              offset: const Offset(0, 20),
              child: widget.contentBuilder(context, metrics),
            ),
          ),
      ],
    );
  }

  Widget _portraitColumn({
    required double columnWidth,
    required double innerWidth,
    required double rightPadding,
  }) {
    final palette = widget.palette;
    final coverSide = innerWidth * (1 + _kPortraitBleedRatio);

    return SizedBox(
      width: columnWidth,
      child: Center(
        // 方形封面比它那一栏宽 35.135%，多出来的部分压在左栏上——上游的构图，
        // 不是溢出 bug。OverflowBox 是这里唯一能把「右缘对齐、向左越界」表达
        // 出来的容器。
        child: OverflowBox(
          alignment: Alignment.centerRight,
          minWidth: 0,
          minHeight: 0,
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: Padding(
            padding: EdgeInsets.only(right: rightPadding),
            child: _introMotion(
              delay: .25,
              duration: 1.6,
              offset: const Offset(50, 0),
              scaleFrom: .95,
              rotationTurnsFrom: 1 / 360,
              child: SizedBox(
                width: coverSide,
                height: coverSide,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          color: monetAlpha(palette.primary, .08),
                          boxShadow: [
                            BoxShadow(
                              color: monetAlpha(palette.background, .45),
                              blurRadius: 80,
                              offset: const Offset(0, 36),
                            ),
                            BoxShadow(
                              color: monetAlpha(palette.accent, .22),
                              blurRadius: 42,
                              offset: const Offset(0, 20),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: _coverImage(),
                        ),
                      ),
                    ),
                    // 上游的挂钩（拖动封面用）。这里不做拖动重定位，只保留它在
                    // 构图里的那一笔。
                    Positioned(
                      top: -12,
                      right: 32,
                      width: 12,
                      height: 56,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: monetAlpha(palette.background, .86),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0x3D000000),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _coverImage() {
    final cover = widget.cover;
    if (cover == null) {
      return widget.coverFallback ?? const SizedBox.expand();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, ?current],
      ),
      child: Image(
        key: ValueKey<Object>(cover),
        image: cover,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const SizedBox.expand(),
      ),
    );
  }

  /// 位移 + 淡入（+ 可选缩放/旋转）的入场动画，对应上游的 framer-motion 段。
  Widget _introMotion({
    required double delay,
    required double duration,
    required Offset offset,
    required Widget child,
    double scaleFrom = 1,
    double rotationTurnsFrom = 0,
  }) => AnimatedBuilder(
    animation: _intro,
    child: child,
    builder: (context, child) {
      final t = _progress(delay, duration);
      Widget result = Transform.translate(
        offset: Offset(offset.dx * (1 - t), offset.dy * (1 - t)),
        child: Opacity(opacity: t, child: child),
      );
      if (scaleFrom != 1) {
        result = Transform.scale(
          scale: scaleFrom + (1 - scaleFrom) * t,
          child: result,
        );
      }
      if (rotationTurnsFrom != 0) {
        result = Transform.rotate(
          angle: rotationTurnsFrom * 2 * math.pi * (1 - t),
          child: result,
        );
      }
      return result;
    },
  );

  /// 竖发丝线的 `scaleY: 0 → 1`，原点在顶端。
  Widget _introScaleY({
    required double delay,
    required double duration,
    required Widget child,
  }) => AnimatedBuilder(
    animation: _intro,
    child: child,
    builder: (context, child) => Transform(
      alignment: Alignment.topCenter,
      transform: Matrix4.diagonal3Values(1, _progress(delay, duration), 1),
      child: child,
    ),
  );

  double _progress(double delaySeconds, double durationSeconds) {
    final elapsed =
        _intro.value * (_kIntroTimeline.inMilliseconds / 1000) - delaySeconds;
    if (elapsed <= 0) return 0;
    return _kIntroCurve.transform(
      (elapsed / durationSeconds).clamp(0.0, 1.0),
    );
  }
}

/// `px-5 sm:px-8 lg:px-14 2xl:px-20`
double _columnPaddingX(double width) {
  if (width >= _kLargeScreenMinPx) return 80;
  if (width >= 1024) return 56;
  if (width >= 640) return 32;
  return 20;
}

/// `py-5 sm:py-6 lg:py-8`
double _columnPaddingY(double width) {
  if (width >= 1024) return 32;
  if (width >= 640) return 24;
  return 20;
}

/// `pr-5 sm:pr-8 lg:pr-10 xl:pr-12`
double _portraitSidePadding(double width) {
  if (width >= 1280) return 48;
  if (width >= 1024) return 40;
  if (width >= 640) return 32;
  return 20;
}

double _clamp(double value, double min, double max) =>
    math.min(math.max(value, min), math.max(min, max));
