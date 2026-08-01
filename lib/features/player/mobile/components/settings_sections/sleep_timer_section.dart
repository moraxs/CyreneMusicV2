import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../../../../presentation/cyrene/cyrene_page.dart';
import '../../../../../presentation/cyrene/cyrene_toast.dart';
import '../../compat/sleep_timer_service.dart';
import '../mobile_player_dialogs.dart';

/// 睡眠定时器设置区域：预设时长 / 自定义，运行中可延长或取消。
///
/// 数据源 [SleepTimerService]（Listenable）。
class SleepTimerSection extends StatelessWidget {
  const SleepTimerSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SleepTimerService(),
      builder: (context, _) {
        final timer = SleepTimerService();
        final isActive = timer.isActive;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MiuixSmallTitle('睡眠定时器', insideMargin: EdgeInsets.zero),
            const SizedBox(height: 4),
            if (isActive) ...[
                CyreneInlineAlert(
                  icon: Icons.bedtime_outlined,
                  title: '正在倒计时',
                  description: '${timer.remainingTimeString} 后停止播放',
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: MiuixButton(
                        onPressed: () {
                          timer.extend(15);
                          CyreneToast.show('已延长 15 分钟');
                        },
                        child: MiuixText(
                          '+15 分钟',
                          style: MiuixTheme.of(context).textStyles.button,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MiuixButton(
                        onPressed: () {
                          timer.cancel();
                          CyreneToast.show('定时器已取消');
                        },
                        colors: MiuixButtonColors(
                          color: MiuixTheme.of(context).colors.error,
                          disabledColor:
                              MiuixTheme.of(context).colors.errorContainer,
                          contentColor:
                              MiuixTheme.of(context).colors.onError,
                          disabledContentColor:
                              MiuixTheme.of(context).colors.onErrorContainer,
                        ),
                        child: MiuixText(
                          '取消',
                          style: MiuixTheme.of(context).textStyles.button,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else
                CyreneMenuGroup(
                  children: [
                    for (final minutes in const [15, 30, 45, 60, 90])
                      CyreneMenuRow(
                        icon: Icons.timer_outlined,
                        title: '$minutes 分钟',
                        onTap: () {
                          timer.setTimerByDuration(minutes);
                          CyreneToast.show('定时器已设置：$minutes 分钟后停止播放');
                        },
                      ),
                    CyreneMenuRow(
                      icon: Icons.edit_calendar_rounded,
                      title: '自定义',
                      onTap: () => MobilePlayerDialogs.showSleepTimer(context),
                    ),
                  ],
                ),
            ],
          );
      },
    );
  }
}
