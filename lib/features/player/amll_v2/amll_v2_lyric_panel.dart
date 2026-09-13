/// AMLL v2 歌词面板：接入项目的播放服务与样式服务。
///
/// 构造参数与 `AmllLyricPanel` / `MobilePlayerFluidCloudLyricsPanel` 保持一致，
/// 可在样式分发点直接替换。
///
/// 与 v1（`../amll/`）的关系：v1 是照着 tauri 宿主的用法移植的一版，参数被宿主
/// 改过（关模糊、渐变宽度 1.0、字号跟随用户设置）；v2 是对着
/// `demo/applemusic-like-lyrics` 源码逐条复刻，默认值一律取样式表与
/// `base.ts` 的原始默认，不做宿主侧调整。两份并存，v1 保留不动。
library;

import 'package:flutter/material.dart';

import '../mobile/compat/lyric_font_service.dart';
import '../mobile/compat/lyric_line.dart';
import '../mobile/compat/lyric_style_service.dart';
import '../mobile/compat/player_service.dart';
import 'amll_v2_adapter.dart';
import 'amll_v2_lyric_view.dart';
import 'core/interfaces.dart';

class AmllV2LyricPanel extends StatefulWidget {
  const AmllV2LyricPanel({
    super.key,
    required this.lyrics,
    required this.showTranslation,
    this.visibleLineCount = 7,
    this.onTapBlank,
    this.baseColor = Colors.white,
  });

  final List<LyricLine> lyrics;
  final bool showTranslation;

  /// 期望可见的行数（与旧面板参数保持一致）。v2 的字号按样式表推导，
  /// 这个值只在用户显式调过歌词字号时参与上限保护。
  final int visibleLineCount;

  /// 点击非歌词区域
  final VoidCallback? onTapBlank;

  final Color baseColor;

  @override
  State<AmllV2LyricPanel> createState() => _AmllV2LyricPanelState();
}

class _AmllV2LyricPanelState extends State<AmllV2LyricPanel> {
  List<V2LyricLine> _converted = const [];
  int _sourceHash = 0;
  bool _lastShowTranslation = true;

  @override
  void initState() {
    super.initState();
    _convert();
  }

  @override
  void didUpdateWidget(AmllV2LyricPanel oldWidget) {
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
    _converted = toV2LyricLines(
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

        // `setAlignPosition` 的默认值是 0.35（base.ts）；本项目的「顶部对齐」
        // 沿用旧面板的 0.15。
        final alignPosition =
            styleService.currentAlignment == LyricAlignment.center
            ? 0.35
            : 0.15;

        return AmllV2LyricView(
          lines: _converted,
          positionListenable: player.positionNotifier,
          isPlaying: player.isPlaying,
          fontFamily: LyricFontService().currentFontFamily,
          color: widget.baseColor,
          alignPosition: alignPosition,
          // 以下全部是 base.ts 的默认值
          wordFadeWidth: 0.5,
          enableBlur: true,
          enableScale: true,
          enableSpring: true,
          hidePassedLines: false,
          overscanPx: 300,
          onSeek: player.seek,
          onTapBlank: widget.onTapBlank,
        );
      },
    );
  }
}
