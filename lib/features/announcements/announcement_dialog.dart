import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/announcements/announcement_controller.dart';
import '../../domain/models/announcement.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';

/// 弹出公告。
///
/// [showDismissOption] 为 true（启动自动弹窗）时给出「不再提示」勾选框：勾上再关，
/// 就把这条公告的编号记为水位线，之后只有编号更大的公告才会重新自动弹。不勾直接关，
/// 什么都不记，下次启动照常再弹。
///
/// 设置页的手动入口传 false —— 用户主动点进来看的，给个「不再提示」既没意义
/// （他下次还是会主动点），又会让他误以为设置项里的公告入口也会跟着消失。
Future<void> showAnnouncementDialog(
  BuildContext context,
  Announcement announcement, {
  bool showDismissOption = false,
  AnnouncementController? controller,
}) async {
  final announcements = controller ?? AnnouncementController.instance;

  final dismissForever = await showCyreneDialog<bool>(
    context: context,
    title: announcement.title.isEmpty ? '公告' : announcement.title,
    builder: (dialogContext, dismiss) => _AnnouncementContent(
      announcement: announcement,
      showDismissOption: showDismissOption,
      onDismiss: dismiss,
    ),
  );

  // 只有勾选后点「知道了」才落水位线。点遮罩/返回键溜走的返回 null，同样不记——
  // 没有明确表态就当他还想再看到。
  if (dismissForever == true) {
    await announcements.dismissUntilNewer(announcement.id);
  }
}

class _AnnouncementContent extends StatefulWidget {
  const _AnnouncementContent({
    required this.announcement,
    required this.showDismissOption,
    required this.onDismiss,
  });

  final Announcement announcement;
  final bool showDismissOption;
  final void Function([bool? result]) onDismiss;

  @override
  State<_AnnouncementContent> createState() => _AnnouncementContentState();
}

class _AnnouncementContentState extends State<_AnnouncementContent> {
  bool _dismissForever = false;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    // 内容区高度上限。
    //
    // 不能写死一个常量：Miuix 的对话框面板在小屏是「屏高 - 边距」，本 Column 又
    // 是外层 Column 的普通子节点，拿到的主轴约束是**无界**的——固定 360 在矮屏
    // （横屏手机 / 平板）上比可用空间还高，Column 直接撑爆，「知道了」被挤出弹窗。
    // 按屏高折半再与 360 取小：高屏维持原来的观感，矮屏自动收窄。
    final maxContentHeight = math.min(
      360.0,
      MediaQuery.sizeOf(context).height * .5,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxContentHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Flexible 而非固定高度：勾选框与按钮先占位，正文吃剩下的空间，
          // 空间不够时收缩并交给内部的 SingleChildScrollView 滚动。
          Flexible(
            child: SingleChildScrollView(
              child: Text(
                widget.announcement.content,
                style: theme.textStyles.body2.copyWith(
                  color: theme.colors.onSurfaceContainer,
                ),
              ),
            ),
          ),
          if (widget.showDismissOption) ...[
            const SizedBox(height: 12),
            // 整行可点，不用让用户去戳那个 26dp 的方块。
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _dismissForever = !_dismissForever),
              child: Row(
                children: [
                  MiuixCheckbox(
                    value: _dismissForever,
                    onChanged: (value) =>
                        setState(() => _dismissForever = value ?? false),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '不再提示此公告',
                      style: theme.textStyles.body2.copyWith(
                        color: theme.colors.onSurfaceVariantSummary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              MiuixButton(
                onPressed: () => widget.onDismiss(_dismissForever),
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                child: MiuixText('知道了', style: theme.textStyles.button),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
