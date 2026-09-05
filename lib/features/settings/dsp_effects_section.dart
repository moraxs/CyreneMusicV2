import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../infrastructure/audio/audio_filter_chain.dart';
import '../../infrastructure/audio/dsp_effects_service.dart';
import '../../presentation/cyrene/cyrene_page.dart';

/// 「音效与均衡器」页里的 DSP 音效区块。
///
/// 每个滤镜一张卡片：卡头是开关，展开后是该滤镜的全部可调参数。参数表完全由
/// [DspEffectsService.filters] 驱动，加滤镜/加参数只改服务里的 spec，这里不用动。
///
/// 仅在 [DspEffectsService.isSupported] 为真时才应插入页面——其余平台的 libmpv
/// 没编进这些滤镜。
class DspEffectsSection extends StatelessWidget {
  const DspEffectsSection({super.key});

  static const _iconTeal = Color(0xFF00B0A6);

  @override
  Widget build(BuildContext context) {
    final service = DspEffectsService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final theme = MiuixTheme.of(context);
        final enabled = service.enabled;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MiuixSmallTitle(
              'DSP 音效',
              insideMargin: EdgeInsets.fromLTRB(16, 16, 16, 8),
            ),
            CyreneMenuGroup(
              children: [
                CyreneMenuRow(
                  vector: MiuixIcons.extended.byName('volumeUp')!,
                  iconBackground: _iconTeal,
                  title: '启用 DSP 音效',
                  subtitle: '低音、声场、动态与限幅等 10 种滤镜',
                  value: enabled && service.activeCount > 0
                      ? '${service.activeCount} 项生效'
                      : null,
                  trailing: MiuixSwitch(
                    value: enabled,
                    onChanged: service.setEnabled,
                  ),
                  onTap: () => service.setEnabled(!enabled),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder(
              valueListenable: AudioFilterChain.instance.dspRejected,
              builder: (context, rejected, _) => rejected
                  ? const CyreneInlineAlert(
                      icon: Icons.error_outline_rounded,
                      destructive: true,
                      title: '当前 libmpv 不支持这些滤镜',
                      description:
                          '写入音频滤镜链失败，DSP 段已自动摘除（均衡器不受影响）。'
                          '请确认使用的是带 DSP 滤镜的 libmpv 定制构建。',
                    )
                  : const CyreneInlineAlert(
                      icon: Icons.graphic_eq_rounded,
                      description:
                          '滤镜按下方顺序串接在均衡器之后：音色 → 声场 → 调制 → 动态 → 限幅。'
                          '叠加多个增益类滤镜容易削顶，建议同时开启「限幅保护」。',
                    ),
            ),
            const SizedBox(height: 8),
            // 与均衡器一致：总开关关闭时整块变灰且不可交互。
            Opacity(
              opacity: enabled ? 1.0 : 0.4,
              child: AbsorbPointer(
                absorbing: !enabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final spec in DspEffectsService.filters) ...[
                      _FilterCard(spec: spec, service: service),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 4),
                    Center(
                      child: MiuixButton(
                        onPressed: service.resetAll,
                        insideMargin: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        child: MiuixText(
                          '全部关闭并复位',
                          style: theme.textStyles.button,
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
    );
  }
}

class _FilterCard extends StatelessWidget {
  const _FilterCard({required this.spec, required this.service});

  final DspFilterSpec spec;
  final DspEffectsService service;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final on = service.isFilterEnabled(spec.id);
    return MiuixCard(
      cornerRadius: 20,
      insideMargin: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            spec.title,
                            style: theme.textStyles.body1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // 附上 FFmpeg 滤镜名，方便对照文档调参。
                        Text(
                          spec.id,
                          style: theme.textStyles.footnote2.copyWith(
                            color: theme.colors.onSurfaceVariantSummary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      spec.subtitle,
                      style: theme.textStyles.footnote1.copyWith(
                        color: theme.colors.onSurfaceVariantSummary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              MiuixSwitch(
                value: on,
                onChanged: (value) =>
                    service.setFilterEnabled(spec.id, value),
              ),
            ],
          ),
          // 关闭的滤镜收起参数，避免十张卡片全展开后页面过长。
          if (on) ...[
            const SizedBox(height: 6),
            for (final param in spec.params)
              _ParamSlider(
                spec: spec,
                param: param,
                value: service.valueOf(spec.id, param.key),
                onChanged: (value) =>
                    service.setParam(spec.id, param.key, value),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => service.resetFilter(spec.id),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, left: 12, bottom: 2),
                  child: Text(
                    '恢复默认',
                    style: theme.textStyles.footnote1.copyWith(
                      color: theme.colors.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ParamSlider extends StatelessWidget {
  const _ParamSlider({
    required this.spec,
    required this.param,
    required this.value,
    required this.onChanged,
  });

  final DspFilterSpec spec;
  final DspParamSpec param;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  param.label,
                  style: theme.textStyles.footnote1.copyWith(
                    color: theme.colors.onSurfaceSecondary,
                  ),
                ),
              ),
              Text(
                param.format(value),
                style: theme.textStyles.footnote1.copyWith(
                  color: theme.colors.primary,
                  fontWeight: FontWeight.w700,
                  // 数值随拖动变宽窄，等宽数字才不会让标签左右跳动。
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          MiuixSlider(
            value: param.clamp(value),
            min: param.min,
            max: param.max,
            height: 22,
            onValueChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
