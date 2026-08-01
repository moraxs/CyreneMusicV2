/// 歌词行的排版解算。
///
/// AMLL 在 DOM 里靠 `inline-block` + `white-space: pre-wrap` 让浏览器折行，
/// 并用 `emphasizeWrapper` 保证连写的词不被拆开。这里用 [TextPainter] 逐词
/// 测量后自己折行，得到每个词的精确位置，供绘制与遮罩几何使用。
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/is_cjk.dart';
import '../core/lyric_types.dart';
import '../core/split_words.dart';

/// 排版后的单个词。
class LaidOutWord {
  LaidOutWord({
    required this.word,
    required this.text,
    required this.offset,
    required this.size,
    required this.lineIndex,
    required this.shouldEmphasize,
    required this.graphemes,
    required this.romanWord,
  });

  /// 原始词数据
  final AmllLyricWord word;

  /// 实际绘制的文本（可能经过不雅用语掩码）
  final String text;

  /// 相对整行内容左上角的位置
  final Offset offset;

  /// 词的绘制尺寸
  final Size size;

  /// 所在视觉行（折行后的第几行）
  final int lineIndex;

  /// 是否应用强调辉光
  final bool shouldEmphasize;

  /// 强调时按字素拆分的结果；不强调时为空
  final List<LaidOutGrapheme> graphemes;

  /// 音译文本，无则为空串
  final String romanWord;

  double get left => offset.dx;
  double get right => offset.dx + size.width;
}

/// 强调词内的单个字素。
class LaidOutGrapheme {
  LaidOutGrapheme({
    required this.text,
    required this.offset,
    required this.size,
  });

  final String text;

  /// 相对所属词左上角的位置
  final Offset offset;
  final Size size;
}

/// 整行歌词的排版结果。
class LyricLineLayout {
  const LyricLineLayout({
    required this.words,
    required this.size,
    required this.lineCount,
    required this.lineHeight,
    required this.isNonDynamic,
    required this.plainText,
    required this.textAlign,
  });

  /// 排版后的所有词（不含纯空白）
  final List<LaidOutWord> words;

  /// 主歌词内容的总尺寸
  final Size size;

  /// 折行后的视觉行数
  final int lineCount;

  /// 单行高度
  final double lineHeight;

  /// 是否为逐行歌词（此时按 [plainText] 整行绘制，不做逐词几何）
  final bool isNonDynamic;

  /// 逐行歌词的整行文本
  final String plainText;

  /// 整行绘制时的对齐方式（对唱行右对齐）
  final TextAlign textAlign;
}

/// 副歌词行（翻译 / 音译）的样式。
///
/// 对应 CSS `.lyricSubLine`：字号 `max(0.5em, 10px)`、行高 1.5em、不透明度 0.3。
/// 布局测量与实际绘制必须共用本函数，否则组高度会和渲染结果不一致。
TextStyle subLineStyle(TextStyle mainStyle) {
  final mainFontSize = mainStyle.fontSize ?? 24;
  return mainStyle.copyWith(
    fontSize: math.max(mainFontSize * 0.5, 10),
    fontWeight: FontWeight.w500,
    height: 1.5,
  );
}

/// 主歌词与副歌词之间的间距。
///
/// 对应 `.lyricLineWrapper` 的 `gap: 0.3em`。
double subLineGap(TextStyle mainStyle) => (mainStyle.fontSize ?? 24) * 0.3;

/// 行的上下内边距（单侧）。
///
/// 对应 `.lyricLineWrapper` 的 `padding: 0.4em`。
double lineVerticalPadding(TextStyle mainStyle) =>
    (mainStyle.fontSize ?? 24) * 0.4;

/// 测量翻译行 + 音译行占用的总高度（含与主歌词之间的间距）。
double measureSubLines({
  required String translation,
  required String roman,
  required TextStyle mainStyle,
  required double maxWidth,
}) {
  if (translation.isEmpty && roman.isEmpty) return 0;

  final style = subLineStyle(mainStyle);
  var height = subLineGap(mainStyle);

  for (final text in <String>[translation, roman]) {
    if (text.isEmpty) continue;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    height += painter.height;
    painter.dispose();
  }

  return height;
}

/// 按字素簇拆分字符串。
///
/// 对应 AMLL 的 `Intl.Segmenter(granularity: 'grapheme')`。`characters` 包
/// 实现的是 Unicode 扩展字素簇，能正确处理 emoji、组合字符、变体选择符与
/// 国旗序列；它由 `package:flutter/widgets.dart` 再导出，无需新增依赖。
List<String> splitGraphemes(String text) {
  if (text.isEmpty) return const [];
  return text.characters.toList();
}

/// 解算一行歌词的排版。
///
/// [maxWidth] 是可用宽度；[textStyle] 用于主歌词。连写词组（[WordChunk.isGroup]）
/// 会被当作一个整体考虑折行，与 DOM 的 `emphasizeWrapper` 语义一致。
LyricLineLayout layoutLyricLine({
  required AmllLyricLine line,
  required TextStyle textStyle,
  required double maxWidth,
  required bool isNonDynamic,
  String Function(AmllLyricWord word)? processWord,
  bool isDuet = false,
}) {
  final resolveText = processWord ?? (AmllLyricWord w) => w.word;

  // 逐行歌词：整行一次性排版，不需要逐词几何
  if (isNonDynamic) {
    final plainText = line.words.map(resolveText).join();
    final painter = TextPainter(
      text: TextSpan(text: plainText, style: textStyle),
      textDirection: TextDirection.ltr,
      textAlign: isDuet ? TextAlign.right : TextAlign.left,
    )..layout(maxWidth: maxWidth);

    final result = LyricLineLayout(
      words: const [],
      size: Size(painter.width, painter.height),
      lineCount: painter.computeLineMetrics().length,
      lineHeight: painter.preferredLineHeight,
      isNonDynamic: true,
      plainText: plainText,
      textAlign: isDuet ? TextAlign.right : TextAlign.left,
    );
    painter.dispose();
    return result;
  }

  final chunks = chunkAndSplitLyricWords(line.words);

  // 先测每个 chunk 的宽度，用于折行决策
  final measured = <_MeasuredChunk>[];
  for (final chunk in chunks) {
    final isSpace = chunk.words.every((w) => w.word.trim().isEmpty);
    if (isSpace) {
      final spaceText = chunk.words.map((w) => w.word).join();
      measured.add(
        _MeasuredChunk(
          chunk: chunk,
          isSpace: true,
          width: _measureWidth(spaceText, textStyle),
          wordWidths: const [],
          wordTexts: const [],
        ),
      );
      continue;
    }

    final wordTexts = <String>[];
    final wordWidths = <double>[];
    var total = 0.0;
    for (final w in chunk.words) {
      final text = resolveText(w);
      final trimmed = w.word.trim().isEmpty ? text : text.trim();
      wordTexts.add(trimmed);
      final width = _measureWidth(trimmed, textStyle);
      wordWidths.add(width);
      total += width;
    }
    measured.add(
      _MeasuredChunk(
        chunk: chunk,
        isSpace: false,
        width: total,
        wordWidths: wordWidths,
        wordTexts: wordTexts,
      ),
    );
  }

  final probe = TextPainter(
    text: TextSpan(text: 'Ag', style: textStyle),
    textDirection: TextDirection.ltr,
  )..layout();
  final lineHeight = probe.preferredLineHeight;
  probe.dispose();

  // 折行：连写组整体换行
  final laidOut = <LaidOutWord>[];
  var cursorX = 0.0;
  var lineIndex = 0;
  var maxLineWidth = 0.0;
  final lineWidths = <double>[];

  void finishLine() {
    lineWidths.add(cursorX);
    if (cursorX > maxLineWidth) maxLineWidth = cursorX;
  }

  for (final m in measured) {
    if (m.isSpace) {
      // 行首的空白不占位，避免折行后出现悬挂空格
      if (cursorX > 0) cursorX += m.width;
      continue;
    }

    final needsWrap = cursorX > 0 && cursorX + m.width > maxWidth;
    if (needsWrap) {
      finishLine();
      cursorX = 0;
      lineIndex++;
    }

    final emp = _chunkShouldEmphasize(m.chunk);

    for (var i = 0; i < m.chunk.words.length; i++) {
      final w = m.chunk.words[i];
      final text = m.wordTexts[i];
      final width = m.wordWidths[i];

      final graphemes = <LaidOutGrapheme>[];
      if (emp) {
        var gx = 0.0;
        for (final g in splitGraphemes(text)) {
          final gw = _measureWidth(g, textStyle);
          graphemes.add(
            LaidOutGrapheme(
              text: g,
              offset: Offset(gx, 0),
              size: Size(gw, lineHeight),
            ),
          );
          gx += gw;
        }
      }

      laidOut.add(
        LaidOutWord(
          word: w,
          text: text,
          offset: Offset(cursorX, lineIndex * lineHeight),
          size: Size(width, lineHeight),
          lineIndex: lineIndex,
          shouldEmphasize: emp,
          graphemes: graphemes,
          romanWord: w.romanWord.trim(),
        ),
      );
      cursorX += width;
    }
  }
  finishLine();

  // 对唱行右对齐：把每行整体右移
  if (isDuet) {
    final contentWidth = math.max(maxLineWidth, 0.0);
    for (var i = 0; i < laidOut.length; i++) {
      final word = laidOut[i];
      final shift = contentWidth - lineWidths[word.lineIndex];
      if (shift <= 0) continue;
      laidOut[i] = LaidOutWord(
        word: word.word,
        text: word.text,
        offset: Offset(word.offset.dx + shift, word.offset.dy),
        size: word.size,
        lineIndex: word.lineIndex,
        shouldEmphasize: word.shouldEmphasize,
        graphemes: word.graphemes,
        romanWord: word.romanWord,
      );
    }
  }

  return LyricLineLayout(
    words: laidOut,
    size: Size(maxLineWidth, lineHeight * (lineIndex + 1)),
    lineCount: lineIndex + 1,
    lineHeight: lineHeight,
    isNonDynamic: false,
    plainText: '',
    textAlign: isDuet ? TextAlign.right : TextAlign.left,
  );
}

/// 一组连写词是否应用强调。
///
/// 与原实现一致：组内任一词命中即命中；若合并后的整体不是 CJK，
/// 还要再用合并词判定一次（让 "wo"+"rd" 这类拆分词也能作为整体触发）。
bool _chunkShouldEmphasize(WordChunk chunk) {
  var emp = chunk.words.any(shouldEmphasize);
  if (emp) return true;

  if (chunk.words.length <= 1) return false;

  var start = chunk.words.first.startTime;
  var end = chunk.words.first.endTime;
  final buffer = StringBuffer();
  for (final w in chunk.words) {
    if (w.startTime < start) start = w.startTime;
    if (w.endTime > end) end = w.endTime;
    buffer.write(w.word);
  }
  final merged = AmllLyricWord(
    word: buffer.toString(),
    startTime: start,
    endTime: end,
  );
  if (!isCJK(merged.word)) {
    emp = emp || shouldEmphasize(merged);
  }
  return emp;
}

final Map<_MeasureKey, double> _widthCache = <_MeasureKey, double>{};

double _measureWidth(String text, TextStyle style) {
  if (text.isEmpty) return 0;
  final key = _MeasureKey(text, style);
  final cached = _widthCache[key];
  if (cached != null) return cached;

  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();

  // 简单容量上限，避免长时间播放后无界增长
  if (_widthCache.length > 4096) _widthCache.clear();
  _widthCache[key] = width;
  return width;
}

class _MeasureKey {
  const _MeasureKey(this.text, this.style);

  final String text;
  final TextStyle style;

  @override
  bool operator ==(Object other) =>
      other is _MeasureKey && other.text == text && other.style == style;

  @override
  int get hashCode => Object.hash(text, style);
}

class _MeasuredChunk {
  const _MeasuredChunk({
    required this.chunk,
    required this.isSpace,
    required this.width,
    required this.wordWidths,
    required this.wordTexts,
  });

  final WordChunk chunk;
  final bool isSpace;
  final double width;
  final List<double> wordWidths;
  final List<String> wordTexts;
}
