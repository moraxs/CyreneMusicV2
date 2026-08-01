/// 歌词组：一行主歌词 + 可选的一行背景人声。
///
/// 对应 AMLL 的 `LyricLineGroupBase` / `LyricLineGroup`。纵向位移由本组的
/// [posY] 弹簧统一负责，背景人声的进出由 [bgSlideY] 弹簧驱动
/// （±80 表示隐藏在主歌词的下方或上方）。
library;

import 'dart:math' as math;

import 'package:flutter/animation.dart';

import '../core/layout.dart';
import '../core/lyric_types.dart';
import '../core/spring.dart';
import 'lyric_line_view.dart';

/// 背景人声隐藏时的滑动距离（百分比）
const double kBgSlideDistance = 80;

/// 非逐字模式下的换行动画曲线（流体云同款弹性曲线）。
const Curve _kElasticCurve = Cubic(0.34, 1.56, 0.64, 1.0);

/// 非逐字模式下换行动画的持续时间（秒）。
const double _kElasticDuration = 0.7;

class AmllLyricGroup extends InterludeGroup {
  AmllLyricGroup({required this.mainLine, double initialPosY = 0}) {
    posY.setPosition(initialPosY);
  }

  /// 主歌词行
  final AmllLyricLineView mainLine;

  /// 背景人声行
  AmllLyricLineView? bgLine;

  /// 纵向位移弹簧（像素）
  final Spring posY = Spring(0);

  /// 背景人声滑入/滑出弹簧（百分比，0 = 完全就位）
  final Spring bgSlideY = Spring(-kBgSlideDistance);

  /// 背景人声是否应显示在主歌词**上方**
  bool isBgFirst = false;

  double top = 0;
  double delay = 0;
  bool isActive = false;
  double opacity = 1;
  double blur = 0;

  bool _isNonDynamic = false;

  // 非逐字模式下的弹性换行动画状态（流体云同款）
  bool _elasticActive = false;
  double _elasticElapsed = 0;
  double _elasticFromY = 0;
  double _elasticToY = 0;
  double _elasticDelay = 0;

  @override
  int get startTime => mainLine.line.startTime;

  @override
  int get endTime => mainLine.line.endTime;

  @override
  bool get isDuet => mainLine.line.isDuet;

  /// 组的当前纵向位置
  double get currentTop => posY.getCurrentPosition();

  /// 背景人声的当前进场进度（0 = 完全隐藏，1 = 完全就位）
  double get bgActiveProgress {
    final slide = bgSlideY.getCurrentPosition();
    return (1 - slide.abs() / kBgSlideDistance).clamp(0.0, 1.0);
  }

  /// 背景人声的当前缩放（隐藏时 0.8，就位时 1.0）
  double get bgScale => 0.8 + bgActiveProgress * 0.2;

  /// 背景人声当前的纵向滑动量（百分比）
  double get bgSlidePercent => bgSlideY.getCurrentPosition();

  /// 挂上背景人声行。
  void addBgLine(AmllLyricLineView line) {
    bgLine = line;

    // 要比较第一个词的开始时间而不是行起始时间，因为行起始时间
    // 已经被 syncMainAndBackgroundLines 同步过了
    final bgStart = line.line.words.isNotEmpty
        ? line.line.words.first.startTime
        : line.line.startTime;
    final mainStart = mainLine.line.words.isNotEmpty
        ? mainLine.line.words.first.startTime
        : mainLine.line.startTime;

    isBgFirst = bgStart < mainStart;
    bgSlideY.setPosition(isBgFirst ? kBgSlideDistance : -kBgSlideDistance);
  }

  /// 设置本组的目标变换。
  void setTransform({
    required double top,
    required bool force,
    required double delay,
    required bool isActive,
    required double opacity,
    required double blur,
    required bool enableSpring,
    required bool enableScale,
    required bool isPlaying,
    required bool isNonDynamic,
    required bool alwaysPostpositionBackground,
  }) {
    this.top = top;
    this.delay = delay;
    this.isActive = isActive;
    this.opacity = opacity;
    this.blur = blur;
    _isNonDynamic = isNonDynamic;

    _setLineTransformations(
      force: force,
      delay: delay,
      enableScale: enableScale,
      isPlaying: isPlaying,
    );

    final shouldBgFirst = alwaysPostpositionBackground ? false : isBgFirst;
    final hiddenSlideY = shouldBgFirst ? kBgSlideDistance : -kBgSlideDistance;
    // 暂停时把背景人声显示出来
    final targetBgSlideY = (isActive || !isPlaying) ? 0.0 : hiddenSlideY;

    if (force || !enableSpring) {
      _elasticActive = false;
      posY.setPosition(top);
      bgSlideY.setPosition(targetBgSlideY);
    } else if (_isNonDynamic) {
      // 非逐字模式：posY 用流体云弹性曲线动画，bgSlideY 仍用弹簧
      if (!_elasticActive || (top - _elasticToY).abs() > 0.5) {
        _elasticFromY = posY.getCurrentPosition();
        _elasticToY = top;
        _elasticElapsed = 0;
        _elasticDelay = delay;
        _elasticActive = true;
      }
      bgSlideY.setTargetPosition(targetBgSlideY, delay);
    } else {
      _elasticActive = false;
      posY.setTargetPosition(top, delay);
      bgSlideY.setTargetPosition(targetBgSlideY, delay);
    }
  }

  void _setLineTransformations({
    required bool force,
    required double delay,
    required bool enableScale,
    required bool isPlaying,
  }) {
    final renderMode = isActive
        ? LyricLineRenderMode.gradient
        : LyricLineRenderMode.solid;

    final scaleAspect = enableScale ? 97.0 : 100.0;

    var mainScale = 100.0;
    if (!isActive && isPlaying) mainScale = scaleAspect;
    mainLine.setTransform(
      scale: mainScale,
      opacity: 1,
      blur: 0,
      force: force,
      delay: delay,
      mode: renderMode,
    );

    var bgScale = 100.0;
    if (!isActive && isPlaying) bgScale = 75;
    bgLine?.setTransform(
      scale: bgScale,
      opacity: 1,
      blur: 0,
      force: force,
      delay: delay,
      mode: renderMode,
    );
  }

  /// 逐帧推进（[delta] 秒）。
  void update(double delta, {required bool enableSpring}) {
    if (_elasticActive) {
      _elasticElapsed += delta;
      if (_elasticElapsed < _elasticDelay) {
        // delay 期间保持起始位置
        posY.setPosition(_elasticFromY);
      } else {
        final t = ((_elasticElapsed - _elasticDelay) / _kElasticDuration)
            .clamp(0.0, 1.0);
        final eased = _kElasticCurve.transform(t);
        posY.setPosition(_elasticFromY + (_elasticToY - _elasticFromY) * eased);
        if (t >= 1.0) _elasticActive = false;
      }
      // bgSlideY 仍用弹簧
      if (enableSpring) bgSlideY.update(delta);
    } else if (enableSpring) {
      posY.update(delta);
      bgSlideY.update(delta);
    }

    mainLine.update(delta);
    bgLine?.update(delta);
  }

  /// 本组内容的总高度。
  ///
  /// 必须与 widget 实际渲染出的高度一致（主歌词 + 翻译/音译 + 上下内边距 +
  /// 背景人声占位），否则下一行会压到翻译上。
  double contentHeight({required double verticalPadding}) {
    var h = mainLine.totalHeight + verticalPadding * 2;
    final bg = bgLine;
    if (bg != null) {
      // 背景人声完全隐藏时不占位；进场过程中按进度线性占位
      h += bg.totalHeight * bgActiveProgress;
    }
    return h;
  }

  /// 本组是否落在视区内（含 overscan）。
  ///
  /// 同时考虑当前位置与目标位置：新歌词的初始位置在视区外很远，若只看当前
  /// 位置，行要等弹簧飞进视区才会被构建和测量，期间布局只能用兜底高度，
  /// 会在入场时产生一次突跳。
  bool isInSight({
    required double viewportHeight,
    required double overscanPx,
    required double measuredHeight,
  }) {
    final h = measuredHeight;
    final lower = -h - overscanPx;
    final upper = viewportHeight + h + overscanPx;

    bool within(double t) => t >= lower && t <= upper;

    return within(posY.getCurrentPosition()) ||
        within(posY.getTargetPosition());
  }

  void enable() {
    mainLine.enable();
    bgLine?.enable();
  }

  void disable() {
    mainLine.disable();
    bgLine?.disable();
  }

  void teardownContent() {
    mainLine.teardownContent();
    bgLine?.teardownContent();
  }

  /// 更新纵向弹簧参数（含背景人声滑动）。
  void updatePosYSpringParams(SpringParams params) {
    posY.updateParams(params);
    bgSlideY.updateParams(params);
  }

  /// 更新缩放弹簧参数。
  void updateScaleSpringParams({
    required SpringParams mainParams,
    required SpringParams bgParams,
  }) {
    mainLine.scaleSpring.updateParams(mainParams);
    bgLine?.scaleSpring.updateParams(bgParams);
  }

  /// 组内所有行是否都已构建内容
  bool get isBuilt => mainLine.isBuilt && (bgLine?.isBuilt ?? true);

  /// 组内是否存在强调词
  bool get hasEmphasis =>
      mainLine.hasEmphasis || (bgLine?.hasEmphasis ?? false);

  /// 主歌词与背景人声中较大的宽度
  double get contentWidth =>
      math.max(mainLine.size.width, bgLine?.size.width ?? 0);
}
