import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../../../../presentation/cyrene/cyrene_overlays.dart';
import '../../../../../presentation/cyrene/cyrene_page.dart';
import '../../../../../presentation/cyrene/cyrene_toast.dart';
import '../../compat/player_background_service.dart';
import '../../compat/wiki_services.dart';

/// 播放器背景设置区域：自适应 / 动态 / 纯色 / 图片 / 视频 + 颜色 + 模糊。
///
/// 数据源 [PlayerBackgroundService]（Listenable）；图片/视频为赞助用户专属。
class BackgroundSection extends StatelessWidget {
  const BackgroundSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PlayerBackgroundService(),
      builder: (context, _) {
        final bg = PlayerBackgroundService();
        final theme = MiuixTheme.of(context);
        final isSponsor = AuthService().currentUser?.isSponsor ?? false;
        final current = bg.backgroundType;

        Widget checkFor(PlayerBackgroundType type) => current == type
            ? Icon(Icons.check_rounded, size: 20, color: theme.colors.primary)
            : const SizedBox(width: 20);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MiuixSmallTitle('播放器背景', insideMargin: EdgeInsets.zero),
            const SizedBox(height: 4),
            CyreneMenuGroup(
                children: [
                  CyreneMenuRow(
                    icon: Icons.auto_awesome_outlined,
                    iconBackground: const Color(0xFF0A84FF),
                    title: '自适应',
                    subtitle: '基于专辑封面提取颜色',
                    trailing: checkFor(PlayerBackgroundType.adaptive),
                    onTap: () =>
                        bg.setBackgroundType(PlayerBackgroundType.adaptive),
                  ),
                  CyreneMenuRow(
                    icon: Icons.blur_on,
                    iconBackground: const Color(0xFFBF5AF2),
                    title: '动态背景',
                    subtitle: '基于封面的动态渐变效果',
                    trailing: checkFor(PlayerBackgroundType.dynamic),
                    onTap: () =>
                        bg.setBackgroundType(PlayerBackgroundType.dynamic),
                  ),
                  CyreneMenuRow(
                    icon: Icons.palette_outlined,
                    iconBackground: const Color(0xFFFF9F0A),
                    title: '纯色背景',
                    subtitle: '使用自定义纯色',
                    trailing: checkFor(PlayerBackgroundType.solidColor),
                    onTap: () => bg
                        .setBackgroundType(PlayerBackgroundType.solidColor),
                  ),
                  if (bg.isSolidColor)
                    CyreneMenuRow(
                      icon: Icons.colorize,
                      iconBackground: const Color(0xFFFF453A),
                      title: '选择颜色',
                      trailing: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: bg.solidColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colors.onSurfaceVariantActions,
                          ),
                        ),
                      ),
                      onTap: () => _pickSolidColor(context),
                    ),
                  CyreneMenuRow(
                    icon: Icons.image_outlined,
                    iconBackground: const Color(0xFF34C759),
                    title: '图片背景',
                    subtitle: bg.mediaPath != null && bg.isImage
                        ? '自定义图片'
                        : '未设置图片',
                    value: isSponsor ? null : '赞助专属',
                    trailing: checkFor(PlayerBackgroundType.image),
                    onTap: () => _selectMediaBackground(
                      context,
                      isVideo: false,
                      isSponsor: isSponsor,
                    ),
                  ),
                  CyreneMenuRow(
                    icon: Icons.video_library_outlined,
                    iconBackground: const Color(0xFFFF375F),
                    title: '视频背景',
                    subtitle: bg.mediaPath != null && bg.isVideo
                        ? '自定义视频'
                        : '未设置视频',
                    value: isSponsor ? null : '赞助专属',
                    trailing: checkFor(PlayerBackgroundType.video),
                    onTap: () => _selectMediaBackground(
                      context,
                      isVideo: true,
                      isSponsor: isSponsor,
                    ),
                  ),
                  if ((bg.isImage || bg.isVideo) && isSponsor) ...[
                    MiuixSliderPreference(
                      title: '背景模糊',
                      value: bg.blurAmount,
                      min: 0,
                      max: 50,
                      valueText: '${bg.blurAmount.toInt()}',
                      onValueChange: bg.setBlurAmount,
                    ),
                    if (bg.mediaPath != null)
                      CyreneMenuRow(
                        icon: Icons.delete_outline_rounded,
                        title: '清除背景媒体',
                        subtitle: '移除当前图片/视频',
                        destructive: true,
                        onTap: () => bg.clearMediaBackground(),
                      ),
                  ],
                ],
              ),
          ],
        );
      },
    );
  }

  Future<void> _pickSolidColor(BuildContext context) async {
    final bg = PlayerBackgroundService();
    final picked = await showCyreneDialog<Color>(
      context: context,
      title: '自定义颜色',
      builder: (context, dismiss) => _SolidColorDialog(
        initial: bg.solidColor,
        dismiss: dismiss,
      ),
    );
    if (picked != null) await bg.setSolidColor(picked);
  }

  Future<void> _selectMediaBackground(
    BuildContext context, {
    required bool isVideo,
    required bool isSponsor,
  }) async {
    if (!isSponsor) {
      CyreneToast.show('此功能为赞助用户专属，成为赞助用户即可解锁');
      return;
    }
    final bg = PlayerBackgroundService();
    final targetType = isVideo
        ? PlayerBackgroundType.video
        : PlayerBackgroundType.image;
    final hasMatchingMedia = bg.mediaPath != null &&
        (isVideo
            ? bg.isVideoFile(bg.mediaPath!)
            : bg.isImageFile(bg.mediaPath!));
    if (hasMatchingMedia && bg.backgroundType != targetType) {
      await bg.setBackgroundType(targetType);
      return;
    }
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: isVideo
          ? const ['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v']
          : const ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'],
      dialogTitle: isVideo ? '选择背景视频' : '选择背景图片',
    );
    final path = result?.files.single.path;
    if (path == null) return;
    await bg.setMediaBackground(path);
    CyreneToast.show(isVideo ? '背景视频已设置' : '背景图片已设置');
  }
}

/// 纯色背景取色对话框：Miuix 调色板 + 取消/应用。
class _SolidColorDialog extends StatefulWidget {
  const _SolidColorDialog({required this.initial, required this.dismiss});

  final Color initial;
  final void Function([Color?]) dismiss;

  @override
  State<_SolidColorDialog> createState() => _SolidColorDialogState();
}

class _SolidColorDialogState extends State<_SolidColorDialog> {
  late Color _color = widget.initial;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        MiuixColorPalette(
          color: _color,
          onColorChanged: (color) => setState(() => _color = color),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            MiuixTextButton('取消', onPressed: () => widget.dismiss()),
            const SizedBox(width: 10),
            MiuixButton(
              onPressed: () => widget.dismiss(_color),
              colors: MiuixButtonDefaults.buttonColorsPrimary(context),
              child: MiuixText('应用色彩', style: theme.textStyles.button),
            ),
          ],
        ),
      ],
    );
  }
}
