import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../compat/player_service.dart';
import '../compat/lyric_font_service.dart';
import '../compat/lyric_style_service.dart';
import '../compat/lyric_line.dart';
import '../../amll/core/lyric_types.dart';
import '../../amll/render/lyric_line_painter.dart';
import 'fluid_cloud_word_line.dart';

/// 本组件的主歌词字号（移动端固定）
const double _kMobileLyricFontSize = 18.0;

/// 主歌词文字样式。
///
/// 高度测量与实际绘制必须共用本函数，否则折行结果会分叉，
/// 表现为「点亮后行距/换行位置变了」。
TextStyle mobileFluidCloudTextStyle(String fontFamily) {
  return TextStyle(
    fontFamily: fontFamily,
    fontSize: _kMobileLyricFontSize,
    fontWeight: FontWeight.w800,
    color: const Color(0xFFFFFFFF),
    height: 1.25, // 增加行高防止裁断
  );
}

/// 移动端流体云样式歌词组件 (v2 - 移植桌面端新版动画)
/// 核心改进：Stack 布局 + 弹性间距动画 + 波浪式延迟
///
/// [positionListenable] / [onSeek] 可选注入：桌面歌词覆盖层等「无 PlayerService
/// 的隔离场景」可显式传入播放时钟与 seek 回调；移动端调用方不传，继续走
/// PlayerService 单例（保持原行为）。
class MobilePlayerFluidCloudLyric extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int currentLyricIndex;
  final bool showTranslation;
  final VoidCallback? onTap;

  /// 播放进度时钟。非空时，行内渐变进度的位置读取改用它而非 PlayerService。
  /// 传入后仍保留 PlayerService().isPlaying 做帧间外推（隔离场景下该值为
  /// false，外推停用，仅按 listenable 的离散更新推进，轻微顿挫可接受）。
  final ValueListenable<Duration>? positionListenable;

  /// 拖拽定位回调。非空时替代 PlayerService().seek；隔离场景可传 null 走 no-op
  /// （桌面覆盖层不开放拖拽 seek）。
  final ValueChanged<Duration>? onSeek;

  const MobilePlayerFluidCloudLyric({
    super.key,
    required this.lyrics,
    required this.currentLyricIndex,
    this.showTranslation = true,
    this.onTap,
    this.positionListenable,
    this.onSeek,
  });

  @override
  State<MobilePlayerFluidCloudLyric> createState() => _MobilePlayerFluidCloudLyricState();
}

class _MobilePlayerFluidCloudLyricState extends State<MobilePlayerFluidCloudLyric>
    with TickerProviderStateMixin {
  // 核心变量 - 移动端行高适配
  final double _lineHeight = 48.0;

  // 滚动/拖拽相关
  double _dragOffset = 0.0;
  bool _isDragging = false;
  Timer? _dragResetTimer;
  int? _selectedLyricIndex;
  
  // 时间胶囊动画
  AnimationController? _timeCapsuleAnimationController;
  Animation<double>? _timeCapsuleFadeAnimation;

  // 布局缓存
  final Map<String, double> _heightCache = {};
  double? _lastViewportWidth;
  String? _lastFontFamily;
  bool? _lastShowTranslation;

  @override
  void initState() {
    super.initState();
    _timeCapsuleAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _timeCapsuleFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _timeCapsuleAnimationController!,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _dragResetTimer?.cancel();
    _timeCapsuleAnimationController?.dispose();
    super.dispose();
  }

  // 拖拽手势处理
  void _onDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _dragResetTimer?.cancel();
    });
    _timeCapsuleAnimationController?.forward();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
      // 计算当前选中的歌词索引
      if (widget.lyrics.isNotEmpty) {
        final estimatedIndex = widget.currentLyricIndex - (_dragOffset / _lineHeight).round();
        _selectedLyricIndex = estimatedIndex.clamp(0, widget.lyrics.length - 1);
      }
    });
  }

  void _onDragEnd(DragEndDetails details) {
    _dragResetTimer = Timer(const Duration(milliseconds: 2000), () {
      if (mounted) {
        setState(() {
          _isDragging = false;
          _dragOffset = 0.0;
          _selectedLyricIndex = null;
        });
        _timeCapsuleAnimationController?.reverse();
      }
    });
  }

  void _seekToSelectedLyric() {
    if (_selectedLyricIndex != null &&
        _selectedLyricIndex! >= 0 &&
        _selectedLyricIndex! < widget.lyrics.length) {
      final selectedLyric = widget.lyrics[_selectedLyricIndex!];
      // 隔离场景注入 onSeek；移动端不传则走 PlayerService 单例。
      final onSeek = widget.onSeek;
      if (onSeek != null) {
        onSeek(selectedLyric.startTime);
      } else {
        PlayerService().seek(selectedLyric.startTime);
      }
    }
    // 立即退出拖拽模式
    _dragResetTimer?.cancel();
    setState(() {
      _isDragging = false;
      _dragOffset = 0.0;
      _selectedLyricIndex = null;
    });
    _timeCapsuleAnimationController?.reverse();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lyrics.isEmpty) {
      return _buildNoLyric();
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        children: [
          // 主歌词面板
          AnimatedBuilder(
            animation: LyricStyleService(),
            builder: (context, _) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final viewportHeight = constraints.maxHeight;
                  final viewportWidth = constraints.maxWidth;

                  // 根据对齐设置动态计算中心点偏移
                  final lyricStyle = LyricStyleService();
                  final centerY = lyricStyle.currentAlignment == LyricAlignment.center
                      ? viewportHeight * 0.5
                      : viewportHeight * 0.30;

                  // 可视区域计算
                  const visibleBuffer = 5;
                  final visibleLines = (viewportHeight / _lineHeight).ceil();
                  final minIndex = math.max(0, widget.currentLyricIndex - visibleBuffer - (visibleLines ~/ 2));
                  final maxIndex = math.min(widget.lyrics.length - 1, widget.currentLyricIndex + visibleBuffer + (visibleLines ~/ 2));

                  // 动态高度计算
                  final Map<int, double> heights = {};
                  final textMaxWidth = viewportWidth - 32; // horizontal padding 16 * 2

                  for (int i = minIndex; i <= maxIndex; i++) {
                    heights[i] = _measureLyricItemHeight(i, textMaxWidth);
                  }

                  // 计算偏移量（相对于 activeIndex 中心）
                  final Map<int, double> offsets = {};
                  offsets[widget.currentLyricIndex] = 0;

                  // 向下累加
                  double currentOffset = 0;
                  double prevHalfHeight = (heights[widget.currentLyricIndex] ?? _lineHeight) / 2;

                  for (int i = widget.currentLyricIndex + 1; i <= maxIndex; i++) {
                    final h = heights[i] ?? _lineHeight;
                    currentOffset += prevHalfHeight + (h / 2);
                    offsets[i] = currentOffset;
                    prevHalfHeight = h / 2;
                  }

                  // 向上累加
                  currentOffset = 0;
                  double nextHalfHeight = (heights[widget.currentLyricIndex] ?? _lineHeight) / 2;

                  for (int i = widget.currentLyricIndex - 1; i >= minIndex; i--) {
                    final h = heights[i] ?? _lineHeight;
                    currentOffset -= (nextHalfHeight + h / 2);
                    offsets[i] = currentOffset;
                    nextHalfHeight = h / 2;
                  }

                  List<Widget> children = [];
                  for (int i = minIndex; i <= maxIndex; i++) {
                    children.add(_buildLyricItem(i, centerY, offsets[i] ?? 0.0, heights[i] ?? _lineHeight));
                  }

                  return GestureDetector(
                    onVerticalDragStart: _onDragStart,
                    onVerticalDragUpdate: _onDragUpdate,
                    onVerticalDragEnd: _onDragEnd,
                    behavior: HitTestBehavior.translucent,
                    child: Stack(
                      fit: StackFit.expand,
                      children: children,
                    ),
                  );
                },
              );
            },
          ),
          // 时间胶囊组件
          if (_isDragging && _selectedLyricIndex != null)
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(child: _buildTimeCapsule()),
            ),
        ],
      ),
    );
  }

  /// 估算歌词项高度
  double _measureLyricItemHeight(int index, double maxWidth) {
    if (index < 0 || index >= widget.lyrics.length) return _lineHeight;
    final lyric = widget.lyrics[index];
    final fontFamily = LyricFontService().currentFontFamily ?? 'Microsoft YaHei';

    // 检查缓存
    final cacheKey = '${lyric.startTime.inMilliseconds}_${lyric.text.hashCode}_$maxWidth';
    if (_lastViewportWidth == maxWidth &&
        _lastFontFamily == fontFamily &&
        _lastShowTranslation == widget.showTranslation &&
        _heightCache.containsKey(cacheKey)) {
      return _heightCache[cacheKey]!;
    }

    // 主歌词高度用渲染时那套排版来量：所有行（点亮与未点亮）都由
    // FluidCloudWordLine 绘制，这里另用 TextPainter 估高会导致折行数不一致。
    double h = fluidCloudLineLayout(
      lyric: lyric,
      textStyle: mobileFluidCloudTextStyle(fontFamily),
      maxWidth: maxWidth,
      centered: true,
    ).height;

    // 测量翻译高度
    if (widget.showTranslation && lyric.translation != null && lyric.translation!.isNotEmpty) {
      final transPainter = TextPainter(
        text: TextSpan(
          text: lyric.translation,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      transPainter.layout(maxWidth: maxWidth);
      h += 4.0;
      h += transPainter.height * 1.1;
    }

    h += 8.0; // 基础 Padding

    final result = math.max(h, _lineHeight);

    // 更新缓存
    _lastViewportWidth = maxWidth;
    _lastFontFamily = fontFamily;
    _lastShowTranslation = widget.showTranslation;
    _heightCache[cacheKey] = result;

    return result;
  }

  Widget _buildLyricItem(int index, double centerYOffset, double relativeOffset, double itemHeight) {
    final activeIndex = widget.currentLyricIndex;
    final diff = index - activeIndex;

    // 1. 基础位移
    final double baseTranslation = relativeOffset;

    // 2. 正弦偏移（果冻弹性效果）- 移动端略微减弱
    final double sineOffset = math.sin(diff * 0.8) * 12.0;

    // 3. 最终Y坐标
    double targetY = centerYOffset + baseTranslation + sineOffset - (itemHeight / 2);

    // 叠加拖拽偏移
    if (_isDragging) {
      targetY += _dragOffset;
    }

    // 4. 缩放逻辑 - 移动端略微调整
    double targetScale;
    if (diff == 0) {
      targetScale = 1.10; // 移动端缩放略小
    } else if (diff.abs() < 3) {
      targetScale = 1.0 - diff.abs() * 0.08;
    } else {
      targetScale = 0.76;
    }

    // 5. 透明度逻辑
    double targetOpacity;
    if (diff.abs() > 4) {
      targetOpacity = 0.0;
    } else {
      targetOpacity = 1.0 - diff.abs() * 0.20;
    }
    targetOpacity = targetOpacity.clamp(0.0, 1.0);

    // 6. 延迟逻辑
    final int delayMs = (diff.abs() * 40).toInt();

    // 7. 模糊逻辑
    double targetBlur = 3.0;
    if (diff == 0) {
      targetBlur = 0.0;
    } else if (diff.abs() == 1) targetBlur = 0.8;

    final bool isActive = (diff == 0);

    return _MobileElasticLyricLine(
      key: ValueKey(index),
      text: widget.lyrics[index].text,
      translation: widget.lyrics[index].translation,
      lyric: widget.lyrics[index],
      lyrics: widget.lyrics,
      index: index,
      lineHeight: _lineHeight,
      targetY: targetY,
      targetScale: targetScale,
      targetOpacity: targetOpacity,
      targetBlur: targetBlur,
      isActive: isActive,
      delay: Duration(milliseconds: delayMs),
      isDragging: _isDragging,
      showTranslation: widget.showTranslation,
      positionListenable: widget.positionListenable,
    );
  }

  Widget _buildNoLyric() {
    final fontFamily = LyricFontService().currentFontFamily ?? 'Microsoft YaHei';
    return Center(
      child: Text(
        '暂无歌词',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 16,
          fontFamily: fontFamily,
        ),
      ),
    );
  }

  Widget _buildTimeCapsule() {
    if (_selectedLyricIndex == null ||
        _selectedLyricIndex! < 0 ||
        _selectedLyricIndex! >= widget.lyrics.length) {
      return const SizedBox.shrink();
    }

    final selectedLyric = widget.lyrics[_selectedLyricIndex!];
    final timeText = _formatDuration(selectedLyric.startTime);

    return FadeTransition(
      opacity: _timeCapsuleFadeAnimation!,
      child: GestureDetector(
        onTap: _seekToSelectedLyric,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 4),
              Text(
                timeText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 移动端弹性歌词行组件 - 移植桌面端动画系统
class _MobileElasticLyricLine extends StatefulWidget {
  final String text;
  final String? translation;
  final LyricLine lyric;
  final List<LyricLine> lyrics;
  final int index;
  final double lineHeight;

  final double targetY;
  final double targetScale;
  final double targetOpacity;
  final double targetBlur;
  final bool isActive;
  final Duration delay;
  final bool isDragging;
  final bool showTranslation;
  final ValueListenable<Duration>? positionListenable;

  const _MobileElasticLyricLine({
    super.key,
    required this.text,
    this.translation,
    required this.lyric,
    required this.lyrics,
    required this.index,
    required this.lineHeight,
    required this.targetY,
    required this.targetScale,
    required this.targetOpacity,
    required this.targetBlur,
    required this.isActive,
    required this.delay,
    required this.isDragging,
    required this.showTranslation,
    this.positionListenable,
  });

  @override
  State<_MobileElasticLyricLine> createState() => _MobileElasticLyricLineState();
}

class _MobileElasticLyricLineState extends State<_MobileElasticLyricLine> with TickerProviderStateMixin {
  late double _y;
  late double _scale;
  late double _opacity;
  late double _blur;

  AnimationController? _controller;
  Animation<double>? _yAnim;
  Animation<double>? _scaleAnim;
  Animation<double>? _opacityAnim;
  Animation<double>? _blurAnim;

  Timer? _delayTimer;

  // 弹性曲线 - 来自桌面端
  static const Curve elasticCurve = Cubic(0.34, 1.56, 0.64, 1.0);
  static const Duration animDuration = Duration(milliseconds: 700); // 移动端略快

  @override
  void initState() {
    super.initState();
    _y = widget.targetY;
    _scale = widget.targetScale;
    _opacity = widget.targetOpacity;
    _blur = widget.targetBlur;
  }

  @override
  void didUpdateWidget(_MobileElasticLyricLine oldWidget) {
    super.didUpdateWidget(oldWidget);

    const double epsilon = 0.05;

    bool positionChanged = (oldWidget.targetY - widget.targetY).abs() > epsilon;
    bool scaleChanged = (oldWidget.targetScale - widget.targetScale).abs() > 0.001;
    bool opacityChanged = (oldWidget.targetOpacity - widget.targetOpacity).abs() > 0.01;
    bool blurChanged = (oldWidget.targetBlur - widget.targetBlur).abs() > 0.1;

    if (positionChanged || scaleChanged || opacityChanged || blurChanged) {
      _startAnimation();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _delayTimer?.cancel();
    super.dispose();
  }

  void _startAnimation() {
    _delayTimer?.cancel();

    if (widget.isDragging) {
      _controller?.stop();
      setState(() {
        _y = widget.targetY;
        _scale = widget.targetScale;
        _opacity = widget.targetOpacity;
        _blur = widget.targetBlur;
      });
      return;
    }

    void play() {
      _controller?.dispose();
      _controller = AnimationController(
        vsync: this,
        duration: animDuration,
      );

      _yAnim = Tween<double>(begin: _y, end: widget.targetY).animate(
        CurvedAnimation(parent: _controller!, curve: elasticCurve),
      );
      _scaleAnim = Tween<double>(begin: _scale, end: widget.targetScale).animate(
        CurvedAnimation(parent: _controller!, curve: elasticCurve),
      );
      _opacityAnim = Tween<double>(begin: _opacity, end: widget.targetOpacity).animate(
        CurvedAnimation(parent: _controller!, curve: Curves.ease),
      );
      _blurAnim = Tween<double>(begin: _blur, end: widget.targetBlur).animate(
        CurvedAnimation(parent: _controller!, curve: Curves.ease),
      );

      _controller!.addListener(() {
        if (!mounted) return;
        setState(() {
          _y = _yAnim!.value;
          _scale = _scaleAnim!.value;
          _opacity = _opacityAnim!.value;
          _blur = _blurAnim!.value;
        });
      });

      _controller!.forward();
    }

    if (widget.delay == Duration.zero) {
      play();
    } else {
      _delayTimer = Timer(widget.delay, play);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_opacity < 0.01) return const SizedBox();

    return Positioned(
      top: _y,
      left: 0,
      right: 0,
      child: Transform.scale(
        scale: _scale,
        alignment: Alignment.center, // 移动端居中对齐
        child: Opacity(
          opacity: _opacity,
          child: _MobileOptionalBlur(
            blur: _blur,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              child: _buildInnerContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInnerContent() {
    final fontFamily = LyricFontService().currentFontFamily ?? 'Microsoft YaHei';
    final textStyle = mobileFluidCloudTextStyle(fontFamily);

    // 点亮与未点亮都走同一套排版：逐字动画有上浮，若未点亮态改用 Text
    // 自己断行，两者折行位置会不同，滚到该行时整句突然重排。
    // 无逐字数据的活跃行仍走整行渐变，但排版同样来自 fluidCloudLineLayout。
    final Widget textWidget;
    if (widget.isActive && !widget.lyric.hasWordByWord) {
      textWidget = _MobileLineGradientText(
        text: widget.text,
        lyric: widget.lyric,
        lyrics: widget.lyrics,
        index: widget.index,
        textStyle: textStyle,
        positionListenable: widget.positionListenable,
      );
    } else {
      textWidget = FluidCloudWordLine(
        lyric: widget.lyric,
        active: widget.isActive,
        centered: true,
        textStyle: textStyle,
        inactiveAlpha: 0.35,
        positionListenable: widget.positionListenable,
      );
    }

    // 翻译
    if (widget.showTranslation && widget.translation != null && widget.translation!.isNotEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          textWidget,
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: Text(
              widget.translation!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.35),
                height: 1.2,
              ),
            ),
          )
        ],
      );
    }

    return textWidget;
  }
}

/// 模糊优化组件
class _MobileOptionalBlur extends StatelessWidget {
  final double blur;
  final Widget child;

  const _MobileOptionalBlur({required this.blur, required this.child});

  @override
  Widget build(BuildContext context) {
    if (blur < 0.5) return child;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: child,
    );
  }
}

/// 整行渐变文本组件 - 无逐字数据时使用。
///
/// 排版同样来自 [fluidCloudLineLayout]，只是把逐词遮罩换成整行的
/// 左→右渐变，这样它与未点亮态（[FluidCloudWordLine] active=false）
/// 的折行完全一致。
class _MobileLineGradientText extends StatefulWidget {
  final String text;
  final LyricLine lyric;
  final List<LyricLine> lyrics;
  final int index;
  final TextStyle textStyle;
  final ValueListenable<Duration>? positionListenable;

  const _MobileLineGradientText({
    required this.text,
    required this.lyric,
    required this.lyrics,
    required this.index,
    required this.textStyle,
    this.positionListenable,
  });

  @override
  State<_MobileLineGradientText> createState() => _MobileLineGradientTextState();
}

class _MobileLineGradientTextState extends State<_MobileLineGradientText> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  double _lineProgress = 0.0;
  late Duration _duration;

  @override
  void initState() {
    super.initState();
    _calculateDuration();
    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _calculateDuration() {
    if (widget.index < widget.lyrics.length - 1) {
      _duration = widget.lyrics[widget.index + 1].startTime - widget.lyric.startTime;
    } else {
      _duration = const Duration(seconds: 5);
    }
    if (_duration.inMilliseconds == 0) _duration = const Duration(seconds: 3);
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    // 隔离场景注入 positionListenable；移动端不传则走 PlayerService 单例。
    final currentPos =
        widget.positionListenable?.value ?? PlayerService().position;
    final elapsedFromStart = currentPos - widget.lyric.startTime;
    final newProgress = (elapsedFromStart.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);

    if ((newProgress - _lineProgress).abs() > 0.005) {
      setState(() {
        _lineProgress = newProgress;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.hasBoundedWidth && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 320.0;
        // 与未点亮态共用排版，保证折行一致
        final layout = fluidCloudLineLayout(
          lyric: widget.lyric,
          textStyle: widget.textStyle,
          maxWidth: maxWidth,
          centered: true,
        ).layout;

        // 绘制盒占满可用宽度（视觉行各自居中），但填充进度必须按**文字实际
        // 横向范围**推进，否则居中的短句会在文字还没开始处就先亮一截。
        var contentLeft = maxWidth;
        var contentRight = 0.0;
        for (final w in layout.words) {
          if (w.left < contentLeft) contentLeft = w.left;
          if (w.right > contentRight) contentRight = w.right;
        }
        if (contentRight <= contentLeft) {
          contentLeft = 0;
          contentRight = maxWidth;
        }

        return RepaintBoundary(
          child: ShaderMask(
            shaderCallback: (bounds) {
              final width = bounds.width <= 0 ? 1.0 : bounds.width;
              final edge =
                  ((contentLeft + (contentRight - contentLeft) * _lineProgress) /
                          width)
                      .clamp(0.0, 1.0);
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: const [Colors.white, Color(0x99FFFFFF)],
                stops: [edge, edge],
                tileMode: TileMode.clamp,
              ).createShader(bounds);
            },
            blendMode: BlendMode.srcIn,
            child: CustomPaint(
              size: Size(maxWidth, layout.size.height),
              painter: LyricLinePainter(
                layout: layout,
                animations: const [],
                textStyle: widget.textStyle,
                relativeTimeMs: 0,
                fadeProgress: 0,
                // 颜色由外层 ShaderMask 的 srcIn 决定，这里画满不透明即可
                brightAlpha: 1.0,
                darkAlpha: 1.0,
                baseColor: const Color(0xFFFFFFFF),
                renderMode: LyricLineRenderMode.solid,
                enableGlow: false,
              ),
            ),
          ),
        );
      },
    );
  }
}
