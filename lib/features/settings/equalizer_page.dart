import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../infrastructure/audio/equalizer_service.dart';
import '../../presentation/cyrene/cyrene_page.dart';

/// 均衡器设置页（对应原版 equalizer_page.dart 的移动端 Material 版）。
///
/// 预设表、频段、±12dB 范围与文案照抄原版；UI 重排为 HyperOS 风格
/// （灰底白卡 + Miuix 控件），推子仍是原版的"竖排 10 列"布局。
class EqualizerPage extends StatefulWidget {
  const EqualizerPage({super.key});

  @override
  State<EqualizerPage> createState() => _EqualizerPageState();
}

class _EqualizerPageState extends State<EqualizerPage> {
  /// 内置预设（与原版完全一致），数组顺序对应 31Hz → 16kHz。
  static const Map<String, List<double>> _presets = {
    '默认': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    '流行 (Pop)': [4, 2, 0, -2, -4, -4, -2, 0, 2, 4],
    '摇滚 (Rock)': [5, 3, 1, 0, -1, 0, 1, 3, 5, 6],
    '爵士 (Jazz)': [3, 2, 0, 2, 2, 2, 0, 2, 4, 5],
    '古典 (Classical)': [5, 3, 2, 0, -1, 0, 2, 4, 5, 6],
    '低音增强 (Bass)': [7, 5, 3, 1, 0, 0, 0, 0, 0, 0],
    '人声 (Vocal)': [-2, -2, -1, 0, 3, 5, 4, 2, 0, -1],
    '舞曲 (Dance)': [6, 4, 2, 0, 0, 0, 2, 4, 4, 4],
    'R&B': [3, 7, 3, -2, -3, -2, 2, 4, 5, 6],
    '电子 (Electronic)': [6, 4, 0, -2, -4, -2, 0, 2, 4, 6],
    '嘻哈 (Hip-Hop)': [5, 3, 0, -1, -1, -1, 0, 2, 4, 5],
    '原声 (Acoustic)': [3, 2, 1, 1, 1, 1, 2, 3, 3, 4],
    '钢琴 (Piano)': [2, 1, 0, 2, 3, 2, 1, 2, 4, 5],
    '高音增强 (Treble Boost)': [0, 0, 0, 0, 0, 1, 3, 5, 6, 8],
    '耳机 (Headphone)': [3, 5, 4, 1, 1, 1, 3, 5, 4, 2],
  };

  final _equalizer = EqualizerService.instance;

  @override
  void initState() {
    super.initState();
    // 未绑定播放器时（如 preview）也要能查看/编辑已保存的设置。
    _equalizer.ensureLoaded();
  }

  /// 与原版一致：每段增益与预设差值都在 0.1 内即视为命中该预设。
  String? _currentPresetName(List<double> gains) {
    for (final entry in _presets.entries) {
      var matched = true;
      for (var i = 0; i < gains.length; i++) {
        if ((gains[i] - entry.value[i]).abs() > 0.1) {
          matched = false;
          break;
        }
      }
      if (matched) return entry.key;
    }
    return null;
  }

  static String _frequencyLabel(int frequency) =>
      frequency >= 1000 ? '${frequency ~/ 1000}k' : '$frequency';

  static String _gainLabel(double gain) =>
      '${gain > 0 ? '+' : ''}${gain.toStringAsFixed(1)}';

  @override
  Widget build(BuildContext context) => CyrenePage(
    title: '均衡器',
    bodyBuilder: (context, topPadding) => ListenableBuilder(
      listenable: _equalizer,
      builder: (context, _) {
        final theme = MiuixTheme.of(context);
        final enabled = _equalizer.enabled;
        final gains = _equalizer.gains;
        final currentPreset = _currentPresetName(gains);
        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: topPadding + const EdgeInsets.fromLTRB(12, 4, 12, 40),
          children: [
            CyreneMenuGroup(
              children: [
                CyreneMenuRow(
                  vector: MiuixIcons.extended.byName('tune')!,
                  iconBackground: const Color(0xFF3CC756),
                  title: '启用均衡器',
                  subtitle: '关闭后恢复原始音频输出',
                  trailing: MiuixSwitch(
                    value: enabled,
                    onChanged: (value) => _equalizer.setEnabled(value),
                  ),
                  onTap: () => _equalizer.setEnabled(!enabled),
                ),
              ],
            ),
            const SizedBox(height: 12),
            CyreneInlineAlert(
              vector: MiuixIcons.extended.byName('info')!,
              description: '均衡器目前仅支持mp3格式，暂时不支持无损音质和Hi-Res音质',
            ),
            const SizedBox(height: 8),
            // 与原版一致：未启用时预设与推子整体变灰且不可交互。
            Opacity(
              opacity: enabled ? 1.0 : 0.4,
              child: AbsorbPointer(
                absorbing: !enabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const MiuixSmallTitle(
                      '预设',
                      insideMargin: EdgeInsets.fromLTRB(16, 8, 16, 8),
                    ),
                    SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        itemCount: _presets.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final name = _presets.keys.elementAt(index);
                          final selected = name == currentPreset;
                          return MiuixButton(
                            onPressed: () =>
                                _equalizer.updateGains(_presets[name]!),
                            colors: selected
                                ? MiuixButtonDefaults.buttonColorsPrimary(
                                    context,
                                  )
                                : null,
                            child: MiuixText(
                              name,
                              style: theme.textStyles.button,
                            ),
                          );
                        },
                      ),
                    ),
                    const MiuixSmallTitle(
                      '频段增益 (dB)',
                      insideMargin: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    ),
                    MiuixCard(
                      cornerRadius: 20,
                      insideMargin: const EdgeInsets.fromLTRB(10, 18, 10, 14),
                      child: SizedBox(
                        height: 300,
                        child: Row(
                          children: [
                            for (
                              var i = 0;
                              i < EqualizerService.frequencies.length;
                              i++
                            )
                              Expanded(child: _buildBand(theme, gains, i)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: Text(
                        '提示：调节过大可能会导致失真',
                        style: theme.textStyles.footnote1.copyWith(
                          color: theme.colors.onSurfaceVariantSummary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _buildBand(MiuixThemeData theme, List<double> gains, int index) {
    final gain = gains[index];
    return Column(
      children: [
        Text(
          _gainLabel(gain),
          style: theme.textStyles.footnote2.copyWith(
            color: theme.colors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          // RotatedBox 连同手势坐标一起旋转，把水平 MiuixSlider 立起来用。
          child: RotatedBox(
            quarterTurns: 3,
            child: MiuixSlider(
              value: gain,
              min: -EqualizerService.maxGainDb,
              max: EqualizerService.maxGainDb,
              height: 22,
              onValueChanged: (value) {
                final next = List.of(gains);
                next[index] = value;
                _equalizer.updateGains(next);
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _frequencyLabel(EqualizerService.frequencies[index]),
          style: theme.textStyles.footnote2.copyWith(
            color: theme.colors.onSurfaceVariantSummary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
