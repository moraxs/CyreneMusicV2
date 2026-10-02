import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_miuix/miuix.dart';

import '../../infrastructure/services/developer_mode_service.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';

/// 运行日志查看页：等宽小字号逐行展示，支持复制全部与清空。
///
/// 入口在关于页，不依赖开发者模式——日志采集本就一直开着（main() 挂接的
/// debugPrint 钩子），遇到问题时让用户复制整页发过来即可。
class RuntimeLogPage extends StatelessWidget {
  const RuntimeLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final developer = DeveloperModeService.instance;
    final theme = MiuixTheme.of(context);
    return CyrenePage(
      title: '运行日志',
      largeTitle: false,
      actions: [
        MiuixIconButton(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: developer.logs.join('\n')),
            );
            CyreneToast.show('日志已复制到剪贴板');
          },
          child: MiuixIcon(
            vector: MiuixIcons.extended.byName('copy')!,
            size: 20,
          ),
        ),
        MiuixIconButton(
          onPressed: () {
            developer.clearLogs();
            CyreneToast.show('日志已清空');
          },
          child: MiuixIcon(
            vector: MiuixIcons.extended.byName('delete')!,
            size: 20,
            tint: theme.colors.error,
          ),
        ),
      ],
      body: ValueListenableBuilder<int>(
        valueListenable: developer.logRevision,
        builder: (context, _, _) {
          final logs = developer.logs;
          if (logs.isEmpty) {
            return CyreneEmptyState(
              vector: MiuixIcons.extended.byName('notes')!,
              title: '暂无日志',
              description: '应用内的 debugPrint 输出会实时收集到这里。',
            );
          }
          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            itemCount: logs.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText(
                logs[index],
                style: theme.textStyles.footnote1.copyWith(
                  color: theme.colors.onSurfaceContainer,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
