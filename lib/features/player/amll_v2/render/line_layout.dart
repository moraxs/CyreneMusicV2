/// 1:1 移植 `dom/lyric-line.ts` 的 `rebuildElement` / `buildChunkGroup` /
/// `buildSingleWord`，外加浏览器替我们做掉的那部分：inline-block 的换行排版。
///
/// 产物是一份纯数据的「行渲染模型」，绘制层只读它，不再做任何测量。
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/interfaces.dart';
import '../core/lyric_split_words.dart';
import 'metrics.dart';
import 'word_animations.dart';

/// 强调词里的一个字符（对应一个 `<span>`）。
class V2RenderChar {
  V2RenderChar({
    required this.char,
    required this.x,
    required this.width,
    required this.empIndex,
    required this.painter,
  });

  final String char;

  /// 相对所属词盒左边缘
  final double x;
  final double width;

  /// 在整组强调动画里的字符序号（连写组内跨词连续编号）
  final int empIndex;

  final TextPainter painter;
}

/// 一个渲染单元，对应 DOM 里 `.lyricMainLine` 下的一个 `<span>`。
class V2RenderWord {
  V2RenderWord({
    required this.word,
    required this.text,
    required this.romanWord,
    required this.emphasize,
    required this.chars,
    required this.width,
    required this.height,
    required this.padding,
    required this.float,
    required this.painter,
    required this.romanPainter,
  });

  final V2LyricWord word;
  final String text;
  final String romanWord;
  final bool emphasize;
  final List<V2RenderChar> chars;

  /// `el.clientWidth - padding * 2`
  final double width;

  /// `el.clientHeight - padding * 2`
  final double height;

  /// `.lyricMainLine > span { padding: 1em }`
  final double padding;

  final V2FloatAnimation float;

  /// 非强调词用整段 painter；强调词为 null（逐字画）
  final TextPainter? painter;

  /// 词内音译（`.romanWord`）
  final TextPainter? romanPainter;

  /// 同一连写组共享一个强调动画实例（JS 侧也是一次 `initEmphasizeAnimation`
  /// 覆盖整组字符）
  V2EmphasizeAnimation? emp;

  /// 词盒左上角，相对主歌词行的内容原点
  double x = 0;
  double y = 0;

  /// `generateWebAnimationBasedMaskImage` 生成的关键帧
  List<V2MaskFrame> maskFrames = const [];
}

/// 一整行的渲染模型。
class V2LineLayout {
  V2LineLayout({
    required this.line,
    required this.words,
    required this.mainSize,
    required this.contentWidth,
    required this.paddingLeft,
    required this.paddingRight,
    required this.paddingTop,
    required this.paddingBottom,
    required this.translation,
    required this.roman,
    required this.size,
    required this.totalFadeDuration,
    required this.fadeWidth,
  });

  final V2LyricLine line;
  final List<V2RenderWord> words;

  /// `.lyricMainLine` 的尺寸
  final Size mainSize;

  final double contentWidth;
  final double paddingLeft;
  final double paddingRight;
  final double paddingTop;
  final double paddingBottom;

  final TextPainter? translation;
  final TextPainter? roman;

  /// `.lyricLine` 的整体尺寸，即 `lyricLinesSize` 里存的那对数
  final Size size;

  /// `generateWebAnimationBasedMaskImage` 的 `totalFadeDuration`
  final double totalFadeDuration;

  /// `word.height * wordFadeWidth`，整行取第一个词的高度（同字号下一致）
  final double fadeWidth;
}

class _Inline {
  _Inline.space(this.width) : word = null, height = 0;
  _Inline.word(V2RenderWord this.word)
    : width = word.width,
      height = word.height;

  final V2RenderWord? word;
  final double width;
  final double height;

  bool get isSpace => word == null;
}

/// 行排版器。
class V2LineLayoutBuilder {
  V2LineLayoutBuilder({
    required this.metrics,
    required this.isNonDynamic,
    required this.wordFadeWidth,
    required this.textScaler,
  });

  final V2CssMetrics metrics;
  final bool isNonDynamic;
  final double wordFadeWidth;
  final TextScaler textScaler;

  TextPainter _paint(String text, TextStyle style, {double? maxWidth}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: maxWidth == null ? 1 : null,
    )..layout(maxWidth: maxWidth ?? double.infinity);
    return tp;
  }

  V2LineLayout build(V2LyricLine line) {
    final isBG = line.isBG;
    final mainStyle = metrics.mainTextStyle(isBG);
    final romanStyle = metrics.romanWordTextStyle(isBG);
    final padLeft = metrics.linePaddingLeft(isBG, line.isDuet);
    final padRight = metrics.linePaddingRight(isBG, line.isDuet);
    final padTop = metrics.linePaddingTop(isBG);
    final padBottom = metrics.linePaddingBottom(isBG);
    final contentWidth = math.max(
      0.0,
      metrics.playerSize.width - padLeft - padRight,
    );
    final textHeight = metrics.lineTextHeight(isBG);
    final wordPadding = metrics.wordPadding(isBG);
    final spaceWidth = _paint(' ', mainStyle).width;

    final words = <V2RenderWord>[];
    final inlines = <_Inline>[];

    if (isNonDynamic) {
      // `main.innerText = this.lyricLine.words.map(w => w.word).join("")`
      final text = line.words.map((w) => w.word).join();
      final tp = _paint(text, mainStyle, maxWidth: contentWidth);
      final w = V2RenderWord(
        word: V2LyricWord(
          word: text,
          startTime: line.startTime,
          endTime: line.endTime,
        ),
        text: text,
        romanWord: '',
        emphasize: false,
        chars: const [],
        width: tp.width,
        height: tp.height,
        padding: wordPadding,
        float: V2FloatAnimation(delayMs: 0, durationMs: 0, up: 0),
        painter: tp,
        romanPainter: null,
      );
      words.add(w);
      inlines.add(_Inline.word(w));
    } else {
      final chunks = chunkAndSplitLyricWords(line.words);
      for (final chunk in chunks) {
        if (chunk.isGroup) {
          if (chunk.words.isEmpty) continue;
          _buildChunkGroup(
            chunk.words,
            line,
            mainStyle,
            romanStyle,
            textHeight,
            wordPadding,
            spaceWidth,
            words,
            inlines,
          );
        } else if (chunk.word!.word.trim().isEmpty) {
          inlines.add(_Inline.space(spaceWidth));
        } else {
          _buildSingleWord(
            chunk.word!,
            line,
            mainStyle,
            romanStyle,
            textHeight,
            wordPadding,
            spaceWidth,
            words,
            inlines,
          );
        }
      }
    }

    final mainSize = _layoutInlines(
      inlines,
      contentWidth,
      textHeight,
      line.isDuet,
    );

    // ---- 副行 ----
    final subStyle = metrics.subTextStyle(isBG);
    final translation = line.translatedLyric.isEmpty
        ? null
        : _paint(line.translatedLyric, subStyle, maxWidth: contentWidth);
    final romanLine = line.romanLyric.isEmpty
        ? null
        : _paint(line.romanLyric, subStyle, maxWidth: contentWidth);

    final totalHeight =
        padTop +
        mainSize.height +
        (translation?.height ?? 0) +
        (romanLine?.height ?? 0) +
        padBottom;

    // ---- 遮罩关键帧 ----
    // `totalFadeDuration = max(max(w.endTime), line.endTime) - line.startTime`
    var maxWordEnd = 0;
    for (final w in words) {
      maxWordEnd = math.max(maxWordEnd, w.word.endTime);
    }
    final totalFadeDuration =
        (math.max(maxWordEnd, line.endTime) - line.startTime).toDouble();
    final fadeWidth =
        (words.isEmpty ? textHeight : words.first.height) * wordFadeWidth;

    if (!isNonDynamic && words.isNotEmpty && totalFadeDuration > 0) {
      final metricsList = words
          .map(
            (w) => V2MaskWordMetric(
              width: w.width,
              padding: w.padding,
              startTime: w.word.startTime,
              endTime: w.word.endTime,
            ),
          )
          .toList();
      for (var i = 0; i < words.length; i++) {
        words[i].maskFrames = buildMaskFrames(
          words: metricsList,
          index: i,
          lineStartTime: line.startTime,
          totalFadeDuration: totalFadeDuration,
          fadeWidth: (words[i].height) * wordFadeWidth,
        );
      }
    }

    return V2LineLayout(
      line: line,
      words: words,
      mainSize: mainSize,
      contentWidth: contentWidth,
      paddingLeft: padLeft,
      paddingRight: padRight,
      paddingTop: padTop,
      paddingBottom: padBottom,
      translation: translation,
      roman: romanLine,
      size: Size(metrics.playerSize.width, totalHeight),
      totalFadeDuration: totalFadeDuration,
      fadeWidth: fadeWidth,
    );
  }

  // ------------------------------------------------------------ 词构建

  V2RenderWord _makeWord({
    required V2LyricWord word,
    required String text,
    required bool emphasize,
    required V2LyricLine line,
    required TextStyle mainStyle,
    required TextStyle romanStyle,
    required double textHeight,
    required double wordPadding,
    required int empIndexBase,
  }) {
    final up = line.isBG ? 0.1 : 0.05; // `let up = 0.05; if (isBG) up *= 2;`
    final float = V2FloatAnimation(
      delayMs: (word.startTime - line.startTime).toDouble(),
      durationMs: math.max(1000, word.endTime - word.startTime).toDouble(),
      up: up,
    );
    final hasRoman = word.romanWord.trim().isNotEmpty;
    final romanPainter = hasRoman ? _paint(word.romanWord, romanStyle) : null;

    if (emphasize) {
      // 逐字：每个字符一个 `<span>`
      final chars = <V2RenderChar>[];
      var x = 0.0;
      var i = 0;
      for (final ch in text.characters) {
        final tp = _paint(ch, mainStyle);
        chars.add(
          V2RenderChar(
            char: ch,
            x: x,
            width: tp.width,
            empIndex: empIndexBase + i,
            painter: tp,
          ),
        );
        x += tp.width;
        i++;
      }
      final width = math.max(x, romanPainter?.width ?? 0);
      return V2RenderWord(
        word: word,
        text: text,
        romanWord: hasRoman ? word.romanWord : '',
        emphasize: true,
        chars: chars,
        width: width,
        height: textHeight + (romanPainter?.height ?? 0),
        padding: wordPadding,
        float: float,
        painter: null,
        romanPainter: romanPainter,
      );
    }

    final tp = _paint(text, mainStyle);
    return V2RenderWord(
      word: word,
      text: text,
      romanWord: hasRoman ? word.romanWord : '',
      emphasize: false,
      chars: const [],
      width: math.max(tp.width, romanPainter?.width ?? 0),
      height: textHeight + (romanPainter?.height ?? 0),
      padding: wordPadding,
      float: float,
      painter: tp,
      romanPainter: romanPainter,
    );
  }

  /// `buildChunkGroup`
  void _buildChunkGroup(
    List<V2LyricWord> chunk,
    V2LyricLine line,
    TextStyle mainStyle,
    TextStyle romanStyle,
    double textHeight,
    double wordPadding,
    double spaceWidth,
    List<V2RenderWord> out,
    List<_Inline> inlines,
  ) {
    // 聚合区间与文本作为合并词
    final merged = V2LyricWord(
      word: '',
      romanWord: '',
      startTime: 0x7FFFFFFFFFFFFFF,
      endTime: -0x7FFFFFFFFFFFFFF,
    );
    for (final b in chunk) {
      merged.endTime = math.max(merged.endTime, b.endTime);
      merged.startTime = math.min(merged.startTime, b.startTime);
      merged.word += b.word;
    }
    var emp = shouldEmphasize(merged, isCJK);
    for (final w in chunk) {
      emp = emp || shouldEmphasize(w, isCJK);
    }

    final groupWords = <V2RenderWord>[];
    var empIndexBase = 0;
    for (final word in chunk) {
      final text = emp ? word.word.trim() : word.word;
      final rw = _makeWord(
        word: word,
        text: text,
        emphasize: emp,
        line: line,
        mainStyle: mainStyle,
        romanStyle: romanStyle,
        textHeight: textHeight,
        wordPadding: wordPadding,
        empIndexBase: empIndexBase,
      );
      empIndexBase += rw.chars.length;
      groupWords.add(rw);
      out.add(rw);
    }

    if (emp) {
      // 整组共享一次 `initEmphasizeAnimation(merged, characterElements, ...)`
      final anim = V2EmphasizeAnimation(
        word: merged,
        lineWords: line.words,
        charCount: empIndexBase,
        duration: (merged.endTime - merged.startTime).toDouble(),
        delay: (merged.startTime - line.startTime).toDouble(),
        isBG: line.isBG,
      );
      for (final w in groupWords) {
        w.emp = anim;
      }
    }

    // 前后空格处理（保持原有判断）
    if (merged.word.trimLeft() != merged.word) {
      inlines.add(_Inline.space(spaceWidth));
    }
    // 一组连写词共用一个 `.emphasizeWrapper`，不允许在组内换行
    for (final w in groupWords) {
      inlines.add(_Inline.word(w));
    }
    if (merged.word.trimRight() != merged.word &&
        shouldEmphasize(merged, isCJK)) {
      inlines.add(_Inline.space(spaceWidth));
    }
  }

  /// `buildSingleWord`
  void _buildSingleWord(
    V2LyricWord chunk,
    V2LyricLine line,
    TextStyle mainStyle,
    TextStyle romanStyle,
    double textHeight,
    double wordPadding,
    double spaceWidth,
    List<V2RenderWord> out,
    List<_Inline> inlines,
  ) {
    final emp = shouldEmphasize(chunk, isCJK);
    final hasRoman = chunk.romanWord.trim().isNotEmpty;
    // 非强调且带音译时，JS 用未 trim 的原文；其余一律 trim
    final text = (!emp && hasRoman) ? chunk.word : chunk.word.trim();
    final rw = _makeWord(
      word: chunk,
      text: text,
      emphasize: emp,
      line: line,
      mainStyle: mainStyle,
      romanStyle: romanStyle,
      textHeight: textHeight,
      wordPadding: wordPadding,
      empIndexBase: 0,
    );
    if (emp) {
      rw.emp = V2EmphasizeAnimation(
        word: chunk,
        lineWords: line.words,
        charCount: rw.chars.length,
        duration: (chunk.endTime - chunk.startTime).abs().toDouble(),
        delay: (chunk.startTime - line.startTime).toDouble(),
        isBG: line.isBG,
      );
    }

    if (chunk.word.trimLeft() != chunk.word) {
      inlines.add(_Inline.space(spaceWidth));
    }
    inlines.add(_Inline.word(rw));
    if (chunk.word.trimRight() != chunk.word) {
      inlines.add(_Inline.space(spaceWidth));
    }
    out.add(rw);
  }

  // ------------------------------------------------------- inline 换行排版

  /// 把 inline-block 序列按内容宽度贪心折行，写回每个词的 [V2RenderWord.x] /
  /// [V2RenderWord.y]，返回 `.lyricMainLine` 的尺寸。
  Size _layoutInlines(
    List<_Inline> inlines,
    double contentWidth,
    double defaultRowHeight,
    bool isDuet,
  ) {
    final rows = <List<_Inline>>[];
    var row = <_Inline>[];
    var rowWidth = 0.0;

    for (final item in inlines) {
      if (item.isSpace) {
        // 行首的空白会被折叠掉
        if (row.isEmpty) continue;
        row.add(item);
        rowWidth += item.width;
        continue;
      }
      if (row.isNotEmpty && rowWidth + item.width > contentWidth) {
        // 换行：行尾的空白不占位
        while (row.isNotEmpty && row.last.isSpace) {
          rowWidth -= row.removeLast().width;
        }
        rows.add(row);
        row = <_Inline>[];
        rowWidth = 0;
      }
      row.add(item);
      rowWidth += item.width;
    }
    while (row.isNotEmpty && row.last.isSpace) {
      row.removeLast();
    }
    if (row.isNotEmpty) rows.add(row);

    var y = 0.0;
    var maxWidth = 0.0;
    for (final r in rows) {
      var w = 0.0;
      var h = defaultRowHeight;
      for (final item in r) {
        w += item.width;
        h = math.max(h, item.height);
      }
      maxWidth = math.max(maxWidth, w);
      // `.lyricDuetLine { text-align: right }`
      var x = isDuet ? contentWidth - w : 0.0;
      for (final item in r) {
        final word = item.word;
        if (word != null) {
          word.x = x;
          // inline 基线对齐：同一行里矮的盒子贴底
          word.y = y + (h - word.height);
        }
        x += item.width;
      }
      y += h;
    }

    return Size(maxWidth, rows.isEmpty ? 0 : y);
  }
}
