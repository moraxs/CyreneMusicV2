/// 1:1 移植 `lyric-player/base.ts`（`LyricPlayerBase`）与
/// `lyric-player/dom/index.ts`（`DomLyricPlayer`）。
///
/// 与上游的唯一结构性差异：行尺寸不再靠 `ResizeObserver` 回填，而是由
/// [rebuildLayouts] 在尺寸/字号变化时用 TextPainter 同步量出来——Flutter 里
/// 没有「先渲染再回读」这一步，同步测量反而更确定。
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/interfaces.dart';
import '../core/lyric_split_words.dart' show eqSet;
import '../core/spring.dart';
import '../render/line_layout.dart';
import '../render/metrics.dart';
import 'interlude_dots.dart';
import 'lyric_line_el.dart';

/// `BottomLineEl`。本移植里底栏没有内容，只保留它对布局边界的参与。
class V2BottomLine {
  final V2Spring posX = V2Spring(0);
  final V2Spring posY = V2Spring(0);
  Size lineSize = Size.zero;
  double delay = 0;

  void setTransform(
    double left,
    double top, {
    bool force = false,
    double delay = 0,
    required bool enableSpring,
  }) {
    this.delay = delay;
    if (force || !enableSpring) {
      posX.setPosition(left);
      posY.setPosition(top);
    } else {
      posX.setTargetPosition(left, delay);
      posY.setTargetPosition(top, delay);
    }
  }

  void update(double delta) {
    posX.update(delta);
    posY.update(delta);
  }
}

class V2LyricPlayer extends ChangeNotifier {
  // ---- base.ts 的字段 ----
  int currentTime = 0;
  List<V2LyricLine> currentLyricLines = const [];
  List<V2LyricLine> processedLines = const [];
  final Set<int> hotLines = <int>{};
  final Set<int> bufferedLines = <int>{};
  bool isNonDynamic = false;
  bool hasDuetLine = false;
  int scrollToIndex = 0;
  bool disableSpring = false;
  final V2InterludeDots interludeDots = V2InterludeDots();
  final V2BottomLine bottomLine = V2BottomLine();
  bool enableBlur = true;
  bool enableScale = true;
  bool hidePassedLines = false;
  final List<double> scrollBoundary = <double>[0, 0];
  List<V2LyricLineEl> currentLyricLineObjects = <V2LyricLineEl>[];
  bool isSeeking = false;
  int lastCurrentTime = 0;

  /// `"top" | "bottom" | "center"`
  String alignAnchor = 'center';
  double alignPosition = 0.35;
  double scrollOffset = 0;
  Size size = Size.zero;
  bool allowScroll = true;
  bool isPageVisible = true;
  bool initialLayoutFinished = false;
  double overscanPx = 300;
  double wordFadeWidth = 0.5;
  int targetAlignIndex = 0;
  bool isPlaying = true;

  V2SpringParams posYSpringParams = const V2SpringParams(
    mass: 0.9,
    damping: 15,
    stiffness: 90,
  );
  V2SpringParams scaleSpringParams = const V2SpringParams(
    mass: 2,
    damping: 25,
    stiffness: 100,
  );
  V2SpringParams scaleForBGSpringParams = const V2SpringParams(
    mass: 1,
    damping: 20,
    stiffness: 50,
  );

  /// 当前用于排版的 CSS 度量
  V2CssMetrics? metrics;

  bool isScrolled = false;
  double _scrolledCountdown = 0;

  /// `window.innerWidth`，`setTransform` 里决定模糊是否打折
  double windowWidth = 0;
  double windowHeight = 0;

  // ------------------------------------------------------------ setters

  void setWordFadeWidth([double value = 0.5]) {
    final v = math.max(0.0001, value);
    if (v == wordFadeWidth) return;
    wordFadeWidth = v;
    // DomLyricPlayer.setWordFadeWidth → 每行 updateMaskImageSync()
    _needsLayoutRebuild = true;
  }

  void setEnableScale([bool enable = true]) {
    if (enableScale == enable) return;
    enableScale = enable;
    calcLayout();
  }

  void setEnableBlur(bool enable) {
    if (enableBlur == enable) return;
    enableBlur = enable;
    calcLayout();
  }

  void setHidePassedLines(bool hide) {
    if (hidePassedLines == hide) return;
    hidePassedLines = hide;
    calcLayout();
  }

  void setAlignAnchor(String anchor) => alignAnchor = anchor;
  void setAlignPosition(double v) => alignPosition = v;
  void setOverscanPx(double px) => overscanPx = math.max(0, px);
  void setIsSeeking(bool v) => isSeeking = v;

  void setEnableSpring([bool enable = true]) {
    if (disableSpring == !enable) return;
    disableSpring = !enable;
    calcLayout(true);
  }

  bool getEnableSpring() => !disableSpring;

  // ------------------------------------------------------------ 滚动

  /// `beginScrollHandler`
  bool beginScrollHandler() {
    final allowed = allowScroll;
    if (allowed) {
      isScrolled = true;
      _scrolledCountdown = 5000;
    }
    return allowed;
  }

  void limitScrollOffset() {
    scrollOffset = math.max(
      math.min(scrollBoundary[1], scrollOffset),
      scrollBoundary[0],
    );
  }

  void resetScroll() {
    isScrolled = false;
    scrollOffset = 0;
    _scrolledCountdown = 0;
  }

  // ------------------------------------------------------------ 间奏

  /// `getCurrentInterlude`
  /// 返回 `[开始时间, 结束时间, 大概处于的歌词行ID, 下一句是否为对唱歌词(0/1)]`
  List<int>? getCurrentInterlude() {
    if (bufferedLines.isNotEmpty) return null;
    final ct = currentTime + 20;
    final i = scrollToIndex;
    V2LyricLine? at(int idx) =>
        idx >= 0 && idx < processedLines.length ? processedLines[idx] : null;

    if (i == 0) {
      final l0 = at(0);
      if (l0 != null && l0.startTime != 0) {
        if (l0.startTime > ct) {
          return [ct, math.max(ct, l0.startTime - 250), -2, l0.isDuet ? 1 : 0];
        }
        final l1 = at(1);
        if (l1 != null && l1.startTime > ct && l0.endTime < ct) {
          return [math.max(l0.endTime, ct), l1.startTime, 0, l1.isDuet ? 1 : 0];
        }
      }
    } else {
      final li = at(i);
      final li1 = at(i + 1);
      if (li != null && li1 != null) {
        if (li1.startTime > ct && li.endTime < ct) {
          return [
            math.max(li.endTime, ct),
            li1.startTime,
            i,
            li1.isDuet ? 1 : 0,
          ];
        }
        final li2 = at(i + 2);
        if (li2 != null && li2.startTime > ct && li1.endTime < ct) {
          return [
            math.max(li1.endTime, ct),
            li2.startTime,
            i + 1,
            li2.isDuet ? 1 : 0,
          ];
        }
      }
    }
    return null;
  }

  // ------------------------------------------------------------ 歌词

  bool _needsLayoutRebuild = false;

  /// `setLyricLines`
  void setLyricLines(List<V2LyricLine> lines, [int initialTime = 0]) {
    initialLayoutFinished = true;
    for (final line in lines) {
      for (final word in line.words) {
        word.word = word.word.replaceAll(RegExp(r'\s+'), ' ');
      }
    }
    lastCurrentTime = initialTime;
    currentTime = initialTime;
    currentLyricLines = lines.map((l) => l.clone()).toList();
    processedLines = lines.map((l) => l.clone()).toList();

    isNonDynamic = true;
    for (final line in processedLines) {
      if (line.words.length > 1) {
        isNonDynamic = false;
        break;
      }
    }

    hasDuetLine = processedLines.any((line) => line.isDuet);

    // 将行开始时间提早最多一秒
    for (var i = processedLines.length - 1; i >= 0; i--) {
      final line = processedLines[i];
      if (line.isBG) continue;
      final prevLine = i - 1 >= 0 ? processedLines[i - 1] : null;
      if (prevLine != null) {
        line.startTime = math.max(
          math.min(prevLine.endTime, line.startTime),
          line.startTime - 1000,
        );
      } else {
        line.startTime = math.max(0, line.startTime - 1000);
      }
    }

    // 让背景歌词和上一行歌词一同出现并一同消失
    for (var i = processedLines.length - 1; i >= 0; i--) {
      final line = processedLines[i];
      if (line.isBG) continue;
      final nextLine = i + 1 < processedLines.length
          ? processedLines[i + 1]
          : null;
      if (nextLine != null && nextLine.isBG) {
        final voiced = nextLine.words
            .where((w) => w.word.trim().isNotEmpty)
            .toList();
        final bgStartTime = voiced
            .map((w) => w.startTime)
            .fold<int>(line.startTime, math.min);
        final bgEndTime = voiced
            .map((w) => w.endTime)
            .fold<int>(line.endTime, math.max);
        nextLine.startTime = math.min(bgStartTime, line.startTime);
        nextLine.endTime = math.max(bgEndTime, line.endTime);
      }
    }

    // DomLyricPlayer.setLyricLines：重建行对象
    currentLyricLineObjects = processedLines
        .map((line) => V2LyricLineEl(line: line, windowHeight: windowHeight))
        .toList();
    for (final obj in currentLyricLineObjects) {
      obj.posY.updateParams(posYSpringParams);
      obj.scaleSpring.updateParams(
        obj.line.isBG ? scaleForBGSpringParams : scaleSpringParams,
      );
    }
    bottomLine.posY.updateParams(posYSpringParams);

    interludeDots.setInterlude(null);
    hotLines.clear();
    bufferedLines.clear();
    _needsLayoutRebuild = true;
    setCurrentTime(0, true);
    notifyListeners();
  }

  /// 尺寸 / 字号 / 字体变化时重新排版所有行。
  void rebuildLayouts(V2CssMetrics newMetrics, {TextScaler? textScaler}) {
    metrics = newMetrics;
    size = newMetrics.playerSize;
    windowWidth = newMetrics.windowSize.width;
    windowHeight = newMetrics.windowSize.height;
    final builder = V2LineLayoutBuilder(
      metrics: newMetrics,
      isNonDynamic: isNonDynamic,
      wordFadeWidth: wordFadeWidth,
      textScaler: textScaler ?? TextScaler.noScaling,
    );
    for (final obj in currentLyricLineObjects) {
      obj.layout = builder.build(obj.line);
    }
    _needsLayoutRebuild = false;
    calcLayout(true);
  }

  bool get needsLayoutRebuild => _needsLayoutRebuild;

  /// `setCurrentTime`
  void setCurrentTime(int time, [bool isSeek = false]) {
    currentTime = time;
    if (!initialLayoutFinished && !isSeek) return;

    final removedIds = <int>{};
    final addedIds = <int>{};

    V2LyricLine? at(int idx) =>
        idx >= 0 && idx < processedLines.length ? processedLines[idx] : null;
    V2LyricLineEl? obj(int idx) =>
        idx >= 0 && idx < currentLyricLineObjects.length
        ? currentLyricLineObjects[idx]
        : null;

    for (final lastHotId in hotLines.toList()) {
      final line = at(lastHotId);
      if (line != null) {
        if (line.isBG) continue;
        final nextLine = at(lastHotId + 1);
        if (nextLine != null && nextLine.isBG) {
          final nextMainLine = at(lastHotId + 2);
          final startTime = math.min(line.startTime, nextLine.startTime);
          final endTime = math.min(
            math.max(
              line.endTime,
              nextMainLine?.startTime ?? 0x7FFFFFFFFFFFFFF,
            ),
            math.max(line.endTime, nextLine.endTime),
          );
          if (startTime > time || endTime <= time) {
            hotLines.remove(lastHotId);
            hotLines.remove(lastHotId + 1);
            if (isSeek) {
              obj(lastHotId)?.disable();
              obj(lastHotId + 1)?.disable();
            }
          }
        } else if (line.startTime > time || line.endTime <= time) {
          hotLines.remove(lastHotId);
          if (isSeek) obj(lastHotId)?.disable();
        }
      } else {
        hotLines.remove(lastHotId);
        if (isSeek) obj(lastHotId)?.disable();
      }
    }

    for (var id = 0; id < currentLyricLineObjects.length; id++) {
      final lineObj = currentLyricLineObjects[id];
      final line = lineObj.line;
      if (!line.isBG && line.startTime <= time && line.endTime > time) {
        if (!hotLines.contains(id)) {
          hotLines.add(id);
          addedIds.add(id);
          if (isSeek) lineObj.enable();
          final next = obj(id + 1);
          if (next != null && next.line.isBG) {
            hotLines.add(id + 1);
            addedIds.add(id + 1);
            if (isSeek) next.enable();
          }
        }
      }
    }

    for (final v in bufferedLines) {
      if (!hotLines.contains(v)) {
        removedIds.add(v);
        if (isSeek) obj(v)?.disable();
      }
    }

    if (isSeek) {
      if (bufferedLines.isNotEmpty) {
        scrollToIndex = bufferedLines.reduce(math.min);
      } else {
        scrollToIndex = processedLines.indexWhere(
          (line) => line.startTime >= time,
        );
      }
      bufferedLines.clear();
      bufferedLines.addAll(hotLines);
      calcLayout();
    } else if (removedIds.isNotEmpty || addedIds.isNotEmpty) {
      if (removedIds.isEmpty && addedIds.isNotEmpty) {
        for (final v in addedIds) {
          bufferedLines.add(v);
          obj(v)?.enable();
        }
        scrollToIndex = bufferedLines.reduce(math.min);
        calcLayout();
      } else if (addedIds.isEmpty && removedIds.isNotEmpty) {
        if (eqSet(removedIds, bufferedLines)) {
          for (final v in bufferedLines.toList()) {
            if (!hotLines.contains(v)) {
              bufferedLines.remove(v);
              obj(v)?.disable();
            }
          }
          calcLayout();
        }
      } else {
        for (final v in addedIds) {
          bufferedLines.add(v);
          obj(v)?.enable();
        }
        for (final v in removedIds) {
          bufferedLines.remove(v);
          obj(v)?.disable();
        }
        if (bufferedLines.isNotEmpty) {
          scrollToIndex = bufferedLines.reduce(math.min);
        }
        calcLayout();
      }
    }
    lastCurrentTime = time;
  }

  /// 间奏点当前的落点（绘制层用）
  double interludeDotsTop = 0;

  /// `calcLayout`
  void calcLayout([bool sync = false]) {
    if (currentLyricLineObjects.isEmpty) return;
    final interlude = getCurrentInterlude();
    var curPos = -scrollOffset;
    var targetAlignIndex = scrollToIndex;
    var interludeDuration = 0;
    if (interlude != null) {
      interludeDuration = interlude[1] - interlude[0];
      if (interludeDuration >= 4000) {
        final nextIdx = interlude[2] + 1;
        if (nextIdx >= 0 && nextIdx < currentLyricLineObjects.length) {
          targetAlignIndex = nextIdx;
        }
      }
    } else {
      interludeDots.setInterlude(null);
    }

    // 避免一开始就让所有歌词行挤在一起
    final lineHeightFallback = size.height / 5;
    var scrollOffsetAcc = 0.0;
    final upper = targetAlignIndex.clamp(0, currentLyricLineObjects.length);
    for (var i = 0; i < upper; i++) {
      final el = currentLyricLineObjects[i];
      scrollOffsetAcc += el.line.isBG && isPlaying
          ? 0
          : (el.layout?.size.height ?? lineHeightFallback);
    }
    scrollBoundary[0] = -scrollOffsetAcc;
    curPos -= scrollOffsetAcc;
    curPos += size.height * alignPosition;

    this.targetAlignIndex = targetAlignIndex;
    if (targetAlignIndex >= 0 &&
        targetAlignIndex < currentLyricLineObjects.length) {
      final curLine = currentLyricLineObjects[targetAlignIndex];
      final lineHeight = curLine.layout?.size.height ?? lineHeightFallback;
      switch (alignAnchor) {
        case 'bottom':
          curPos -= lineHeight;
        case 'center':
          curPos -= lineHeight / 2;
        case 'top':
          break;
      }
    }

    // `Math.max(...this.bufferedLines)`：空集合在 JS 里是 -Infinity
    final latestIndex = bufferedLines.isEmpty
        ? -0x7FFFFFFFFFFFFFF
        : bufferedLines.reduce(math.max);
    var delay = 0.0;
    var baseDelay = sync ? 0.0 : 0.05;
    var setDots = false;

    for (var i = 0; i < currentLyricLineObjects.length; i++) {
      final lineObj = currentLyricLineObjects[i];
      final hasBuffered = bufferedLines.contains(i);
      final isActive = hasBuffered || (i >= scrollToIndex && i < latestIndex);
      final line = lineObj.line;

      if (!setDots &&
          interludeDuration >= 4000 &&
          ((i == scrollToIndex && interlude?[2] == -2) ||
              i == scrollToIndex + 1)) {
        setDots = true;
        interludeDotsTop = curPos;
        interludeDots.setTransform(0, curPos);
        if (interlude != null) {
          interludeDots.setInterlude([interlude[0], interlude[1]]);
        }
        curPos += metrics?.interludeDotsSize.height ?? 0;
      }

      double targetOpacity;
      if (hidePassedLines) {
        if (i < (interlude != null ? interlude[2] + 1 : scrollToIndex) &&
            isPlaying) {
          targetOpacity = 0.00001;
        } else if (hasBuffered) {
          targetOpacity = 0.85;
        } else {
          targetOpacity = isNonDynamic ? 0.2 : 1;
        }
      } else {
        if (hasBuffered) {
          targetOpacity = 0.85;
        } else {
          targetOpacity = isNonDynamic ? 0.2 : 1;
        }
      }

      var blurLevel = 0.0;
      if (enableBlur) {
        if (isActive) {
          blurLevel = 0;
        } else {
          blurLevel = 1;
          if (i < scrollToIndex) {
            blurLevel += (scrollToIndex - i).abs() + 1;
          } else {
            blurLevel += (i - math.max(scrollToIndex, latestIndex)).abs();
          }
        }
      }

      final scaleAspect = enableScale ? 97.0 : 100.0;
      var targetScale = 100.0;
      if (!isActive && isPlaying) {
        targetScale = line.isBG ? 75.0 : scaleAspect;
      }

      lineObj.setTransform(
        top: curPos,
        scale: targetScale,
        opacity: targetOpacity,
        blur: windowWidth <= 1024 ? blurLevel * 0.8 : blurLevel,
        force: false,
        delay: delay,
        enableSpring: getEnableSpring(),
      );

      if (line.isBG && (isActive || !isPlaying)) {
        curPos += lineObj.layout?.size.height ?? lineHeightFallback;
      } else if (!line.isBG) {
        curPos += lineObj.layout?.size.height ?? lineHeightFallback;
      }

      if (curPos >= 0 && !isSeeking) {
        if (!line.isBG) delay += baseDelay;
        if (i >= scrollToIndex) baseDelay /= 1.05;
      }
    }

    scrollBoundary[1] = curPos + scrollOffset - size.height / 2;
    bottomLine.setTransform(
      0,
      curPos,
      delay: delay,
      enableSpring: getEnableSpring(),
    );
  }

  // ------------------------------------------------------------ 播放状态

  void pause() {
    interludeDots.pause();
    if (isPlaying) {
      isPlaying = false;
      calcLayout();
    }
    for (final line in currentLyricLineObjects) {
      line.pause();
    }
  }

  void resume() {
    interludeDots.resume();
    if (!isPlaying) {
      isPlaying = true;
      calcLayout();
    }
    for (final line in currentLyricLineObjects) {
      line.resume();
    }
  }

  /// 逐帧推进后触发重绘（[CustomPainter.repaint] 监听的就是本对象）。
  void repaint() => notifyListeners();

  /// `DomLyricPlayer.update(delta)`，[delta] 单位毫秒。
  void update([double delta = 0]) {
    if (!initialLayoutFinished) return;
    // LyricPlayerBase.update
    bottomLine.update(delta / 1000);
    interludeDots.update(delta / 1000);
    if (!isPageVisible) return;
    final deltaS = delta / 1000;
    interludeDots.update(delta);
    bottomLine.update(deltaS);
    for (final line in currentLyricLineObjects) {
      line.update(deltaS, enableSpring: getEnableSpring(), playing: isPlaying);
    }

    if (_scrolledCountdown > 0) {
      _scrolledCountdown -= delta;
      if (_scrolledCountdown <= 0) {
        _scrolledCountdown = 0;
        isScrolled = false;
        scrollOffset = 0;
        calcLayout(true);
      }
    }
  }
}
