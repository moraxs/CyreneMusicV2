import 'dart:math' as math;
import 'dart:ui' as ui show Image, ImageFilter;
import 'dart:ui' show Canvas, Picture, PictureRecorder, TextDirection;

import 'package:flutter/material.dart';

import '../../../application/playback/playback_controller.dart';
import '../../../domain/models/music_source.dart';
import '../../../domain/models/track.dart';
import '../mobile/compat/lyric_line.dart';
import '../mobile/compat/lyric_parser.dart';
import 'default_core/default_timeline.dart';
import 'default_core/default_types.dart';
import 'super_cyrene_lyric_timing.dart';

/// 像素歌词主题。移植自 Tauri 项目 SuperCyrenePlayer 的 pixel-core：
/// 文字先高分辨率光栅、再 1/8 最近邻降采样、显示时最近邻放大，形成硬边
/// 像素马赛克；逐字进度驱动颜色（白→淡薰衣草）、透明度（0.5→0.92）、辉光
/// （呼吸调制）与「灵魂离体」ghost。3D 飞越简化为 2D 纵向滚动 + 弹簧追踪。
class SuperCyrenePixelLyrics extends StatefulWidget {
  const SuperCyrenePixelLyrics({
    super.key,
    required this.playback,
    required this.track,
    required this.onTranslationChanged,
  });

  final PlaybackController playback;
  final Track track;
  final ValueChanged<String?> onTranslationChanged;

  @override
  State<SuperCyrenePixelLyrics> createState() => _SuperCyrenePixelLyricsState();
}

class _SuperCyrenePixelLyricsState extends State<SuperCyrenePixelLyrics>
    with SingleTickerProviderStateMixin {
  List<DefaultLine> _lines = const [];
  int _activeIdx = -1;
  int _lastTranslationIdx = -2;

  // 滚动弹簧（像素）：目标 = activeIdx * linePitch。
  double _scrollPx = 0;
  // 活跃行逐字包络状态（按 active 行 words 顺序）。
  List<double> _lightVals = const [];
  List<double> _soulVals = const [];

  late final AnimationController _frames;
  Duration _lastTick = Duration.zero;

  // 像素光栅缓存：key = word 文本。base 像素图 + 测量尺寸。
  final Map<String, _PixelRaster> _rasters = {};
  final Set<String> _rasterInFlight = {};

  static const _rasterFontPx = 96.0; // 高分辨率光栅字号
  static const _pixelBlock = 8; // 像素块尺寸（越大越粗犷）
  static const _padEm = 0.2;
  static const _lineBandEm = 1.4;

  // 显示字号。
  static const _activeFontPx = 40.0;
  static const _neighborFontPx = 22.0;
  static const _linePitchPx = _activeFontPx * 2.6;

  // 主题色（照搬 default-adapter SUPER_CYRENE_DEFAULT_THEME）。
  static const _primary = Color(0xFFFFFFFF);
  static const _accent = Color(0xFFDDD6FE);
  static const _secondary = Color(0xFFC4B5FD);

  // 逐字动力学常量（照搬 PixelScene.tsx）。
  static const _activeLineOpacity = 0.92;
  static const _unsungOpacity = 0.5;
  static const _glowMax = 0.9;
  static const _soulMax = 0.6;
  static const _soulDetachLiftEm = 0.5;
  static const _soulActiveLiftEm = 0.06;
  static const _soulActiveSwell = 0.1;
  static const _soulDetachSwell = 0.3;
  static const _soulHandoff = 0.5; // 秒

  @override
  void initState() {
    super.initState();
    // duration 设成一个极长的周期：repeat() 要求 period>0，用一天作为上限，
    // 实际只利用它每帧触发的 ticker 驱动 _advance（与经典主题 default_canvas 一致）。
    _frames = AnimationController(
      vsync: this,
      duration: const Duration(days: 1),
    )..repeat();
    // 翻译回调必须经独立监听器在 build 外触发——不能在 _advance（AnimatedBuilder
    // builder 内）调用 onTranslationChanged，否则父级 setState 会落在 build 期导致
    // "setState() called during build"。与经典主题一致，走 positionListenable。
    widget.playback.positionListenable.addListener(_updateTranslation);
    _adaptTrack();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lastTick = _now;
      _updateTranslation();
    });
  }

  @override
  void didUpdateWidget(covariant SuperCyrenePixelLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playback != widget.playback) {
      oldWidget.playback.positionListenable.removeListener(_updateTranslation);
      widget.playback.positionListenable.addListener(_updateTranslation);
    }
    if (_lyricSignature(oldWidget.track) != _lyricSignature(widget.track)) {
      _disposeRasters();
      _adaptTrack();
    }
  }

  int _lyricSignature(Track track) =>
      Object.hash(track.key, track.lyric, track.yrc, track.tlyric, track.ytlrc);

  Duration get _now => widget.playback.positionListenable.value;

  double get _nowSec => _now.inMicroseconds / 1000000 + 0.3;

  void _adaptTrack() {
    final lyric = widget.track.lyric;
    final parsed = lyric == null || lyric.isEmpty
        ? const <LyricLine>[]
        : switch (widget.track.source) {
            MusicSource.qq => LyricParser.parseQQLyric(
              lyric,
              translation: widget.track.tlyric,
              qrcLyric: widget.track.yrc,
              qrcTranslation: widget.track.ytlrc,
            ),
            MusicSource.kugou => LyricParser.parseKugouLyric(
              lyric,
              translation: widget.track.tlyric,
            ),
            _ => LyricParser.parseNeteaseLyric(
              lyric,
              translation: widget.track.tlyric,
              yrcLyric: widget.track.yrc,
              yrcTranslation: widget.track.ytlrc,
            ),
          };
    _lines = parsed.indexed
        .where((entry) => entry.$2.text.trim().isNotEmpty)
        .map((entry) => _adaptLine(entry.$2, entry.$1, parsed))
        .toList(growable: false);
    _activeIdx = -1;
    _lastTranslationIdx = -2;
    _scrollPx = 0;
  }

  DefaultLine _adaptLine(LyricLine line, int index, List<LyricLine> source) {
    final fallbackEnd = index + 1 < source.length
        ? source[index + 1].startTime
        : line.startTime + (line.lineDuration ?? const Duration(seconds: 4));
    final lineEnd =
        line.startTime + (line.lineDuration ?? fallbackEnd - line.startTime);
    final words = buildSuperCyreneWordTimeline(line: line, lineEnd: lineEnd);
    return DefaultLine(
      id: '${line.startTime.inMilliseconds}-$index',
      fullText: words.map((word) => word.text).join(),
      startTime: line.startTime.inMicroseconds / 1000000,
      endTime: lineEnd.inMicroseconds / 1000000,
      translation: line.translation,
      words: words,
    );
  }

  void _updateTranslation() {
    if (!mounted || _lines.isEmpty) return;
    final idx = findDefaultTimelineLine(_lines, _nowSec);
    if (idx == _lastTranslationIdx) return;
    _lastTranslationIdx = idx;
    widget.onTranslationChanged(
      idx >= 0 ? _lines[idx].translation?.trim() : null,
    );
  }

  // —— 每帧推进：滚动弹簧 + 逐字包络 + 翻译 ——
  void _advance() {
    if (_lines.isEmpty) return;
    final tickNow = _now;
    var dt = (tickNow - _lastTick).inMicroseconds / 1000000;
    if (dt < 0) dt = 0;
    if (dt > 0.05) dt = 0.05; // 防止丢帧后大跳
    _lastTick = tickNow;

    final now = _nowSec;
    final newActive = findDefaultTimelineLine(_lines, now);
    if (newActive != _activeIdx) {
      _activeIdx = newActive;
      if (newActive >= 0 && newActive < _lines.length) {
        final w = _lines[newActive].words;
        _lightVals = List<double>.filled(w.length, 0);
        _soulVals = List<double>.filled(w.length, 0);
        _ensureLineRasters(_lines[newActive]);
      }
      // 翻译由 positionListenable 监听器在 build 之外触发，不在 build 期 setState。
    }

    // 滚动弹簧追踪 activeIdx*linePitch。
    final target = _activeIdx * _linePitchPx;
    _scrollPx = _stepEnvelope(_scrollPx, target, 12, 6, dt);

    if (_activeIdx >= 0 && _activeIdx < _lines.length) {
      final words = _lines[_activeIdx].words;
      for (var i = 0; i < words.length; i++) {
        final w = words[i];
        final isCurrent = now >= w.startTime && now < w.endTime;
        _lightVals[i] =
            _stepEnvelope(_lightVals[i], isCurrent ? 1 : 0, 14, 4.5, dt);
        _soulVals[i] =
            _stepEnvelope(_soulVals[i], isCurrent ? 1 : 0, 12, 2.2, dt);
      }
    }
  }

  // —— 像素光栅生成（async，一次缓存）——
  void _ensureLineRasters(DefaultLine line) {
    for (final word in line.words) {
      _ensureRaster(word.text);
    }
  }

  Future<void> _ensureRaster(String text) async {
    final key = text;
    if (key.trim().isEmpty) return;
    if (_rasters.containsKey(key) || _rasterInFlight.contains(key)) return;
    _rasterInFlight.add(key);
    _PixelRaster? raster;
    try {
      raster = await _buildRaster(key);
    } catch (e) {
      // toImage 在极端尺寸/平台下可能抛错；静默丢弃，回退到普通文字。
      debugPrint('[PixelLyrics] 光栅失败 "$key": $e');
    }
    if (!mounted) {
      raster?.dispose();
      _rasterInFlight.remove(key);
      return;
    }
    if (raster != null && !_rasters.containsKey(key)) {
      _rasters[key] = raster;
    } else {
      raster?.dispose();
    }
    _rasterInFlight.remove(key);
    // 无需 setState：_frames..repeat() 每帧已在重绘，下一帧自然取到新光栅。
  }

  Future<_PixelRaster?> _buildRaster(String text) async {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: _rasterFontPx,
          fontWeight: FontWeight.w700,
          color: Color(0xFFFFFFFF),
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    )..layout(maxWidth: 4096);
    final advance = math.max(1.0, tp.width.ceilToDouble());
    final pad = (_rasterFontPx * _padEm).ceilToDouble();
    final canvasW = (advance + pad * 2).ceilToDouble();
    final canvasH = (_rasterFontPx * _lineBandEm + pad * 2).ceilToDouble();

    // 1) 高分辨率白字图。
    final hiPic = _recordPicture(
      Size(canvasW, canvasH),
      (c) => tp.paint(c, Offset(pad, (canvasH - tp.height) / 2)),
    );
    final hi = await hiPic.toImage(canvasW.toInt(), canvasH.toInt());
    hiPic.dispose();

    // 2) 1/8 最近邻降采样得像素图。
    final smallW = math.max(1, (canvasW / _pixelBlock).floor());
    final smallH = math.max(1, (canvasH / _pixelBlock).floor());
    final downPic = _recordPicture(
      Size(smallW.toDouble(), smallH.toDouble()),
      (c) => c.drawImageRect(
        hi,
        Rect.fromLTWH(0, 0, canvasW, canvasH),
        Rect.fromLTWH(0, 0, smallW.toDouble(), smallH.toDouble()),
        Paint()..filterQuality = FilterQuality.none,
      ),
    );
    final small = await downPic.toImage(smallW, smallH);
    downPic.dispose();
    hi.dispose();

    return _PixelRaster(
      image: small,
      advancePx: advance,
      canvasW: canvasW,
      canvasH: canvasH,
      pad: pad,
    );
  }

  Picture _recordPicture(Size size, void Function(Canvas) draw) {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));
    draw(canvas);
    return recorder.endRecording();
  }

  @override
  void dispose() {
    widget.playback.positionListenable.removeListener(_updateTranslation);
    _frames.dispose();
    _disposeRasters();
    super.dispose();
  }

  void _disposeRasters() {
    for (final r in _rasters.values) {
      r.dispose();
    }
    _rasters.clear();
    _rasterInFlight.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_lines.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .3),
            fontSize: 14,
            letterSpacing: 2.8,
          ),
        ),
      );
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _frames,
        builder: (context, _) {
          _advance();
          return CustomPaint(
            size: Size.infinite,
            painter: _PixelLyricPainter(state: this),
          );
        },
      ),
    );
  }
}

/// 单个像素光栅。
class _PixelRaster {
  _PixelRaster({
    required this.image,
    required this.advancePx,
    required this.canvasW,
    required this.canvasH,
    required this.pad,
  });

  final ui.Image image;
  final double advancePx;
  final double canvasW;
  final double canvasH;
  final double pad;

  double scaleFor(double displayFontPx) => displayFontPx / 96.0;

  void dispose() => image.dispose();
}

/// 像素歌词绘制器。
class _PixelLyricPainter extends CustomPainter {
  _PixelLyricPainter({required this.state});

  final _SuperCyrenePixelLyricsState state;

  @override
  void paint(Canvas canvas, Size size) {
    final lines = state._lines;
    if (lines.isEmpty || size.isEmpty) return;
    final now = state._nowSec;
    final active = state._activeIdx;
    final linePitch = _SuperCyrenePixelLyricsState._linePitchPx;
    // 滚动弹簧剩余位移：scroll 追踪 active*linePitch，差值即未到位的偏移。
    // 行 i 的纵坐标 = centerY + (i-active)*linePitch + springOffset，
    // 这样活跃行（i==active）正好落在视口正中央。
    final springOffset = active * linePitch - state._scrollPx;
    final centerY = size.height / 2;
    final maxW = size.width * 0.8;

    // 邻居行（active-3 .. active+4），跳过 active 自身。
    for (var offset = -3; offset <= 4; offset++) {
      if (offset == 0) continue;
      final i = active + offset;
      if (i < 0 || i >= lines.length) continue;
      final opacity = _neighborOpacity(offset);
      if (opacity <= 0) continue;
      final y = centerY + offset * linePitch + springOffset;
      final tint = offset < 0
          ? _SuperCyrenePixelLyricsState._primary
          : _SuperCyrenePixelLyricsState._secondary;
      _drawLineWords(
        canvas, size, lines[i], y,
        _SuperCyrenePixelLyricsState._neighborFontPx,
        maxW, tint, opacity,
      );
    }

    // 活跃行。
    if (active >= 0 && active < lines.length) {
      final activeY = centerY + springOffset;
      _drawActiveLine(canvas, size, lines[active], activeY, now, maxW);
    }
  }

  double _neighborOpacity(int offset) {
    if (offset == -1) return 0.3;
    if (offset == -2) return 0.1;
    if (offset == 1) return 0.34;
    if (offset == 2) return 0.16;
    if (offset == 3) return 0.06;
    return 0;
  }

  void _drawLineWords(
    Canvas canvas,
    Size size,
    DefaultLine line,
    double y,
    double fontPx,
    double maxW,
    Color tint,
    double opacity,
  ) {
    final scale = fontPx / 96.0;
    double total = 0;
    for (final w in line.words) {
      final r = state._rasters[w.text];
      total += (r != null ? r.advancePx : w.text.length * 60.0) * scale;
    }
    total += (line.words.length - 1) * 4 * scale;
    final fit = total > maxW ? (maxW / total) : 1.0;
    final startX = (size.width - total * fit) / 2;
    double x = startX;
    for (final w in line.words) {
      final r = state._rasters[w.text];
      double advancePx;
      if (r != null) {
        advancePx = r.advancePx * scale;
        final dstW = r.canvasW * scale * fit;
        final dstH = r.canvasH * scale * fit;
        final dst = Rect.fromLTWH(
            x - r.pad * scale * fit, y - dstH / 2, dstW, dstH);
        _blit(canvas, r, dst, tint, opacity, FilterQuality.none,
            BlendMode.srcOver);
      } else {
        advancePx = _drawFallbackWord(canvas, w.text, x, y, fontPx * fit,
            tint.withValues(alpha: opacity * 0.6));
      }
      x += advancePx * fit + 4 * scale * fit;
    }
  }

  void _drawActiveLine(
    Canvas canvas,
    Size size,
    DefaultLine line,
    double y,
    double now,
    double maxW,
  ) {
    final breath = 0.9 + 0.1 * math.sin(now * 1.9);
    final words = line.words;
    final lightVals = state._lightVals;
    final soulVals = state._soulVals;

    // 先量总宽以居中。
    final scale = _SuperCyrenePixelLyricsState._activeFontPx / 96.0;
    double total = 0;
    for (final w in words) {
      final r = state._rasters[w.text];
      total += (r != null ? r.advancePx : w.text.length * 60.0) * scale;
    }
    total += (words.length - 1) * 4 * scale; // 字间小间距
    final fit = total > maxW ? (maxW / total) : 1.0;
    final startX = (size.width - total * fit) / 2;

    double x = startX;
    for (var idx = 0; idx < words.length; idx++) {
      final w = words[idx];
      final r = state._rasters[w.text];
      double advancePx;
      if (r != null) {
        advancePx = r.advancePx * scale;
        final dstW = r.canvasW * scale * fit;
        final dstH = r.canvasH * scale * fit;
        final dst = Rect.fromLTWH(x - r.pad * scale * fit, y - dstH / 2, dstW, dstH);

        final sung = now >= w.endTime;
        final isCurrent = now >= w.startTime && now < w.endTime;
        final span = math.max(w.endTime - w.startTime, 0.001);
        final sungMix = sung ? 1.0
            : isCurrent ? (now - w.startTime).clamp(0.0, span) / span : 0.0;
        final light = idx < lightVals.length ? lightVals[idx] : 0.0;
        final soul = idx < soulVals.length ? soulVals[idx] : 0.0;

        final opacity = math.min(
          1.0,
          (_SuperCyrenePixelLyricsState._unsungOpacity +
              (_SuperCyrenePixelLyricsState._activeLineOpacity -
                  _SuperCyrenePixelLyricsState._unsungOpacity) *
              sungMix),
        );
        final colorProgress = (light * 1.15).clamp(0.0, 1.0);
        final color = Color.lerp(
          _SuperCyrenePixelLyricsState._primary,
          _SuperCyrenePixelLyricsState._accent,
          colorProgress,
        )!;

        // 基底（最近邻放大 = 像素马赛克）。
        _blit(canvas, r, dst, color, opacity, FilterQuality.none,
            BlendMode.srcOver);

        // 辉光：呼吸调制，当前字发光。
        final glow = math.min(
          1.0,
          _SuperCyrenePixelLyricsState._glowMax *
              light *
              breath *
              (0.6 + 0.4) *
              1.0,
        );
        if (glow > 0.02) {
          final glowRect = dst.inflate(dst.width * 0.08);
          _blitGlow(canvas, r, glowRect, _SuperCyrenePixelLyricsState._accent,
              glow);
        }

        // 灵魂离体：唱完后 ghost 上浮 + 放大 + 淡出。
        final flightMix = sung
            ? _smoothstep((now - w.endTime).clamp(0.0, 1.0) /
                _SuperCyrenePixelLyricsState._soulHandoff)
            : 0.0;
        final onGlyph = (1 - flightMix) * 1.0;
        final flown = flightMix * 1.0;
        final soulOpacity = math.min(
          1.0,
          _SuperCyrenePixelLyricsState._soulMax * 1.0 * soul *
              (onGlyph + flown),
        );
        if (soulOpacity > 0.02) {
          final lift = _SuperCyrenePixelLyricsState._activeFontPx *
              (_SuperCyrenePixelLyricsState._soulActiveLiftEm * onGlyph +
                  _SuperCyrenePixelLyricsState._soulDetachLiftEm * flown);
          final swell = 1 +
              _SuperCyrenePixelLyricsState._soulActiveSwell * onGlyph +
              _SuperCyrenePixelLyricsState._soulDetachSwell * flown;
          final soulRect = Rect.fromCenter(
            center: dst.center + Offset(0, -lift),
            width: dst.width * swell,
            height: dst.height * swell,
          );
          _blit(canvas, r, soulRect, color, soulOpacity, FilterQuality.none,
              BlendMode.plus);
        }
      } else {
        // 光栅未就绪：回退到普通文字（非像素），淡显。
        advancePx = _drawFallbackWord(canvas, w.text, x, y,
            _SuperCyrenePixelLyricsState._activeFontPx * fit,
            Colors.white.withValues(alpha: .4));
      }
      x += advancePx * fit + 4 * scale * fit;
    }
  }

  double _drawFallbackWord(
    Canvas canvas, String text, double x, double y, double fontPx, Color color,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontPx, fontWeight: FontWeight.w700, color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    )..layout(maxWidth: 4096);
    tp.paint(canvas, Offset(x, y - tp.height / 2));
    final w = tp.width;
    return w;
  }

  void _blit(
    Canvas canvas,
    _PixelRaster r,
    Rect dst,
    Color color,
    double opacity,
    FilterQuality quality,
    BlendMode blend,
  ) {
    final paint = Paint()
      ..filterQuality = quality
      ..blendMode = blend
      ..colorFilter = ColorFilter.mode(
        color.withValues(alpha: opacity.clamp(0.0, 1.0)),
        BlendMode.srcIn,
      );
    canvas.drawImageRect(
      r.image,
      Rect.fromLTWH(0, 0, r.image.width.toDouble(), r.image.height.toDouble()),
      dst,
      paint,
    );
  }

  void _blitGlow(
    Canvas canvas,
    _PixelRaster r,
    Rect dst,
    Color color,
    double opacity,
  ) {
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..blendMode = BlendMode.plus
      ..imageFilter = ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6)
      ..colorFilter = ColorFilter.mode(
        color.withValues(alpha: opacity.clamp(0.0, 1.0)),
        BlendMode.srcIn,
      );
    canvas.drawImageRect(
      r.image,
      Rect.fromLTWH(0, 0, r.image.width.toDouble(), r.image.height.toDouble()),
      dst,
      paint,
    );
  }

  double _smoothstep(double t) {
    final c = t.clamp(0.0, 1.0);
    return c * c * (3 - 2 * c);
  }

  @override
  bool shouldRepaint(covariant _PixelLyricPainter oldDelegate) => true;
}

double _stepEnvelope(double current, double target, double attack,
    double release, double delta) {
  return current + (target - current) * (1 - math.exp(
    -(target > current ? attack : release) * delta,
  ));
}
