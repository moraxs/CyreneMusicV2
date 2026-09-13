/// 1:1 移植 `lyric-player/base.ts` 的 `LyricLineBase` 与
/// `lyric-player/dom/lyric-line.ts` 的 `LyricLineEl` 中与「状态」有关的部分。
///
/// DOM 那边靠 Web Animations 的播放头表达时间，这里换成两个显式时钟：
/// - [elementTime]：`elementAnimations`（整词上浮 / 强调）的播放头，
///   `enable()` 归零正放，`disable()` 转成 -1 倍速回放；
/// - [maskTime]：`maskAnimations`（逐字渐变遮罩）的播放头，
///   `enable(t)` 时按 `t - line.startTime` 落点。
///
/// 样式表里的 `transition` 是浏览器隐式做的，移植时必须显式补出来，
/// 见 [mainOpacity] / [blurValue] / [bgOpacity]。
library;

import 'dart:math' as math;

import '../core/interfaces.dart';
import '../core/spring.dart';
import '../render/css_transition.dart';
import '../render/line_layout.dart';

class V2LyricLineEl {
  V2LyricLineEl({required this.line, required this.windowHeight}) {
    // `this.lineTransforms.posY.setPosition(window.innerHeight * 2)`
    posY.setPosition(windowHeight * 2);
  }

  final V2LyricLine line;
  final double windowHeight;

  /// `lineTransforms`
  final V2Spring posY = V2Spring(0);
  final V2Spring scaleSpring = V2Spring(100);

  double top = 0;
  double scale = 100;
  double blur = 0;
  double opacity = 1;

  /// 秒，`setTargetPosition(top, delay)` 用
  double delay = 0;

  bool isEnabled = false;

  /// `.lyricMainLine { transition: opacity 0.3s 0.1s }`
  final V2CssTransition mainOpacity = V2CssTransition(
    initialValue: 1,
    durationMs: 300,
    delayMs: 100,
  );

  /// `.lyricLine { transition: ... filter 0.2s ... }`
  final V2CssTransition blurValue = V2CssTransition(
    initialValue: 0,
    durationMs: 200,
  );

  /// `.lyricBgLine { opacity: 0.0001; transition: opacity 0.25s }`
  /// `.lyricBgLine.active { opacity: 0.4; transition: opacity 0.5s 0.25s }`
  ///
  /// 进入 active 与退出 active 的时长/延时不同，所以要两条。
  final V2CssTransition bgOpacityIn = V2CssTransition(
    initialValue: 0.0001,
    durationMs: 500,
    delayMs: 250,
  );
  final V2CssTransition bgOpacityOut = V2CssTransition(
    initialValue: 0.0001,
    durationMs: 250,
  );
  bool _bgActiveLast = false;

  /// 布局产物，由播放器在尺寸/字号变化时重建
  V2LineLayout? layout;

  // ---- 动画时钟 ----

  /// `elementAnimations` 的播放头，单位毫秒
  double elementTime = 0;
  double _elementRate = 1;

  /// `maskAnimations` 的播放头，单位毫秒
  double maskTime = 0;

  /// 两个时钟是否在走。
  ///
  /// **初始必须是 false**：上游的 `elementAnimations` / `maskAnimations` 建出来
  /// 就调了 `a.pause()`，要等 `enable()` 才 `play()`。若这里默认 true，从未播到
  /// 的行 `maskTime` 会从对象创建起一路累加，很快越过 `totalFadeDuration`、
  /// 把遮罩停在「全亮」——播放时因为非当前行 `bright == dark == 0.2` 看不出来，
  /// 一暂停（所有行 scale 回 100，bright/dark 拉开到 1.0/0.4）就会整屏高亮。
  bool _clockPlaying = false;

  int get totalDuration => line.endTime - line.startTime;

  /// `enable(maskAnimationTime = this.lyricLine.startTime)`
  void enable([int? maskAnimationTime]) {
    isEnabled = true;
    final t = (maskAnimationTime ?? line.startTime) - line.startTime;
    elementTime = 0;
    _elementRate = 1;
    maskTime = math.min(totalDuration.toDouble(), math.max(0, t.toDouble()));
    _clockPlaying = true;
  }

  /// `disable()`：只有 `float-word` 这一条会倒放，遮罩不动。
  void disable() {
    isEnabled = false;
    _elementRate = -1;
  }

  void resume() {
    if (!isEnabled) return;
    _clockPlaying = true;
  }

  void pause() {
    if (!isEnabled) return;
    _clockPlaying = false;
  }

  /// `LyricLineEl.setTransform`
  void setTransform({
    required double top,
    required double scale,
    required double opacity,
    required double blur,
    bool force = false,
    double delay = 0,
    required bool enableSpring,
  }) {
    this.top = top;
    this.scale = scale;
    this.opacity = opacity;
    this.delay = delay;

    // `main.style.opacity = `${opacity}``（无条件，走 CSS transition）
    mainOpacity.setTarget(opacity);

    if (force || !enableSpring) {
      this.blur = math.min(32, blur);
      blurValue.jumpTo(this.blur);
      posY.setPosition(top);
      scaleSpring.setPosition(scale);
    } else {
      posY.setTargetPosition(top, delay);
      scaleSpring.setTargetPosition(scale);
      if (this.blur != math.min(32, blur)) {
        this.blur = math.min(32, blur);
        blurValue.setTarget(this.blur);
      }
    }
  }

  /// `LyricLineEl.update(delta)`，[delta] 单位秒（与 JS 一致）。
  void update(
    double delta, {
    required bool enableSpring,
    required bool playing,
  }) {
    final deltaMs = delta * 1000;
    if (enableSpring) {
      posY.update(delta);
      scaleSpring.update(delta);
    }
    mainOpacity.update(deltaMs);
    blurValue.update(deltaMs);
    bgOpacityIn.update(deltaMs);
    bgOpacityOut.update(deltaMs);

    if (_clockPlaying) {
      elementTime = math.max(0, elementTime + deltaMs * _elementRate);
      maskTime += deltaMs;
    }

    if (line.isBG) {
      // `.amll-lyric-player:not(.playing) > .lyricBgLine { opacity: 0.4 }`
      final active = isEnabled || !playing;
      if (active != _bgActiveLast) {
        _bgActiveLast = active;
        if (active) {
          bgOpacityIn.jumpTo(bgOpacityOut.value);
          bgOpacityIn.setTarget(0.4);
        } else {
          bgOpacityOut.jumpTo(bgOpacityIn.value);
          bgOpacityOut.setTarget(0.0001);
        }
      }
    }
  }

  /// `.lyricBgLine` 的行级不透明度；非背景行恒为 1。
  double get bgOpacity =>
      line.isBG ? (_bgActiveLast ? bgOpacityIn.value : bgOpacityOut.value) : 1;

  /// `--bright-mask-alpha`
  double get brightMaskAlpha =>
      math.max(
            0.0,
            math.min(1.0, scaleSpring.getCurrentPosition() / 100 - 0.97) / 0.03,
          ) *
          0.8 +
      0.2;

  /// `--dark-mask-alpha`
  double get darkMaskAlpha =>
      math.max(
            0.0,
            math.min(1.0, scaleSpring.getCurrentPosition() / 100 - 0.97) / 0.03,
          ) *
          0.2 +
      0.2;

  /// `get isInSight()`
  bool isInSight(double playerHeight, double overscanPx) {
    final t = posY.getCurrentPosition();
    final h = layout?.size.height ?? 0;
    final b = t + h;
    return !(t > playerHeight + h + overscanPx || b < -h - overscanPx);
  }
}
