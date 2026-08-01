import 'package:flutter/cupertino.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/audio_sources/audio_source_preferences_controller.dart';
import '../../application/auth/account_session_controller.dart';
import '../../application/playback/playback_controller.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../history/history_page.dart';
import '../local/local_music_page.dart';
import '../settings/settings_page.dart';
import '../support/support_page.dart';

class MoreMenuDrawer extends StatelessWidget {
  const MoreMenuDrawer({
    super.key,
    required this.account,
    required this.audioSources,
    required this.playback,
    required this.dismiss,
  });

  final AccountSessionController account;
  final AudioSourcePreferencesController audioSources;
  final PlaybackController playback;

  /// 抽屉关闭函数：携带的回调会在抽屉退场动画结束后由 [show] 执行。
  final void Function([VoidCallback? action]) dismiss;

  static Future<void> show(
    BuildContext context, {
    required AccountSessionController account,
    required AudioSourcePreferencesController audioSources,
    required PlaybackController playback,
  }) async {
    // 菜单项点击时先关抽屉（走 Miuix 退场动画），退场结束后再执行跳转，
    // 避免退场收尾的 pop 误关刚推入的新页面。
    final action = await showCyreneSheet<VoidCallback>(
      context: context,
      title: '更多',
      builder: (_, dismiss) => MoreMenuDrawer(
        account: account,
        audioSources: audioSources,
        playback: playback,
        dismiss: dismiss,
      ),
    );
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 4,
            children: [
              Text(
                '资料库、设置与支持',
                style: theme.textStyles.body2.copyWith(
                  color: theme.colors.onSurfaceVariantSummary,
                ),
              ),
              ...moreMenuItems(
                account: account,
                audioSources: audioSources,
                playback: playback,
              ).map(
                (item) => MoreAction(
                  icon: item.icon,
                  title: item.title,
                  description: item.description,
                  onTap: () => _openPage(context, item.pageBuilder(context)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPage(BuildContext context, Widget page) {
    final navigator = Navigator.of(context);
    // 先关抽屉；跳转动作作为结果带出，由 show() 在抽屉完全关闭后执行。
    dismiss(() {
      navigator.push(CupertinoPageRoute<void>(builder: (_) => page));
    });
  }
}

/// 「更多」菜单项数据：图标、标题、描述、目标页面构造器。
///
/// 抽屉（移动端，底部 sheet）与桌面 rail 的「更多」内容区共用此数据，
/// 只在点击语义上不同：移动端先 dismiss 退场再 push，桌面端直接 push。
class MoreMenuItem {
  const MoreMenuItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.pageBuilder,
  });

  final MiuixVectorIcon icon;
  final String title;
  final String description;
  final Widget Function(BuildContext context) pageBuilder;
}

/// 「更多」菜单项清单（播放历史 / 本地音乐 / 设置 / 帮助与支持）。
List<MoreMenuItem> moreMenuItems({
  required AccountSessionController account,
  required AudioSourcePreferencesController audioSources,
  required PlaybackController playback,
}) {
  return [
    MoreMenuItem(
      icon: MiuixIcons.extended.byName('recent')!,
      title: '播放历史',
      description: '查看最近听过的音乐',
      pageBuilder: (_) => HistoryPage(playback: playback),
    ),
    MoreMenuItem(
      icon: MiuixIcons.extended.byName('folder')!,
      title: '本地音乐',
      description: '管理设备上的音乐文件',
      pageBuilder: (_) => LocalMusicPage(playback: playback),
    ),
    MoreMenuItem(
      icon: MiuixIcons.extended.byName('settings')!,
      title: '设置',
      description: '账号、音源与应用偏好',
      pageBuilder: (_) =>
          SettingsPage(account: account, audioSources: audioSources),
    ),
    MoreMenuItem(
      icon: MiuixIcons.extended.byName('help')!,
      title: '帮助与支持',
      description: '',
      pageBuilder: (_) => SupportPage(account: account),
    ),
  ];
}

/// 「更多」菜单项渲染行（公开，供移动端抽屉与桌面内容区共用）。
///
/// [onTap] 由调用方注入：移动端抽屉注入「先 dismiss 再 push」，
/// 桌面端直接 push。
class MoreAction extends StatelessWidget {
  const MoreAction({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final MiuixVectorIcon icon;
  final String title;
  final String? description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixBasicComponent(
      title: title,
      summary: description,
      insideMargin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      startAction: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: MiuixIcon(vector: icon, size: 19, tint: colors.onBackground),
      ),
      endActions: [
        MiuixIcon(
          vector: MiuixIcons.extended.byName('chevronForward')!,
          size: 17,
          tint: colors.onSurfaceVariantActions,
        ),
      ],
      onClick: onTap,
      role: MiuixBasicComponentRole.button,
    );
  }
}
