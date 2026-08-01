import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../../../domain/models/track.dart';
import '../../../../presentation/cyrene/cyrene_overlays.dart';
import '../compat/wiki_services.dart';
import 'settings_sections/settings_sections.dart';

/// 移动端全屏播放器「更多」设置底部面板。
///
/// Miuix 底部抽屉（[showCyreneSheet] → [MiuixOverlayBottomSheet]）+ Miuix 偏好组件，
/// 跟随系统明暗主题。各区域以独立 section 组件呈现，由各自对应的 compat 服务驱动。
class MobilePlayerSettingsSheet extends StatelessWidget {
  final Track? currentTrack;

  const MobilePlayerSettingsSheet({
    super.key,
    this.currentTrack,
  });

  /// 显示设置底部面板。
  static void show(BuildContext context, {Track? currentTrack}) {
    showCyreneSheet<void>(
      context: context,
      title: '播放器设置',
      // 设置面板内容较密集，收紧 sheet 内边距，让各分组贴边显示。
      insideMargin: 16,
      builder: (context, dismiss) =>
          MobilePlayerSettingsSheet(currentTrack: currentTrack),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSponsor = AuthService().currentUser?.isSponsor ?? false;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: ListView(
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        // 水平内边距由 sheet 的 insideMargin(16) 提供，这里不再重复加。
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
        children: [
          RepaintBoundary(child: PlaybackModeSection()),
          const SizedBox(height: 24),
          // 播放器样式入口已隐藏：目前仅保留「流体云」一种样式，
          // 单一选项无意义，整段注释以备未来恢复多样式时取消注释。
          // RepaintBoundary(child: PlayerStyleSection()),
          // const SizedBox(height: 24),
          if (isSponsor) ...[
            RepaintBoundary(child: EqualizerSection()),
            const SizedBox(height: 24),
          ],
          RepaintBoundary(child: LyricDetailSection()),
          const SizedBox(height: 24),
          RepaintBoundary(child: BackgroundSection()),
          const SizedBox(height: 24),
          RepaintBoundary(child: InteractionSection()),
          const SizedBox(height: 24),
          RepaintBoundary(child: SleepTimerSection()),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
