/// AMLL 歌词面板：接入项目的播放服务与样式服务。
///
/// 构造参数与 `MobilePlayerFluidCloudLyricsPanel` 保持一致，
/// 便于在样式分发点直接替换。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../mobile/compat/lyric_font_service.dart';
import '../mobile/compat/lyric_line.dart';
import '../mobile/compat/lyric_style_service.dart';
import '../mobile/compat/player_service.dart';
import 'amll_adapter.dart';
import 'amll_lyric_view.dart';
import 'core/lyric_types.dart';

class AmllLyricPanel extends StatefulWidget {
  const AmllLyricPanel({
    super.key,
    required this.lyrics,
    required this.showTranslation,
    this.visibleLineCount = 7,
    this.onTapBlank,
    this.baseColor = Colors.white,
  });

  final List<LyricLine> lyrics;
  final bool showTranslation;

  /// 期望可见的行数，用于推导字号（与旧面板参数保持一致）
  final int visibleLineCount;

  /// 点击非歌词区域
  final VoidCallback? onTapBlank;

  final Color baseColor;

  @override
  State<AmllLyricPanel> createState() => _AmllLyricPanelState();
}

class _AmllLyricPanelState extends State<AmllLyricPanel> {
  List<AmllLyricLine> _converted = const [];
  int _sourceHash = 0;
  bool _lastShowTranslation = true;

  @override
  void initState() {
    super.initState();
    _convert();
  }

  @override
  void didUpdateWidget(AmllLyricPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lyrics, widget.lyrics) ||
        oldWidget.showTranslation != widget.showTranslation) {
      _convert();
    }
  }

  /// 转换歌词，并按内容哈希避免重复构建（宿主每帧重建 widget 时很常见）。
  void _convert() {
    final hash = Object.hashAll(<Object?>[
      widget.lyrics.length,
      if (widget.lyrics.isNotEmpty) widget.lyrics.first.startTime,
      if (widget.lyrics.isNotEmpty) widget.lyrics.first.text,
      if (widget.lyrics.isNotEmpty) widget.lyrics.last.startTime,
      if (widget.lyrics.isNotEmpty) widget.lyrics.last.text,
    ]);

    if (hash == _sourceHash &&
        _lastShowTranslation == widget.showTranslation &&
        _converted.isNotEmpty) {
      return;
    }

    _sourceHash = hash;
    _lastShowTranslation = widget.showTranslation;
    _converted = toAmllLyricLines(
      widget.lyrics,
      showTranslation: widget.showTranslation,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lyrics.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(
            color: widget.baseColor.withValues(alpha: 0.54),
            fontSize: 16,
          ),
        ),
      );
    }

    final player = PlayerService();

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        LyricStyleService(),
        LyricFontService(),
        player,
      ]),
      builder: (context, _) {
        final styleService = LyricStyleService();
        final fontFamily = LyricFontService().currentFontFamily;

        // 目标行对齐位置：居中模式 0.5，顶部模式 0.15（与 tauri 端一致）
        final alignPosition =
            styleService.currentAlignment == LyricAlignment.center ? 0.5 : 0.15;

        return LayoutBuilder(
          builder: (context, constraints) {
            final textStyle = TextStyle(
              fontFamily: fontFamily,
              fontSize: _resolveFontSize(styleService, constraints),
              fontWeight: FontWeight.w700,
              height: 1.2,
              color: widget.baseColor,
            );

            return AmllLyricView(
              lines: _converted,
              positionListenable: player.positionNotifier,
              isPlaying: player.isPlaying,
              textStyle: textStyle,
              baseColor: widget.baseColor,
              alignPosition: alignPosition,
              // 与 tauri 端对齐：关闭模糊、渐变宽度 1.0
              enableBlur: false,
              wordFadeWidth: 1.0,
              showTranslation: widget.showTranslation,
              onSeek: player.seek,
              onTapBlank: widget.onTapBlank,
            );
          },
        );
      },
    );
  }

  /// 字号：优先用用户设置，并按可见行数与视口高度做一次上限保护，
  /// 避免行数要求较多时歌词溢出。
  double _resolveFontSize(
    LyricStyleService styleService,
    BoxConstraints constraints,
  ) {
    final configured = styleService.fontSize * 0.9;
    if (!constraints.hasBoundedHeight || widget.visibleLineCount <= 0) {
      return configured;
    }
    // 每行按 1.2em 行高 + 0.8em 间距估算
    final maxByViewport =
        constraints.maxHeight / widget.visibleLineCount / 2.0;
    return math.max(12.0, math.min(configured, maxByViewport));
  }
}
