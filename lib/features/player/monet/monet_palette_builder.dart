import 'dart:async';

import 'package:flutter/widgets.dart';

import '../mobile/compat/color_extraction_service.dart';
import '../mobile/compat/player_service.dart';
import 'monet_palette.dart';

/// 按当前曲目封面解出 [MonetPalette]，**与播放器背景类型无关**。
///
/// 不能直接读 `PlayerService().themeColorNotifier`：那个值只有在「播放器背景 =
/// 自适应」时才由 `MobilePlayerBackground` 写入，而桌面端的默认背景是「动态」，
/// 于是歌名、泛光、花瓣会永远停在兜底的冷灰蓝上——看起来就像莫奈布局没接上封面色。
///
/// 这里自己走一遍 [ColorExtractionService]。它按 URL 缓存且在 isolate 里解码，
/// 自适应背景已经提过色时直接命中缓存，不会重复解一遍图。
class MonetPaletteBuilder extends StatefulWidget {
  const MonetPaletteBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, MonetPalette palette) builder;

  @override
  State<MonetPaletteBuilder> createState() => _MonetPaletteBuilderState();
}

class _MonetPaletteBuilderState extends State<MonetPaletteBuilder> {
  MonetPalette _palette = MonetPalette.fallback;
  String? _requestedUrl;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    PlayerService().addListener(_onPlayerChanged);
    _resolve();
  }

  @override
  void dispose() {
    PlayerService().removeListener(_onPlayerChanged);
    super.dispose();
  }

  void _onPlayerChanged() {
    if (mounted) _resolve();
  }

  void _resolve() {
    final player = PlayerService();
    final url = player.currentSong?.pic ?? player.currentTrack?.picUrl ?? '';
    if (url == _requestedUrl) return;
    _requestedUrl = url;
    _requestId++;

    if (url.isEmpty) {
      _apply(null);
      return;
    }

    final cached = ColorExtractionService().getCachedColors(url);
    if (cached != null) {
      _apply(cached.themeColor);
      return;
    }

    unawaited(_extract(url, _requestId));
  }

  Future<void> _extract(String url, int requestId) async {
    try {
      final result = await ColorExtractionService().extractColorsFromUrl(
        url,
        sampleSize: 64,
        timeout: const Duration(seconds: 3),
      );
      if (!mounted || requestId != _requestId) return;
      _apply(result?.themeColor);
    } catch (_) {
      // 提色失败就保留上一版调色板：闪回兜底色比停在旧封面的颜色更难看。
    }
  }

  void _apply(Color? themeColor) {
    final next = MonetPalette.fromThemeColor(themeColor);
    if (next == _palette) return;
    setState(() => _palette = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _palette);
}
