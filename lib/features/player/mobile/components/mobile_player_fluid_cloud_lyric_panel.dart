import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../compat/player_service.dart';
import '../compat/lyric_font_service.dart';
import '../compat/lyric_style_service.dart';
import '../compat/lyric_line.dart';
import 'fluid_cloud_word_line.dart';

/// 虚拟项类型：歌词或占位点
enum _VirtualEntryType { lyric, dots }

/// 虚拟歌词项 - 用于统一管理歌词和占位点
class _VirtualLyricEntry {
  final _VirtualEntryType type;
  final int? lyricIndex; 
  final Duration startTime;
  final Duration? endTime; // 新增：用于 Dots 动画时长计算
  final String key;

  _VirtualLyricEntry({
    required this.type,
    this.lyricIndex,
    required this.startTime,
    this.endTime,
    required this.key,
  });
}

// --- 动画常量定义 ---
const Curve kSineElastic = Cubic(0.44, 0.05, 0.55, 0.95);
const Duration kScrollDuration = Duration(milliseconds: 800);
const Duration kShrinkDelay = Duration(milliseconds: 400); 
const Duration kShrinkDuration = Duration(milliseconds: 500);

/// 面板主歌词的文字样式。
///
/// 高度测量与实际绘制必须共用本函数：两处只要有一处字号/字重/行高不同，
/// 折行结果就会分叉，表现为「点亮后行距变了」。
TextStyle fluidCloudPanelTextStyle({
  required String fontFamily,
  required double fontSize,
}) {
  return TextStyle(
    fontFamily: fontFamily,
    fontSize: fontSize,
    fontWeight: FontWeight.w800,
    color: const Color(0xFFFFFFFF),
    height: 1.3,
  );
}

/// 移动端流体云歌词面板 - 由桌面端 PlayerFluidCloudLyricsPanel 复制而来，用于独立适配
class MobilePlayerFluidCloudLyricsPanel extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int currentLyricIndex;
  final bool showTranslation;
  final int visibleLineCount;

  const MobilePlayerFluidCloudLyricsPanel({
    super.key,
    required this.lyrics,
    required this.currentLyricIndex,
    required this.showTranslation,
    this.visibleLineCount = 7,
  });

  @override
  State<MobilePlayerFluidCloudLyricsPanel> createState() => _MobilePlayerFluidCloudLyricsPanelState();
}

class _MobilePlayerFluidCloudLyricsPanelState extends State<MobilePlayerFluidCloudLyricsPanel> {
  
  static const double _maxActiveScale = 1.0; // 1.1 -> 1.0 No magnification
  
  // 滚动/拖拽相关
  double _dragOffset = 0.0;
  bool _isDragging = false;
  Timer? _dragResetTimer;

  // 布局缓存
  final Map<String, double> _heightCache = {};
  double? _lastViewportWidth;
  String? _lastFontFamily;
  bool? _lastShowTranslation;

  // Ticker Removed

  // 🔧 修复间奏 dots 显示：监听播放进度，在进入/离开间奏时触发重建
  // 原问题：build 方法中的 dots 插入条件依赖 currentPos，但只监听了 LyricStyleService，
  // 播放进度高频更新不触发 notifyListeners，导致进入间奏时 dots 不会被插入，
  // 只有暂停（结构性变化）触发重建才会显示。
  bool _wasInInterlude = false;

  @override
  void initState() {
    super.initState();
    _wasInInterlude = _isInInterlude(PlayerService().position);
    PlayerService().positionNotifier.addListener(_onPositionChanged);
  }

  @override
  void didUpdateWidget(covariant MobilePlayerFluidCloudLyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 歌词变化时重新计算间奏状态
    if (oldWidget.lyrics != widget.lyrics) {
      _wasInInterlude = _isInInterlude(PlayerService().position);
    }
  }

  @override
  void dispose() {
    PlayerService().positionNotifier.removeListener(_onPositionChanged);
    _dragResetTimer?.cancel();
    super.dispose();
  }

  /// 检查 [pos] 是否落在任一间奏区间内（与 build 方法中 dots 插入条件保持一致）
  bool _isInInterlude(Duration pos) {
    final lyrics = widget.lyrics;
    for (int i = 0; i < lyrics.length - 1; i++) {
      final currentLine = lyrics[i];
      final nextLine = lyrics[i + 1];

      Duration lineEndTime =
          currentLine.startTime + const Duration(seconds: 3);
      if (currentLine.words != null && currentLine.words!.isNotEmpty) {
        lineEndTime =
            currentLine.words!.last.startTime + currentLine.words!.last.duration;
      } else if (currentLine.lineDuration != null) {
        lineEndTime = currentLine.startTime + currentLine.lineDuration!;
      }

      final actualGap = nextLine.startTime - lineEndTime;
      if (actualGap.inSeconds >= 2 &&
          pos >= lineEndTime &&
          pos < nextLine.startTime) {
        return true;
      }
    }
    return false;
  }

  void _onPositionChanged() {
    if (!mounted) return;
    final inInterlude =
        _isInInterlude(PlayerService().positionNotifier.value);
    if (inInterlude != _wasInInterlude) {
      _wasInInterlude = inInterlude;
      setState(() {});
    }
  }

  void _onDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _dragResetTimer?.cancel();
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
    });
  }

  void _onDragEnd(DragEndDetails details) {
     _dragResetTimer = Timer(const Duration(milliseconds: 600), () {
       if (mounted) {
         setState(() {
           _isDragging = false;
           _dragOffset = 0.0; 
         });
       }
     });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lyrics.isEmpty) {
      return _buildNoLyric();
    }

    return AnimatedBuilder(
      animation: LyricStyleService(),
      builder: (context, _) {
        final styleService = LyricStyleService();
        return LayoutBuilder(
          builder: (context, constraints) {
            final viewportHeight = constraints.maxHeight;
            final viewportWidth = constraints.maxWidth;
            final currentPos = PlayerService().position;
            
            // 🔧 关键修复：为了应对活跃行 1.15x 的放大，基础布局宽度需要收缩
            // 使得 基础宽度 * 1.15 = 视口宽度
            final horizontalPadding = 40.0; // 20 * 2
            final layoutWidth = viewportWidth / _maxActiveScale;
            final textMaxWidth = layoutWidth - horizontalPadding;

            // 🔧 关键修复：基础行高随字号倍率缩放
            final baseLineHeight = styleService.lineHeight;
            
            final centerY = styleService.currentAlignment == LyricAlignment.center 
                ? viewportHeight * 0.5 
                : viewportHeight * 0.25;

            // 1. 构建虚拟项列表 (动态触发)
            final List<_VirtualLyricEntry> virtualEntries = [];
            
              // 检查前奏 dots：无论进度如何，只要前奏 > 2s 就显示
              if (widget.lyrics.isNotEmpty) {
                final firstTime = widget.lyrics[0].startTime;
                if (firstTime > const Duration(seconds: 2)) {
                   virtualEntries.add(_VirtualLyricEntry(
                     type: _VirtualEntryType.dots,
                     startTime: Duration.zero,
                     endTime: firstTime,
                     key: 'dots-intro',
                   ));
                }
              }

            for (int i = 0; i < widget.lyrics.length; i++) {
              virtualEntries.add(_VirtualLyricEntry(
                type: _VirtualEntryType.lyric,
                lyricIndex: i,
                startTime: widget.lyrics[i].startTime,
                key: 'lyric-$i-${widget.lyrics[i].startTime.inMilliseconds}',
              ));

              // 检查间奏 dots：同样是动态触发
              if (i < widget.lyrics.length - 1) {
                final currentLine = widget.lyrics[i];
                final nextLine = widget.lyrics[i+1];
                
                // 计算当前行结束时间
                Duration lineEndTime = currentLine.startTime + const Duration(seconds: 3); // 默认兜底 3s
                if (currentLine.words != null && currentLine.words!.isNotEmpty) {
                  lineEndTime = currentLine.words!.last.startTime + currentLine.words!.last.duration;
                } else if (currentLine.lineDuration != null) {
                   lineEndTime = currentLine.startTime + currentLine.lineDuration!;
                }

                // 实际间奏时长
                final actualGap = nextLine.startTime - lineEndTime;
                final actualGapSeconds = actualGap.inSeconds;

                // 只有当播放进度已经到达或超过当前句子的"结束点"，且间奏够长(>2s)，才插入 dots 项
                if (actualGapSeconds >= 2 && currentPos >= lineEndTime) {
                  // 逻辑同步：如果间奏 > 10秒，则延迟 1s 开始渲染 (保持 Apple Music 风格)
                  final dotsStartTime = actualGapSeconds > 10 
                      ? lineEndTime + const Duration(seconds: 1)
                      : lineEndTime;

                  virtualEntries.add(_VirtualLyricEntry(
                    type: _VirtualEntryType.dots,
                    startTime: dotsStartTime,
                    endTime: nextLine.startTime,
                    key: 'dots-interlude-$i',
                  ));
                }
              }
            }

            // 2. 找到当前活跃虚拟项索引
            int activeVirtualIndex = 0;
            for (int i = virtualEntries.length - 1; i >= 0; i--) {
              if (currentPos >= virtualEntries[i].startTime) {
                activeVirtualIndex = i;
                break;
              }
            }

            // 可视区域计算
            final visibleBuffer = 8; 
            final minIdx = max(0, activeVirtualIndex - visibleBuffer);
            final maxIdx = min(virtualEntries.length - 1, activeVirtualIndex + visibleBuffer + 4);

            // 3. 计算高度和偏移
            final Map<int, double> heights = {};
            for (int i = minIdx; i <= maxIdx; i++) {
              heights[i] = _measureVirtualEntryHeight(virtualEntries[i], textMaxWidth, baseLineHeight);
            }

            final Map<int, double> offsets = {};
            offsets[activeVirtualIndex] = 0;

            double currentOffset = 0;
            double prevHalfHeight = (heights[activeVirtualIndex]! * (virtualEntries[activeVirtualIndex].type == _VirtualEntryType.dots ? 1.0 : _maxActiveScale)) / 2;
            
            for (int i = activeVirtualIndex + 1; i <= maxIdx; i++) {
              final h = heights[i]!;
              final s = _getScaleSync(i - activeVirtualIndex);
              final scaledHalfHeight = (h * s) / 2;
              currentOffset += prevHalfHeight + scaledHalfHeight; 
              offsets[i] = currentOffset;
              prevHalfHeight = scaledHalfHeight;
            }

            currentOffset = 0;
            double nextHalfHeight = (heights[activeVirtualIndex]! * (virtualEntries[activeVirtualIndex].type == _VirtualEntryType.dots ? 1.0 : _maxActiveScale)) / 2;
            
            for (int i = activeVirtualIndex - 1; i >= minIdx; i--) {
              final h = heights[i]!;
              final s = _getScaleSync(i - activeVirtualIndex);
              final scaledHalfHeight = (h * s) / 2;
              currentOffset -= (nextHalfHeight + scaledHalfHeight);
              offsets[i] = currentOffset;
              nextHalfHeight = scaledHalfHeight;
            }

            // 🔧 活跃项是否为间奏 dots：用于在间奏期间隐藏歌词项，只让 dots 高亮居中
            final bool activeIsDots = virtualEntries[activeVirtualIndex].type == _VirtualEntryType.dots;

            List<Widget> children = [];
            for (int i = minIdx; i <= maxIdx; i++) {
               children.add(_buildVirtualItem(
                 virtualEntries[i],
                 i,
                 activeVirtualIndex,
                 centerY,
                 offsets[i] ?? 0.0,
                 heights[i]!,
                 layoutWidth,
                 baseLineHeight,
                 currentPos,
                 activeIsDots,
               ));
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
    );
  }

  double _measureVirtualEntryHeight(_VirtualLyricEntry entry, double maxWidth, double baseHeight) {
    if (entry.type == _VirtualEntryType.dots) return 40.0;
    return _measureLyricItemHeight(entry.lyricIndex!, maxWidth, baseHeight);
  }

  /// 内部辅助方法：计算同步缩放值（用于偏移量预计算）
  double _getScaleSync(int diff) {
    return 1.0;
  }

  Widget _buildVirtualItem(_VirtualLyricEntry item, int index, int activeIndex, double centerYOffset, double relativeOffset, double itemHeight, double layoutWidth, double baseHeight, Duration currentPos, bool activeIsDots) {
    final diff = index - activeIndex;
    final styleService = LyricStyleService();

    // 1. 缩放逻辑
    double targetScale = _getScaleSync(diff);
    if (item.type == _VirtualEntryType.dots) targetScale = 1.0;

    // 2. 最终Y坐标
    double baseTranslation = relativeOffset;
    double sineOffset = sin(diff * 0.8) * 20.0 * (styleService.fontSize / 32.0);

    // 【核心亮点】占位点原地消失逻辑
    // 如果是占位点，并且已经过期 (diff < 0)
    if (item.type == _VirtualEntryType.dots && diff < 0) {
       // 固定在中心位置附近停留消失，不跟随向上滚动
       baseTranslation = 0;
       sineOffset = 0;
    }

    double targetY = centerYOffset + baseTranslation + sineOffset - (itemHeight * targetScale / 2);
    if (_isDragging) targetY += _dragOffset;

    // 3. 透明度逻辑
    double targetOpacity;
    if (diff.abs() > 4) {
      targetOpacity = 0.0;
    } else {
      targetOpacity = 1.0 - diff.abs() * 0.2;
    }

    // 过期占位符强制 0 透明度 (因为它们不再占用空间)
    if (item.type == _VirtualEntryType.dots && diff < 0) targetOpacity = 0.0;

    // 间奏 dots 激活时不再清零歌词项透明度：沿用上面的距离衰减
    // (1.0 - |diff|*0.2) 让刚唱完的上一行与即将唱的下一行以淡出态保留，
    // 只在中间高亮 dots，与 AMLL 样式一致；否则上下两行会整行消失。

    targetOpacity = targetOpacity.clamp(0.0, 1.0).toDouble();

    final int delayMs = (diff.abs() * 50).toInt();

    final blurSigma = styleService.blurSigma;
    double targetBlur = blurSigma;
    if (diff == 0) {
      targetBlur = 0.0;
    } else if (diff.abs() == 1) {
      targetBlur = blurSigma * 0.25;
    }
    if (item.type == _VirtualEntryType.dots && diff < 0) {
      targetBlur = blurSigma;
    }

    final bool isActive = (diff == 0);

    // 如果是占位点
    if (item.type == _VirtualEntryType.dots) {
      return _CountdownDotsWrapper(
        key: ValueKey(item.key),
        startTime: item.startTime,
        endTime: item.endTime ?? item.startTime,
        targetY: targetY,
        targetOpacity: targetOpacity,
        layoutWidth: layoutWidth,
      );
    }

    // 歌词项
    return _ElasticLyricLine(
      key: ValueKey(item.key),
      text: widget.lyrics[item.lyricIndex!].text,
      translation: widget.lyrics[item.lyricIndex!].translation,
      lyric: widget.lyrics[item.lyricIndex!],
      lyrics: widget.lyrics,     
      index: index,             
      lineHeight: baseHeight,
      targetY: targetY,
      targetScale: targetScale,
      targetOpacity: targetOpacity,
      targetBlur: targetBlur,
      isActive: isActive,
      delay: Duration(milliseconds: delayMs),
      isDragging: _isDragging,
      showTranslation: widget.showTranslation,
      layoutWidth: layoutWidth,
    );
  }

  double _measureLyricItemHeight(int index, double maxWidth, double baseHeight) {
    if (index < 0 || index >= widget.lyrics.length) return baseHeight;
    final lyric = widget.lyrics[index];
    final fontFamily = LyricFontService().currentFontFamily ?? 'Microsoft YaHei';

    final fontSize = LyricStyleService().fontSize * 0.9;
    final cacheKey = '${lyric.startTime.inMilliseconds}_${lyric.text.hashCode}_${maxWidth.round()}_$fontSize';

    if (_lastViewportWidth != null &&
        (_lastViewportWidth! - maxWidth).abs() < 0.1 &&
        _lastFontFamily == fontFamily &&
        _lastShowTranslation == widget.showTranslation &&
        _heightCache.containsKey(cacheKey)) {
      return _heightCache[cacheKey]!;
    }

    // 主歌词高度必须用渲染时那套排版来量：面板里所有行（点亮与未点亮）
    // 都由 FluidCloudWordLine 绘制，若这里另用 TextPainter 估高，
    // 折行数一旦不一致就会出现行距忽大忽小。
    double h = fluidCloudLineLayout(
      lyric: lyric,
      textStyle: fluidCloudPanelTextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
      ),
      maxWidth: maxWidth,
    ).height;

    if (widget.showTranslation && lyric.translation != null && lyric.translation!.isNotEmpty) {
      final transPainter = TextPainter(
        text: TextSpan(
          text: lyric.translation,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: fontSize * 0.56,
            fontWeight: FontWeight.w600,
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      transPainter.layout(maxWidth: maxWidth);
      h += 8.0 * (fontSize / 32.0); // 比例间距
      h += transPainter.height * 1.4;
    }
    
    h += 24.0 * (fontSize / 32.0); // 比例底部间距
    final result = max(h, baseHeight);
    
    _lastViewportWidth = maxWidth;
    _lastFontFamily = fontFamily;
    _lastShowTranslation = widget.showTranslation;
    _heightCache[cacheKey] = result;
    
    return result;
  }

  Widget _buildNoLyric() {
    return const Center(
      child: Text(
        '暂无歌词',
        style: TextStyle(color: Colors.white54, fontSize: 21.6), // 24 * 0.9
      ),
    );
  }
}

class _ElasticLyricLine extends StatefulWidget {
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
  final double layoutWidth;

  const _ElasticLyricLine({
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
    required this.layoutWidth,
  });

  @override
  State<_ElasticLyricLine> createState() => _ElasticLyricLineState();
}

class _ElasticLyricLineState extends State<_ElasticLyricLine> with TickerProviderStateMixin {
  late double _y;
  late double _scale;
  late double _opacity;
  late double _blur;
  late Color _textColor; // 新增文本颜色状态
  
  AnimationController? _controller;
  Animation<double>? _yAnim;
  Animation<double>? _scaleAnim;
  Animation<double>? _opacityAnim;
  Animation<double>? _blurAnim;
  Animation<Color?>? _colorAnim; // 新增颜色动画
  
  Timer? _delayTimer;

  static const Duration animDuration = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    _y = widget.targetY;
    _scale = widget.targetScale;
    _opacity = widget.targetOpacity;
    _blur = widget.targetBlur;
    _textColor = widget.isActive ? Colors.white : Colors.white.withValues(alpha: 0.3);
  }

  // --- 涟漪效果相关 ---
  final List<_RippleInfo> _ripples = [];
  
  void _addRipple(Offset localPosition) {
    final ripple = _RippleInfo(
      position: localPosition,
      controller: AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 800),
      ),
    );
    
    setState(() {
      _ripples.add(ripple);
    });

    ripple.controller.forward().then((_) {
      if (mounted) {
        setState(() {
          _ripples.remove(ripple);
        });
      }
      ripple.controller.dispose();
    });
  }

  @override
  void didUpdateWidget(_ElasticLyricLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    const double epsilon = 0.05;
    bool positionChanged = (oldWidget.targetY - widget.targetY).abs() > epsilon;
    bool scaleChanged = (oldWidget.targetScale - widget.targetScale).abs() > 0.001;
    bool opacityChanged = (oldWidget.targetOpacity - widget.targetOpacity).abs() > 0.01;
    bool blurChanged = (oldWidget.targetBlur - widget.targetBlur).abs() > 0.1;
    
    if (positionChanged || scaleChanged || opacityChanged || blurChanged) {
      _startAnimation(oldWidget);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _delayTimer?.cancel();
    super.dispose();
  }

  void _startAnimation(covariant _ElasticLyricLine oldWidget) {
    _delayTimer?.cancel();
    
    if (widget.isDragging) {
      _controller?.stop();
      setState(() {
        _y = widget.targetY;
        _scale = widget.targetScale;
        _opacity = widget.targetOpacity;
        _blur = widget.targetBlur;
        _textColor = widget.isActive ? Colors.white : Colors.white.withValues(alpha: 0.3);
      });
      return;
    }

    void play() {
      if (!mounted) return;
      
      // 创建或重置控制器
      _controller?.dispose();
      _controller = AnimationController(
        vsync: this,
        duration: animDuration, // 直接使用固定时长 (800ms)
      );

      _controller!.addListener(() {
        if (!mounted) return;
        setState(() {
          _y = _yAnim!.value;
          _scale = _scaleAnim!.value;
          _opacity = _opacityAnim!.value;
          _blur = _blurAnim!.value;
          if (_colorAnim != null) _textColor = _colorAnim!.value ?? _textColor;
        });
      });
      
      // 计算目标颜色
      final targetColor = widget.isActive ? Colors.white : Colors.white.withValues(alpha: 0.3);

      // 所有属性同步动画
      _yAnim = Tween<double>(begin: _y, end: widget.targetY).animate(
        CurvedAnimation(parent: _controller!, curve: kSineElastic)
      );
      
      _scaleAnim = Tween<double>(begin: _scale, end: widget.targetScale).animate(
         CurvedAnimation(parent: _controller!, curve: kSineElastic)
      );

      // Opacity/Blur/Color 使用 Linear/Ease (匹配 HTML behavior)
      _opacityAnim = Tween<double>(begin: _opacity, end: widget.targetOpacity).animate(
        CurvedAnimation(parent: _controller!, curve: Curves.linear)
      );
      
      _blurAnim = Tween<double>(begin: _blur, end: widget.targetBlur).animate(
        CurvedAnimation(parent: _controller!, curve: Curves.linear)
      );

      _colorAnim = ColorTween(begin: _textColor, end: targetColor).animate(
        CurvedAnimation(parent: _controller!, curve: Curves.linear)
      );

      _controller!.forward(from: 0.0);
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
      width: widget.layoutWidth,
      child: RepaintBoundary(
        child: GestureDetector(
          // 🔧 关键修复：使用 opaque 拦截点击事件，防止冒泡到外部 Layout 触发控制栏显隐
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            _addRipple(details.localPosition);
          },
          onTap: () {
            // 跳转到歌词开始时间
            PlayerService().seek(widget.lyric.startTime);
            debugPrint('🎯 [LyricPanel] 点击跳转到: ${widget.lyric.startTime}');
          },
          child: Transform.scale(
            scale: _scale,
            alignment: Alignment.centerLeft,
            child: Opacity(
              opacity: _opacity,
              child: _OptionalBlur(
                blur: _blur,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12), // 卡片外边距
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12), // 仿 Apple Music 圆角
                    child: AnimatedBuilder(
                      animation: Listenable.merge(_ripples.map((r) => r.controller).toList()),
                      builder: (context, child) {
                        // 根据涟漪进度计算背景透明度
                        double bgOpacity = 0.0;
                        if (_ripples.isNotEmpty) {
                          final maxProgress = _ripples.map((r) => r.controller.value).reduce((a, b) => a > b ? a : b);
                          bgOpacity = 0.12 * (1.0 - maxProgress);
                        }

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10), // 卡片内边距
                          color: Colors.white.withValues(alpha: bgOpacity),
                          alignment: Alignment.centerLeft,
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              _buildInnerContent(),
                              // 涟漪层 (已在 ClipRRect 内部)
                              ..._ripples.map((ripple) => _buildRipple(ripple)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRipple(_RippleInfo ripple) {
    return AnimatedBuilder(
      animation: ripple.controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _RipplePainter(
            progress: ripple.controller.value,
            center: ripple.position,
          ),
        );
      },
    );
  }

  Widget _buildInnerContent() {
    final styleService = LyricStyleService();
    final fontFamily = LyricFontService().currentFontFamily ?? 'Microsoft YaHei';
    final double textFontSize = styleService.fontSize * 0.9;
    final textStyle = fluidCloudPanelTextStyle(
      fontFamily: fontFamily,
      fontSize: textFontSize,
    );

    // 点亮与未点亮都走同一套排版：逐字动画有上浮，若未点亮态改用 Text
    // 自己断行，两者折行位置会不同，滚到该行时整句突然重排。
    // 未点亮时 FluidCloudWordLine 内部不解算动画、不起 ticker。
    final Widget textWidget = FluidCloudWordLine(
      lyric: widget.lyric,
      active: widget.isActive && widget.lyric.hasWordByWord,
      centered: false,
      textStyle: textStyle,
      inactiveAlpha: _textColor.a,
      fallbackMaxWidth: widget.layoutWidth,
    );

    if (widget.showTranslation && widget.translation != null && widget.translation!.isNotEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          textWidget,
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              widget.translation!,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: textFontSize * 0.56,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.3),
                height: 1.4,
              ),
            ),
          )
        ],
      );
    }
    
    return textWidget;
  }
}

class _OptionalBlur extends StatelessWidget {
  final double blur;
  final Widget child;

  const _OptionalBlur({required this.blur, required this.child});

  @override
  Widget build(BuildContext context) {
    if (blur < 1.0) return child;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: child,
    );
  }
}

/// 涟漪信息类
class _RippleInfo {
  final Offset position;
  final AnimationController controller;
  _RippleInfo({required this.position, required this.controller});
}

/// 涟漪绘制器 - 仿 Apple Music 风格
class _RipplePainter extends CustomPainter {
  final double progress;
  final Offset center;

  _RipplePainter({required this.progress, required this.center});

  @override
  void paint(Canvas canvas, Size size) {
    // 极快扩张，平滑淡出
    final double radius = 300.0 * Curves.easeOutCubic.transform(progress);
    final double opacity = (1.0 - Curves.easeOut.transform(progress)) * 0.25;

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_RipplePainter oldDelegate) => oldDelegate.progress != progress;
}


/// 虚拟项占位点包装组件 - 适配移动端布局位置
class _CountdownDotsWrapper extends StatelessWidget {
  final Duration startTime;
  final Duration endTime;
  final double targetY;
  final double targetOpacity;
  final double layoutWidth;

  const _CountdownDotsWrapper({
    super.key,
    required this.startTime,
    required this.endTime,
    required this.targetY,
    required this.targetOpacity,
    required this.layoutWidth,
  });

  @override
  Widget build(BuildContext context) {
    if (targetOpacity < 0.01) return const SizedBox();

    return Positioned(
      top: targetY,
      left: 0,
      width: layoutWidth,
      child: Opacity(
        opacity: targetOpacity,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 28), // 与歌词卡片对齐
          alignment: Alignment.centerLeft,
          child: _CountdownDots(
            startTime: startTime,
            endTime: endTime,
          ),
        ),
      ),
    );
  }
}

/// 倒计时点组件 - Apple Music 风格 (从桌面端同步)
class _CountdownDots extends StatefulWidget {
  final Duration startTime;
  final Duration endTime;

  const _CountdownDots({
    required this.startTime,
    required this.endTime,
  });

  @override
  State<_CountdownDots> createState() => _CountdownDotsState();
}

class _CountdownDotsState extends State<_CountdownDots> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  
  // 动画状态
  double _scale = 0.0;
  double _dot0Opacity = 0.25;
  double _dot1Opacity = 0.25;
  double _dot2Opacity = 0.25;

  // 时间推算状态 (Extrapolation)
  Duration _lastSyncPlayerPos = Duration.zero;
  Duration _lastSyncTickerElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  double _easeOutExpo(double x) {
    return x == 1.0 ? 1.0 : 1.0 - pow(2, -10 * x);
  }

  double _easeInOutBack(double x) {
    const c1 = 1.70158;
    const c2 = c1 * 1.525;
    return x < 0.5
        ? (pow(2 * x, 2) * ((c2 + 1) * 2 * x - c2)) / 2
        : (pow(2 * x - 2, 2) * ((c2 + 1) * (x * 2 - 2) + c2) + 2) / 2;
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;

    final isPlaying = PlayerService().isPlaying;
    final currentPos = PlayerService().position;

    // --- 毫秒级外推逻辑，补偿 PlayerService.position 的更新频率 ---
    if (currentPos != _lastSyncPlayerPos) {
      _lastSyncPlayerPos = currentPos;
      _lastSyncTickerElapsed = elapsed;
    }

    Duration extrapolatedPos = currentPos;
    if (isPlaying) {
      final timeSinceSync = elapsed - _lastSyncTickerElapsed;
      if (timeSinceSync.inMilliseconds > 0 && timeSinceSync.inMilliseconds < 500) {
        extrapolatedPos = currentPos + timeSinceSync;
      }
    }

    final startMs = widget.startTime.inMilliseconds;
    final endMs = widget.endTime.inMilliseconds;
    final interludeDuration = (endMs - startMs).toDouble();
    final currentDuration = (extrapolatedPos.inMilliseconds - startMs).toDouble();

    if (interludeDuration <= 0) {
       _resetState();
       return;
    }

    // 核心动画算法：同步 Standalone Lyric Player / Desktop
    if (currentDuration <= interludeDuration && currentDuration >= 0) {
      const targetBreatheDuration = 1500.0;
      final breatheDuration = interludeDuration / (interludeDuration / targetBreatheDuration).ceil();
      
      double scale = 1.0;
      double globalOpacity = 1.0;

      // 1. 呼吸频率适应
      scale *= sin(1.5 * pi - (currentDuration / breatheDuration) * 2) / 20 + 1;

      // 2. 进场缩放
      if (currentDuration < 2000) {
        scale *= _easeOutExpo((currentDuration / 2000).clamp(0.0, 1.0));
      }

      // 3. 全局透明度渐入
      if (currentDuration < 500) {
        globalOpacity = 0.0;
      } else if (currentDuration < 1000) {
        globalOpacity *= (currentDuration - 500) / 500;
      }

      // 4. 离场动画 (回弹缩放 + 渐隐)
      if (interludeDuration - currentDuration < 750) {
        scale *= 1.0 - _easeInOutBack(((750 - (interludeDuration - currentDuration)) / 750 / 2).clamp(0.0, 1.0));
      }
      if (interludeDuration - currentDuration < 375) {
        globalOpacity *= ((interludeDuration - currentDuration) / 375).clamp(0.0, 1.0);
      }

      // 最终缩放倍率 (Apple Music 风格微调)
      scale = max(0.0, scale) * 0.65; // 移动端稍微小一点

      // 5. 圆点瀑布式亮度计算
      final dotsDuration = max(0.0, interludeDuration - 750);
      
      double getRawDotOpacity(double t) {
          if (dotsDuration <= 0) return 0.25;
          final val = (t * 3 / dotsDuration) * 0.75;
          return val.clamp(0.25, 1.0);
      }

      double d0 = getRawDotOpacity(currentDuration);
      double d1 = getRawDotOpacity(currentDuration - dotsDuration / 3);
      double d2 = getRawDotOpacity(currentDuration - (dotsDuration / 3) * 2);

      double finalize(double dotOp) => (max(0.0, globalOpacity * dotOp)).clamp(0.0, 1.0);

      setState(() {
        _scale = scale;
        _dot1Opacity = finalize(d1);
        _dot2Opacity = finalize(d2);
        _dot0Opacity = finalize(d0);
      });

    } else {
      _resetState();
    }
  }

  void _resetState() {
     if (_scale != 0.0 || _dot0Opacity != 0.0) {
        setState(() {
          _scale = 0.0;
          _dot0Opacity = 0.0; 
          _dot1Opacity = 0.0; 
          _dot2Opacity = 0.0;
        });
     }
  }

  @override
  Widget build(BuildContext context) {
    if (_scale <= 0.01) return const SizedBox();

    return Transform.scale(
      scale: _scale,
      alignment: Alignment.centerLeft,
      child: SizedBox(
        height: 40,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDot(_dot0Opacity),
            const SizedBox(width: 10), // 移动端间距微调
            _buildDot(_dot1Opacity),
            const SizedBox(width: 10),
            _buildDot(_dot2Opacity),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(double opacity) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: 18, // 桌面端 20，移动端 18
        height: 18,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

