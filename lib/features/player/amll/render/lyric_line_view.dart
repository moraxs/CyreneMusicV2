/// 单行歌词的可绘制对象。
///
/// 对应 AMLL 的 `LyricLineEl`：持有该行的排版、逐词动画解算、缩放弹簧、
/// 亮暗透明度平滑器，并按需构建/拆除内容（对应 `show` / `teardownContent`）。
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/fade_mask.dart';
import '../core/lyric_types.dart';
import '../core/spring.dart';
import '../core/split_words.dart';
import 'lyric_line_layout.dart';
import 'lyric_line_painter.dart';
import 'mask_alpha.dart';

/// 单行歌词的运行时状态。
class AmllLyricLineView {
  AmllLyricLineView({required this.line, required this.isBG});

  final AmllLyricLine line;

  /// 是否为背景人声行
  final bool isBG;

  /// 行缩放弹簧，单位是百分比（100 = 原始大小），与 AMLL 一致
  final Spring scaleSpring = Spring(100);

  final MaskAlphaSmoother _alpha = MaskAlphaSmoother();

  LyricLineRenderMode _renderMode = LyricLineRenderMode.solid;
  double _targetScale = 100;
  double _blur = 0;
  double _opacity = 1;
  double _delay = 0;

  bool _isEnabled = false;
  bool _built = false;

  LyricLineLayout? _layout;
  List<WordAnimations> _animations = const [];
  TextStyle? _builtStyle;
  double _builtMaxWidth = 0;

  /// 翻译行 + 音译行占用的高度（含与主歌词之间的间距）。
  ///
  /// 必须参与组高度计算，否则下一行会压到翻译上。
  double _subLinesHeight = 0;
  String? _builtTranslation;
  String? _builtRoman;

  /// 该行渐变的总时长（毫秒）
  int _fadeDuration = 1;

  double get blur => _blur;
  double get opacity => _opacity;
  double get delay => _delay;
  LyricLineRenderMode get renderMode => _renderMode;
  bool get isEnabled => _isEnabled;
  bool get isBuilt => _built;
  LyricLineLayout? get layout => _layout;
  List<WordAnimations> get animations => _animations;
  double get brightAlpha => _alpha.brightAlpha;
  double get darkAlpha => _alpha.darkAlpha;

  /// 当前缩放（1.0 = 原始大小）
  double get currentScale => scaleSpring.getCurrentPosition() / 100;

  /// 主歌词内容尺寸；未构建时为零
  Size get size => _layout?.size ?? Size.zero;

  /// 翻译行 + 音译行的高度（含间距）
  double get subLinesHeight => _subLinesHeight;

  /// 本行渲染占用的总高度（主歌词 + 副歌词）
  double get totalHeight => size.height + _subLinesHeight;

  /// 构建该行的排版与动画解算（进入视区时调用）。
  ///
  /// 已按相同的样式与宽度构建过则直接复用。
  void build({
    required TextStyle textStyle,
    required double maxWidth,
    required bool isNonDynamic,
    required double wordFadeWidth,
    String Function(AmllLyricWord word)? processWord,
    String translation = '',
    String roman = '',
  }) {
    if (_built &&
        _builtStyle == textStyle &&
        (_builtMaxWidth - maxWidth).abs() < 0.5 &&
        _builtTranslation == translation &&
        _builtRoman == roman) {
      return;
    }

    final layout = layoutLyricLine(
      line: line,
      textStyle: textStyle,
      maxWidth: maxWidth,
      isNonDynamic: isNonDynamic,
      processWord: processWord,
      isDuet: line.isDuet,
    );

    _layout = layout;
    _builtStyle = textStyle;
    _builtMaxWidth = maxWidth;
    _builtTranslation = translation;
    _builtRoman = roman;
    _built = true;

    _subLinesHeight = measureSubLines(
      translation: translation,
      roman: roman,
      mainStyle: textStyle,
      maxWidth: maxWidth,
    );

    _animations = solveWordAnimations(
      layout: layout,
      lineStartTime: line.startTime,
      lineEndTime: line.endTime,
      lineWords: line.words,
      isBG: isBG,
      wordFadeWidth: wordFadeWidth,
    );
    _fadeDuration = math.max(
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
        lineStartTime: line.startTime,
        lineEndTime: line.endTime,
      ),
    );
  }

  /// 拆除内容以释放内存（离开视区时调用）。
  void teardownContent() {
    _layout = null;
    _animations = const [];
    _built = false;
    _builtStyle = null;
    _builtMaxWidth = 0;
    _builtTranslation = null;
    _builtRoman = null;
    // 高度刻意不清零：组高度要在内容拆除后依然可用，
    // 否则滚出视区的行会塌陷、把后面所有行往上拽。
  }

  /// 该行被激活（进入播放）。
  void enable() {
    _isEnabled = true;
  }

  /// 该行被取消激活。
  void disable() {
    _isEnabled = false;
    _renderMode = LyricLineRenderMode.solid;
  }

  /// 设置该行的目标变换。
  ///
  /// 与 AMLL 的 `LyricLineEl.setTransform` 对应：纵向位移由所属 group 负责，
  /// 这里只处理缩放、透明度、模糊与渲染模式。
  void setTransform({
    required double scale,
    required double opacity,
    required double blur,
    required bool force,
    required double delay,
    required LyricLineRenderMode mode,
  }) {
    _renderMode = mode;
    _targetScale = scale;
    _opacity = opacity;
    _delay = delay;

    if (force) {
      _blur = math.min(32, blur);
      scaleSpring.setPosition(scale);
      _alpha.updateTargets(scale / 100, mode);
      _alpha.snapToTarget();
    } else {
      scaleSpring.setTargetPosition(scale);
      _blur = math.min(5, blur);
    }
  }

  /// 逐帧推进（[delta] 秒）。
  void update(double delta) {
    scaleSpring.update(delta);
    if (!_built) return;
    _alpha.updateTargets(currentScale, _renderMode);
    _alpha.update(delta);
  }

  /// 当前时间下，该行的渐变进度（0..1）。
  double fadeProgressAt(int currentTimeMs) {
    final relative = currentTimeMs - line.startTime;
    if (relative <= 0) return 0;
    if (relative >= _fadeDuration) return 1;
    return relative / _fadeDuration;
  }

  /// 当前时间相对该行开始的毫秒数（可为负）。
  double relativeTimeAt(int currentTimeMs) =>
      (currentTimeMs - line.startTime).toDouble();

  /// 构造该行的 painter。
  ///
  /// 未构建内容时返回 null。
  LyricLinePainter? buildPainter({
    required int currentTimeMs,
    required TextStyle textStyle,
    required Color baseColor,
    required bool enableGlow,
    double groupOpacity = 1.0,
  }) {
    final layout = _layout;
    if (layout == null) return null;
    return LyricLinePainter(
      groupOpacity: groupOpacity,
      layout: layout,
      animations: _animations,
      textStyle: textStyle,
      relativeTimeMs: relativeTimeAt(currentTimeMs),
      fadeProgress: fadeProgressAt(currentTimeMs),
      brightAlpha: _alpha.brightAlpha,
      darkAlpha: _alpha.darkAlpha,
      baseColor: baseColor,
      renderMode: _renderMode,
      enableGlow: enableGlow,
    );
  }

  /// 该行的目标缩放（百分比）
  double get targetScale => _targetScale;

  /// 是否含有可强调的词（用于判断是否值得开启辉光绘制）
  bool get hasEmphasis =>
      _animations.any((a) => a.emphasis != null) ||
      line.words.any(shouldEmphasize);
}
