import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../infrastructure/services/developer_mode_service.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';

/// 开发者选项（对应原版 developer_page.dart 在移动端有意义的核心子集：
/// 性能叠加层开关 + 运行日志；另补充显示模式信息用于核对高刷是否生效）。
/// 入口仅在开发者模式开启时出现在设置主页。
class DeveloperOptionsPage extends StatefulWidget {
  const DeveloperOptionsPage({super.key});

  @override
  State<DeveloperOptionsPage> createState() => _DeveloperOptionsPageState();
}

class _DeveloperOptionsPageState extends State<DeveloperOptionsPage> {
  static const _iconBlue = Color(0xFF3482FF);
  static const _iconGreen = Color(0xFF3CC756);
  static const _iconOrange = Color(0xFFFF9F0A);

  final _developer = DeveloperModeService.instance;
  String _displayModeText = '读取中…';

  @override
  void initState() {
    super.initState();
    _loadDisplayMode();
  }

  Future<void> _loadDisplayMode() async {
    if (!Platform.isAndroid) {
      setState(() => _displayModeText = '仅 Android 可用');
      return;
    }
    try {
      final active = await FlutterDisplayMode.active;
      final supported = await FlutterDisplayMode.supported;
      final best = supported.fold<int>(
        0,
        (max, mode) => mode.refreshRate > max ? mode.refreshRate.round() : max,
      );
      if (!mounted) return;
      setState(() {
        _displayModeText =
            '${active.width}x${active.height} @${active.refreshRate.round()}Hz'
            '（设备最高 ${best}Hz）';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _displayModeText = '读取失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) => CyrenePage(
    title: '开发者选项',
    bodyBuilder: (context, topPadding) => ListenableBuilder(
      listenable: _developer,
      builder: (context, _) => ListView(
        physics: const BouncingScrollPhysics(),
        padding: topPadding + const EdgeInsets.fromLTRB(12, 4, 12, 40),
        children: [
          const MiuixSmallTitle(
            '调试',
            insideMargin: EdgeInsets.fromLTRB(16, 8, 16, 8),
          ),
          CyreneMenuGroup(
            children: [
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('stopwatch')!,
                iconBackground: _iconGreen,
                title: '性能叠加层',
                subtitle: '在应用上方显示 UI/Raster 线程帧耗时图表',
                trailing: MiuixSwitch(
                  value: _developer.showPerformanceOverlay,
                  onChanged: _developer.setShowPerformanceOverlay,
                ),
                onTap: () => _developer.setShowPerformanceOverlay(
                  !_developer.showPerformanceOverlay,
                ),
              ),
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('screenMirroring')!,
                iconBackground: _iconBlue,
                title: '显示模式',
                subtitle: _displayModeText,
                trailing: const SizedBox.shrink(),
                onTap: _loadDisplayMode,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const MiuixSmallTitle(
            '日志',
            insideMargin: EdgeInsets.fromLTRB(16, 8, 16, 8),
          ),
          CyreneMenuGroup(
            children: [
              ValueListenableBuilder<int>(
                valueListenable: _developer.logRevision,
                builder: (context, _, _) => CyreneMenuRow(
                  vector: MiuixIcons.extended.byName('notes')!,
                  iconBackground: _iconOrange,
                  title: '运行日志',
                  subtitle: '应用内 debugPrint 输出（上限 1000 条）',
                  value: '${_developer.logs.length} 条',
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => const _DeveloperLogPage(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CyreneMenuGroup(
            children: [
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('back')!,
                title: '退出开发者模式',
                destructive: true,
                trailing: const SizedBox.shrink(),
                onTap: () => _confirmExit(context),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _confirmExit(BuildContext context) async {
    final confirmed = await showCyreneDialog<bool>(
      context: context,
      title: '退出开发者模式？',
      summary: '性能叠加层将一并关闭；可随时连点版本号重新开启。',
      builder: (dialogContext, dismiss) {
        final theme = MiuixTheme.of(dialogContext);
        final colors = theme.colors;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                MiuixTextButton('取消', onPressed: () => dismiss(false)),
                const SizedBox(width: 10),
                MiuixButton(
                  onPressed: () => dismiss(true),
                  colors: MiuixButtonColors(
                    color: colors.error,
                    disabledColor: colors.disabledPrimaryButton,
                    contentColor: colors.onError,
                    disabledContentColor: colors.disabledOnPrimaryButton,
                  ),
                  child: MiuixText('退出', style: theme.textStyles.button),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await _developer.disableDeveloperMode();
    if (context.mounted) Navigator.of(context).pop();
  }
}

/// 运行日志查看页：等宽小字号逐行展示，支持复制全部与清空。
class _DeveloperLogPage extends StatelessWidget {
  const _DeveloperLogPage();

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
