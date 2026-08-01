import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../compat/auto_collapse_service.dart';

/// 沉浸模式开关：自动隐藏控制按钮，点击屏幕呼出。
///
/// 数据源 [AutoCollapseService]（移动端播放器专属，与全屏播放器的
/// `FullscreenSettingsStore.isImmersiveMode` 是不同播放器的不同设置）。
class InteractionSection extends StatelessWidget {
  const InteractionSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AutoCollapseService(),
      builder: (context, _) {
        final service = AutoCollapseService();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MiuixSmallTitle(
              '交互',
              insideMargin: EdgeInsets.zero,
            ),
            const SizedBox(height: 4),
            MiuixSwitchPreference(
              title: '沉浸模式',
              summary: '自动隐藏控制按钮，点击屏幕呼出',
              value: service.isAutoCollapseEnabled,
              onChanged: service.setAutoCollapseEnabled,
            ),
          ],
        );
      },
    );
  }
}
