import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/together/together_controller.dart';
import '../../domain/together/together_models.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
import 'together_member_avatar.dart';

/// 房间成员管理：谁在房里、谁是房主，房主还能把人请出去。
///
/// 成员表以服务端为准（[TogetherController.members] 来自 welcome / members 帧），
/// 踢人后不本地删行，等服务端广播回来的新成员表——否则房主看到的人数会和别人
/// 对不上。
class TogetherMembersPage extends StatelessWidget {
  const TogetherMembersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final together = TogetherController.instance;
    return CyrenePage(
      title: '房间成员',
      bodyBuilder: (context, topPadding) => ListenableBuilder(
        listenable: together,
        builder: (context, _) {
          if (!together.isActive) {
            return CyreneEmptyState(
              vector: MiuixIcons.extended.byName('community')!,
              title: '不在房间里',
              description: '开一个房间或加入别人的房间后，这里会显示房间成员',
            );
          }
          final members = together.members;
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: topPadding + const EdgeInsets.fromLTRB(12, 4, 12, 40),
            children: [
              MiuixSmallTitle(
                '房间 ${together.roomCode ?? '------'} · ${members.length} 人',
                insideMargin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              ),
              if (members.isEmpty)
                CyreneEmptyState(
                  vector: MiuixIcons.extended.byName('contacts')!,
                  title: '还没有人加入',
                  description: '把房间号发给朋友，他们就能进来一起听',
                )
              else
                CyreneMenuGroup(
                  children: [
                    for (final member in members)
                      _MemberRow(
                        member: member,
                        isSelf: member.id == together.self?.id,
                        // 房主才有踢人权限，且踢不了自己（结束房间走设置页）。
                        onKick:
                            together.isHost && member.id != together.self?.id
                            ? () => _confirmKick(context, member)
                            : null,
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              CyreneInlineAlert(
                vector: MiuixIcons.extended.byName('info')!,
                description: together.isHost
                    ? '被移出的人会收到提示并断开，但没有拉黑——他拿着房间号还能再进来。'
                      '不想被陌生人找到就把房间设成私有。'
                    : '只有房主能管理成员。',
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmKick(BuildContext context, TogetherMember member) async {
    final confirmed = await showCyreneDialog<bool>(
      context: context,
      title: '移出成员',
      summary: '确定把「${member.name}」移出房间吗？他会立刻断开，但仍可凭房间号再次加入。',
      builder: (dialogContext, dismiss) {
        final theme = MiuixTheme.of(dialogContext);
        final colors = theme.colors;
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            MiuixTextButton('取消', onPressed: () => dismiss(false)),
            const SizedBox(width: 12),
            MiuixButton(
              onPressed: () => dismiss(true),
              colors: MiuixButtonColors(
                color: colors.error,
                disabledColor: colors.disabledPrimaryButton,
                contentColor: colors.onError,
                disabledContentColor: colors.disabledOnPrimaryButton,
              ),
              child: MiuixText('移出房间', style: theme.textStyles.button),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    TogetherController.instance.kick(member.id);
    CyreneToast.show('已把${member.name}移出房间');
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.isSelf,
    required this.onKick,
  });

  final TogetherMember member;
  final bool isSelf;
  final VoidCallback? onKick;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final tags = [
      if (member.isHost) '房主',
      if (isSelf) '我',
      if (member.userId == null) '未登录',
    ];
    return CyreneMenuRow(
      leading: TogetherMemberAvatar(member: member),
      title: member.name,
      subtitle: tags.isEmpty ? '听众' : tags.join(' · '),
      trailing: onKick == null
          ? const SizedBox.shrink()
          : MiuixTextButton(
              '移出',
              onPressed: onKick,
              // 默认按钮尺寸是给对话框底部用的，塞进列表行里太占地方。
              minWidth: 0,
              minHeight: 32,
              cornerRadius: 12,
              insideMargin: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              textStyle: theme.textStyles.footnote1,
              colors: MiuixButtonColors(
                color: colors.error.withValues(alpha: .12),
                disabledColor: colors.disabledPrimaryButton,
                contentColor: colors.error,
                disabledContentColor: colors.disabledOnPrimaryButton,
              ),
            ),
      // 只有「移出」按钮能触发踢人：整行可点太容易误触到一个破坏性操作。
      onTap: null,
    );
  }
}
