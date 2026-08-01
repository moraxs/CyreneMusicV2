/// 文字段落缓存。
///
/// 逐帧重建 `TextPainter` 并 `layout()` 会反复做文字 shaping —— 这是绘制里
/// 最贵的一步。歌词每帧只有透明度在连续变化，字形本身不变，因此把
/// [ui.Paragraph] 按「文本 + 字体属性 + 量化后的透明度」缓存起来复用。
///
/// 透明度量化到 [_alphaSteps] 档：视觉上看不出差别，但能让缓存命中率接近
/// 100%（同一行内大量词共用同一档透明度）。
library;

import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// 透明度量化档数
const int _alphaSteps = 48;

/// 缓存容量上限，超出后按 LRU 淘汰
const int _maxCacheEntries = 2048;

class _ParagraphKey {
  const _ParagraphKey({
    required this.text,
    required this.fontSize,
    required this.fontWeightIndex,
    required this.fontFamily,
    required this.height,
    required this.alphaStep,
    required this.colorValue,
    required this.maxWidth,
    required this.textAlignIndex,
  });

  final String text;
  final double fontSize;
  final int fontWeightIndex;
  final String? fontFamily;
  final double? height;
  final int alphaStep;

  /// 不含透明度的颜色分量
  final int colorValue;
  final double maxWidth;
  final int textAlignIndex;

  @override
  bool operator ==(Object other) =>
      other is _ParagraphKey &&
      other.text == text &&
      other.fontSize == fontSize &&
      other.fontWeightIndex == fontWeightIndex &&
      other.fontFamily == fontFamily &&
      other.height == height &&
      other.alphaStep == alphaStep &&
      other.colorValue == colorValue &&
      other.maxWidth == maxWidth &&
      other.textAlignIndex == textAlignIndex;

  @override
  int get hashCode => Object.hash(
    text,
    fontSize,
    fontWeightIndex,
    fontFamily,
    height,
    alphaStep,
    colorValue,
    maxWidth,
    textAlignIndex,
  );
}

/// 带 LRU 淘汰的段落缓存。
class LyricTextCache {
  LyricTextCache._();

  static final LyricTextCache instance = LyricTextCache._();

  final LinkedHashMap<_ParagraphKey, ui.Paragraph> _cache =
      LinkedHashMap<_ParagraphKey, ui.Paragraph>();

  /// 命中/未命中计数，仅用于调试与测试
  int hits = 0;
  int misses = 0;

  /// 取得一个已完成 layout 的段落。
  ///
  /// [color] 的透明度会被量化，因此调用方无需自己节流。
  ui.Paragraph paragraph({
    required String text,
    required TextStyle style,
    required Color color,
    double maxWidth = double.infinity,
    TextAlign textAlign = TextAlign.left,
  }) {
    final fontSize = style.fontSize ?? 24;
    final alphaStep = (color.a * _alphaSteps).round();

    final key = _ParagraphKey(
      text: text,
      fontSize: fontSize,
      fontWeightIndex: (style.fontWeight ?? FontWeight.normal).value,
      fontFamily: style.fontFamily,
      height: style.height,
      alphaStep: alphaStep,
      colorValue: (color.withValues(alpha: 1.0).toARGB32()) & 0x00FFFFFF,
      maxWidth: maxWidth,
      textAlignIndex: textAlign.index,
    );

    final cached = _cache.remove(key);
    if (cached != null) {
      // remove + 重新插入 = 标记为最近使用
      _cache[key] = cached;
      hits++;
      return cached;
    }

    misses++;
    final quantizedColor = color.withValues(
      alpha: (alphaStep / _alphaSteps).clamp(0.0, 1.0),
    );

    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: textAlign,
        fontSize: fontSize,
        fontWeight: style.fontWeight,
        fontFamily: style.fontFamily,
        height: style.height,
        textDirection: TextDirection.ltr,
      ),
    )
      ..pushStyle(
        ui.TextStyle(
          color: quantizedColor,
          fontSize: fontSize,
          fontWeight: style.fontWeight,
          fontFamily: style.fontFamily,
          height: style.height,
        ),
      )
      ..addText(text);

    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: maxWidth));

    if (_cache.length >= _maxCacheEntries) {
      // 淘汰最久未使用的一批，避免每次插入都触发单条淘汰
      final evictCount = _maxCacheEntries ~/ 4;
      final keys = _cache.keys.take(evictCount).toList();
      for (final k in keys) {
        _cache.remove(k);
      }
    }
    _cache[key] = paragraph;
    return paragraph;
  }

  /// 清空缓存（字体或字号整体变化时调用）。
  void clear() {
    _cache.clear();
    hits = 0;
    misses = 0;
  }

  int get length => _cache.length;
}
