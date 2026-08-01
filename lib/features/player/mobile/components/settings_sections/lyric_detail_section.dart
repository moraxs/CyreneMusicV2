import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../../../../presentation/cyrene/cyrene_overlays.dart';
import '../../../../../presentation/cyrene/cyrene_page.dart';
import '../../../../../presentation/cyrene/cyrene_toast.dart';
import '../../compat/lyric_font_service.dart';
import '../../compat/lyric_style_service.dart';

/// 歌词细节设置区域：字体 / 字号 / 模糊 / 行距（自动/手动）。
///
/// 数据源 [LyricStyleService]（滑块/开关）与 [LyricFontService]（字体行）。
class LyricDetailSection extends StatelessWidget {
  const LyricDetailSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        LyricStyleService(),
        LyricFontService(),
      ]),
      builder: (context, _) {
        final styleService = LyricStyleService();
        final fontService = LyricFontService();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MiuixSmallTitle('歌词细节', insideMargin: EdgeInsets.zero),
            const SizedBox(height: 4),
            CyreneMenuGroup(
                children: [
                  CyreneMenuRow(
                    icon: Icons.font_download_outlined,
                    iconBackground: const Color(0xFF34C759),
                    title: '歌词字体',
                    value: fontService.currentFontName,
                    onTap: () => _showFontPicker(context),
                  ),
                  MiuixSliderPreference(
                    title: '歌词字号',
                    value: styleService.fontSize,
                    min: 24,
                    max: 48,
                    valueText: '${styleService.fontSize.round()} px',
                    onValueChange: styleService.setFontSize,
                  ),
                  MiuixSliderPreference(
                    title: '视觉模糊',
                    value: styleService.blurSigma,
                    min: 0,
                    max: 10,
                    valueText: styleService.blurSigma.toStringAsFixed(1),
                    onValueChange: styleService.setBlurSigma,
                  ),
                  MiuixSwitchPreference(
                    title: '自动行间距',
                    summary: '按字号自适应行距',
                    value: styleService.autoLineHeight,
                    onChanged: styleService.setAutoLineHeight,
                  ),
                  if (!styleService.autoLineHeight)
                    MiuixSliderPreference(
                      title: '行距',
                      value: styleService.lineHeight,
                      min: 60,
                      max: 180,
                      valueText: styleService.lineHeight.round().toString(),
                      onValueChange: styleService.setLineHeight,
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  Future<void> _showFontPicker(BuildContext context) async {
    await showCyreneSheet<void>(
      context: context,
      title: '歌词字体',
      builder: (context, dismiss) => ListenableBuilder(
        listenable: LyricFontService(),
        builder: (context, _) {
          final service = LyricFontService();
          final theme = MiuixTheme.of(context);
          final usingCustom =
              service.fontType == 'custom' && service.customFontPath != null;
          return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: ListView(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                if (usingCustom)
                  CyreneMenuRow(
                    icon: Icons.font_download,
                    iconBackground: const Color(0xFF0A84FF),
                    title: service.currentFontName,
                    subtitle: '本机导入的字体文件',
                    trailing: Icon(
                      Icons.check_rounded,
                      size: 20,
                      color: theme.colors.primary,
                    ),
                  ),
                for (final font in LyricFontService.platformFonts)
                  CyreneMenuRow(
                    icon: Icons.text_fields,
                    iconBackground: const Color(0xFF8E8E93),
                    title: font.name,
                    subtitle: font.description,
                    trailing:
                        !usingCustom && service.presetFontId == font.id
                            ? Icon(
                                Icons.check_rounded,
                                size: 20,
                                color: theme.colors.primary,
                              )
                            : const SizedBox(width: 20),
                    onTap: () => service.setPresetFont(font.id),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: MiuixButton(
                        onPressed: () async {
                          final ok =
                              await LyricFontService().pickAndLoadCustomFont();
                          if (ok) CyreneToast.show('自定义字体已加载');
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            MiuixIcon(
                              vector: MiuixIcons.extended.byName('import')!,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            MiuixText('选择字体文件', style: theme.textStyles.button),
                          ],
                        ),
                      ),
                    ),
                    if (usingCustom) ...[
                      const SizedBox(width: 10),
                      MiuixButton(
                        onPressed: () => service.clearCustomFont(),
                        child: MiuixText('恢复预设', style: theme.textStyles.button),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }
}
