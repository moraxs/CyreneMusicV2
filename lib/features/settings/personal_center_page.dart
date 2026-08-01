import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/auth/account_session_controller.dart';
import '../../domain/models/user.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_user_hero_card.dart';

/// 个人中心（账号聚焦）：顶部复用「我的」页同款沉浸式用户卡片，
/// 下方接账号详情行（用户 ID / 邮箱 / 赞助状态 / 最后登录 / IP 归属）
/// 与退出登录。从设置页账号卡片下沉而来，登录态变化时实时刷新。
class PersonalCenterPage extends StatelessWidget {
  const PersonalCenterPage({super.key, required this.account});

  final AccountSessionController account;

  @override
  Widget build(BuildContext context) => CyrenePage(
    title: '个人中心',
    bodyBuilder: (context, topPadding) => AnimatedBuilder(
      animation: account,
      builder: (context, _) {
        final state = account.state;
        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: topPadding + const EdgeInsets.fromLTRB(12, 4, 12, 40),
          children: [
            if (state.status == AccountSessionStatus.restoring)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: MiuixCircularProgressIndicator()),
              )
            else if (state.user != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: CyreneUserHeroCard(user: state.user!),
              ),
              CyreneMenuGroup(children: _accountDetailRows(state.user!)),
              const SizedBox(height: 12),
              CyreneMenuGroup(
                children: [
                  CyreneMenuRow(
                    key: const Key('logout-button'),
                    icon: Icons.logout_rounded,
                    title: '退出登录',
                    destructive: true,
                    trailing: const SizedBox.shrink(),
                    onTap: () => _confirmLogout(context),
                  ),
                ],
              ),
            ],
            if (state.errorMessage != null && !state.isBusy) ...[
              const SizedBox(height: 12),
              _SessionMessage(
                message: state.errorMessage!,
                onDismiss: account.clearError,
              ),
            ],
          ],
        );
      },
    ),
  );

  /// 账号详情行（无图标块的中性行，用 trailing 展示值）。
  List<Widget> _accountDetailRows(User user) => [
    CyreneMenuRow(
      icon: Icons.alternate_email_rounded,
      title: '用户 ID',
      value: '${user.id}',
      trailing: const SizedBox.shrink(),
    ),
    CyreneMenuRow(
      icon: Icons.mail_outline_rounded,
      title: '邮箱',
      value: user.email,
      trailing: const SizedBox.shrink(),
    ),
    CyreneMenuRow(
      icon: Icons.star_rounded,
      title: '赞助状态',
      // Premium（Cyrene Premium 买断）优先于 Sponsor（上墙赞助）：后端
      // has_listening_card 与 is_sponsor 解耦，买 Premium 只置前者，故这里
      // 以 hasListeningCard 为最高优先级判断。
      value: user.hasListeningCard
          ? 'Cyrene Premium'
          : (user.isSponsor ? 'Sponsor' : '普通用户'),
      trailing: const SizedBox.shrink(),
    ),
    if (user.lastLogin != null && user.lastLogin!.isNotEmpty)
      CyreneMenuRow(
        icon: Icons.access_time_rounded,
        title: '最后登录',
        value: user.lastLogin!,
        trailing: const SizedBox.shrink(),
      ),
    if (user.ipLocation != null && user.ipLocation!.isNotEmpty)
      CyreneMenuRow(
        icon: Icons.location_on_outlined,
        title: 'IP 归属',
        value: user.ipLocation!,
        trailing: const SizedBox.shrink(),
      ),
  ];

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showCyreneDialog<bool>(
      context: context,
      title: '退出登录？',
      summary: '本机保存的登录凭证将被清除。',
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
                  child: MiuixText('退出登录', style: theme.textStyles.button),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (confirmed == true) await account.logout();
  }
}

/// 退出登录确认 + 账号状态提示条，均由设置页搬来（设置页账号卡片已改为
/// 单行入口，退出登录只在个人中心提供）。
class _SessionMessage extends StatelessWidget {
  const _SessionMessage({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Stack(
      children: [
        CyreneInlineAlert(
          vector: MiuixIcons.extended.byName('info')!,
          title: '账号状态',
          description: message,
          destructive: true,
        ),
        Positioned(
          top: 6,
          right: 6,
          child: MiuixIconButton(
            onPressed: onDismiss,
            child: MiuixIcon(
              vector: MiuixIcons.extended.byName('close')!,
              size: 16,
              tint: colors.onErrorContainer,
            ),
          ),
        ),
      ],
    );
  }
}
