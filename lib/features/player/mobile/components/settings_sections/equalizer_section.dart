import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../../../../infrastructure/audio/equalizer_service.dart';
import '../../../../../presentation/cyrene/cyrene_page.dart';
import '../../../../settings/equalizer_page.dart';

/// 音效区域：均衡器入口行。
///
/// 点击先收起设置面板（走 Miuix 退场动画），再进入均衡器页。
/// 赞助闸门在父外壳（仅赞助用户显示整段）。
class EqualizerSection extends StatelessWidget {
  const EqualizerSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: EqualizerService.instance,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MiuixSmallTitle('音效', insideMargin: EdgeInsets.zero),
            const SizedBox(height: 4),
            CyreneMenuGroup(
              children: [
                CyreneMenuRow(
                  icon: Icons.graphic_eq,
                  iconBackground: const Color(0xFF34C759),
                  title: '均衡器',
                  subtitle: '自定义音频频率响应',
                  value: EqualizerService.instance.enabled ? '已开启' : '已关闭',
                  onTap: () {
                    // 与原版一致：先收起设置面板，再进入均衡器页。
                    // showCyreneSheet 的 PopScope 会把 pop 路由到 Miuix 退场动画。
                    Navigator.pop(context);
                    Navigator.of(context, rootNavigator: true).push(
                      CupertinoPageRoute<void>(
                        builder: (_) => const EqualizerPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
