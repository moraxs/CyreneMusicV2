import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../compat/playback_mode_service.dart';

/// 播放顺序设置区域：顺序 / 单曲循环 / 随机。
///
/// 数据源 [PlaybackModeService]（Listenable）。
class PlaybackModeSection extends StatelessWidget {
  const PlaybackModeSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PlaybackModeService(),
      builder: (context, _) {
        final modeService = PlaybackModeService();
        final currentMode = modeService.currentMode;
        final index = _getModeIndex(currentMode);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MiuixSmallTitle('播放顺序', insideMargin: EdgeInsets.zero),
            const SizedBox(height: 4),
            MiuixTabRowWithContour(
              tabs: const ['顺序', '单曲循环', '随机'],
              selectedTabIndex: index,
              onTabSelected: (i) => modeService.setMode(_modeByIndex(i)),
            ),
          ],
        );
      },
    );
  }

  int _getModeIndex(PlaybackMode mode) => switch (mode) {
        PlaybackMode.sequential => 0,
        PlaybackMode.repeatOne => 1,
        PlaybackMode.shuffle => 2,
      };

  PlaybackMode _modeByIndex(int i) => switch (i) {
        0 => PlaybackMode.sequential,
        1 => PlaybackMode.repeatOne,
        _ => PlaybackMode.shuffle,
      };
}
