import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../compat/lyric_style_service.dart';

/// 播放器样式设置区域：流体云 / Apple Music / 经典 + 歌词对齐（居中/顶部）。
///
/// 数据源 [LyricStyleService]（Listenable）。样式与对齐均用 Miuix 分段。
class PlayerStyleSection extends StatelessWidget {
  const PlayerStyleSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LyricStyleService(),
      builder: (context, _) {
        final styleService = LyricStyleService();
        final currentStyle = styleService.currentStyle;
        final styleIndex = _getStyleIndex(currentStyle);
        final alignmentIndex =
            styleService.currentAlignment == LyricAlignment.center ? 0 : 1;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MiuixSmallTitle('播放器样式', insideMargin: EdgeInsets.zero),
            const SizedBox(height: 4),
            MiuixTabRowWithContour(
              tabs: const ['流体云', 'Apple Music', '经典'],
              selectedTabIndex: styleIndex,
              onTabSelected: (i) =>
                  styleService.setStyle(_styleByIndex(i)),
            ),
            const SizedBox(height: 18),
            const MiuixSmallTitle('歌词对齐', insideMargin: EdgeInsets.zero),
            const SizedBox(height: 8),
            MiuixTabRowWithContour(
              tabs: const ['居中显示', '顶部显示'],
              selectedTabIndex: alignmentIndex,
              onTabSelected: (i) => styleService.setAlignment(
                i == 0 ? LyricAlignment.center : LyricAlignment.top,
              ),
            ),
          ],
        );
      },
    );
  }

  int _getStyleIndex(LyricStyle style) => switch (style) {
        LyricStyle.fluidCloud => 0,
        LyricStyle.amll => 1,
        LyricStyle.defaultStyle => 2,
        LyricStyle.immersive => 0, // 未在选项中，回退到首项
      };

  LyricStyle _styleByIndex(int i) => switch (i) {
        0 => LyricStyle.fluidCloud,
        1 => LyricStyle.amll,
        _ => LyricStyle.defaultStyle,
      };
}
