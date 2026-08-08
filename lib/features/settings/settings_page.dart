import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../app/app_version.dart';
import '../../application/audio_sources/audio_source_preferences_controller.dart';
import '../../application/auth/account_session_controller.dart';
import '../../application/stores/appearance_settings_store.dart';
import '../../domain/models/media_url.dart';
import '../../domain/models/user.dart';
import '../../infrastructure/audio/equalizer_service.dart';
import '../../infrastructure/services/announcement_service.dart';
import '../../infrastructure/services/developer_mode_service.dart';
import '../../infrastructure/services/update_service.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
import 'about_page.dart';
import 'appearance_settings_page.dart';
import 'audio_source_settings_page.dart';
import 'developer_options_page.dart';
import 'equalizer_page.dart';
import 'login_page.dart';
import 'personal_center_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.account,
    required this.audioSources,
    this.onOpenSecondary,
    this.body,
  });

  final AccountSessionController account;
  final AudioSourcePreferencesController audioSources;
  final ValueChanged<Widget>? onOpenSecondary;
  final Widget? body;

  // HyperOS 系统设置的彩色图标底色（对照官方设置页取色）。
  static const _iconBlue = Color(0xFF3482FF);
  static const _iconGreen = Color(0xFF3CC756);
  static const _iconPurple = Color(0xFF8A64FF);
  static const _iconOrange = Color(0xFFFF9F0A);

  @override
  Widget build(BuildContext context) {
    final secondaryBody = body;
    if (secondaryBody != null) return secondaryBody;

    return CyrenePage(
      title: '设置',
      bodyBuilder: (context, topPadding) => AnimatedBuilder(
        animation: account,
        builder: (context, _) {
          final state = account.state;
          return ListView(
          physics: const BouncingScrollPhysics(),
          // HyperOS：卡片距屏幕两侧 12，组间距 12，节标题走 MiuixSmallTitle
          //（水平内边距 28 = 页边 12 + 卡内 16，与卡片内容左缘对齐）。
          padding: topPadding + const EdgeInsets.fromLTRB(12, 4, 12, 40),
          children: [
            _SectionTitle('账号'),
            CyreneMenuGroup(children: _accountRows(context, state)),
            if (state.errorMessage != null && !state.isBusy) ...[
              const SizedBox(height: 12),
              _SessionMessage(
                message: state.errorMessage!,
                onDismiss: account.clearError,
              ),
            ],
            const SizedBox(height: 12),
            _SectionTitle('音乐'),
            CyreneMenuGroup(
              children: [
                CyreneMenuRow(
                  key: const Key('open-audio-source-settings'),
                  vector: MiuixIcons.extended.byName('music')!,
                  iconBackground: _iconBlue,
                  title: '播放与音源',
                  subtitle: '音质、解析服务与播放偏好',
                  onTap: () => _openPage(
                    context,
                    AudioSourceSettingsPage(
                      controller: audioSources,
                      account: account,
                      token: state.isLoggedIn ? account.token : null,
                      desktopLayout: onOpenSecondary != null,
                    ),
                  ),
                ),
                ListenableBuilder(
                  listenable: EqualizerService.instance,
                  builder: (context, _) => CyreneMenuRow(
                    vector: MiuixIcons.extended.byName('tune')!,
                    iconBackground: _iconGreen,
                    title: '音效与均衡器',
                    subtitle: '自定义音频频率响应',
                    value: EqualizerService.instance.enabled ? '已开启' : '已关闭',
                    onTap: () => _openPage(context, const EqualizerPage()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SectionTitle('应用'),
            CyreneMenuGroup(
              children: [
                ListenableBuilder(
                  listenable: AppearanceSettingsStore.instance,
                  builder: (context, _) => CyreneMenuRow(
                    vector: MiuixIcons.extended.byName('theme')!,
                    iconBackground: _iconPurple,
                    title: '外观',
                    subtitle: '主题、播放器样式与背景',
                    onTap: () => _openPage(
                      context,
                      AppearanceSettingsPage(account: account),
                    ),
                  ),
                ),
                CyreneMenuRow(
                  vector: MiuixIcons.extended.byName('promotions')!,
                  iconBackground: _iconBlue,
                  title: '公告',
                  subtitle: '查看最新通知',
                  onTap: () => _showAnnouncement(context),
                ),
                CyreneMenuRow(
                  vector: MiuixIcons.extended.byName('update')!,
                  iconBackground: _iconGreen,
                  title: '检查更新',
                  value: 'v$appVersion',
                  onTap: () => _checkUpdate(context),
                ),
                CyreneMenuRow(
                  vector: MiuixIcons.extended.byName('info')!,
                  iconBackground: _iconOrange,
                  title: '关于 Cyrene Music',
                  onTap: () => _openPage(context, const AboutPage()),
                ),
                // 连点关于页版本号 5 次开启后才出现（对应原版开发者模式）。
                ListenableBuilder(
                  listenable: DeveloperModeService.instance,
                  builder: (context, _) =>
                      DeveloperModeService.instance.isDeveloperMode
                      ? CyreneMenuRow(
                          vector: MiuixIcons.extended.byName('notes')!,
                          iconBackground: const Color(0xFF5F6368),
                          title: '开发者选项',
                          subtitle: '性能叠加层与运行日志',
                          onTap: () => _openPage(
                            context,
                            const DeveloperOptionsPage(),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ],
          );
        },
      ),
    );
  }

  void _openPage(BuildContext context, Widget page) {
    final openSecondary = onOpenSecondary;
    if (openSecondary != null) {
      openSecondary(page);
      return;
    }
    Navigator.of(
      context,
    ).push(CupertinoPageRoute<void>(builder: (_) => page));
  }

  /// 查看服务端公告（对应原版启动公告的手动入口）。
  Future<void> _showAnnouncement(BuildContext context) async {
    final announcement = await AnnouncementService.instance.fetchAnnouncement();
    if (!context.mounted) return;
    if (announcement == null || !announcement.enabled) {
      CyreneToast.show('暂无公告');
      return;
    }
    await showCyreneDialog<void>(
      context: context,
      title: announcement.title,
      builder: (dialogContext, dismiss) {
        final theme = MiuixTheme.of(dialogContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: Text(
                  announcement.content,
                  style: theme.textStyles.body2.copyWith(
                    color: theme.colors.onSurfaceContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                MiuixButton(
                  onPressed: () => dismiss(),
                  colors: MiuixButtonDefaults.buttonColorsPrimary(
                    dialogContext,
                  ),
                  child: MiuixText('知道了', style: theme.textStyles.button),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// 检查应用更新；有新版时展示更新说明并支持复制下载链接。
  Future<void> _checkUpdate(BuildContext context) async {
    CyreneToast.show('正在检查更新…');
    final info = await UpdateService.instance.checkUpdate();
    if (!context.mounted) return;
    if (info == null) {
      CyreneToast.show('当前已是最新版本');
      return;
    }
    final downloadUrl =
        info.androidAbiDownloads?[info.androidTargetAbi?.wireName] ??
        info.platformDownloads?['android'] ??
        info.downloadUrl;
    await showCyreneDialog<void>(
      context: context,
      title: '发现新版本 ${info.version}',
      builder: (dialogContext, dismiss) {
        final theme = MiuixTheme.of(dialogContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                child: Text(
                  info.changelog,
                  style: theme.textStyles.body2.copyWith(
                    color: theme.colors.onSurfaceContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                MiuixTextButton('稍后再说', onPressed: () => dismiss()),
                if (downloadUrl != null) ...[
                  const SizedBox(width: 12),
                  MiuixButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: downloadUrl));
                      dismiss();
                      CyreneToast.show('下载链接已复制，请在浏览器中打开');
                    },
                    colors: MiuixButtonDefaults.buttonColorsPrimary(
                      dialogContext,
                    ),
                    child: MiuixText('复制下载链接', style: theme.textStyles.button),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  List<Widget> _accountRows(BuildContext context, AccountSessionState state) {
    if (state.status == AccountSessionStatus.restoring) {
      return const [
        Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              MiuixCircularProgressIndicator(size: 18, strokeWidth: 2),
              SizedBox(width: 12),
              Text('正在恢复账号信息…'),
            ],
          ),
        ),
      ];
    }

    final user = state.user;
    if (user == null) {
      return [
        CyreneMenuRow(
          key: const Key('open-login-button'),
          vector: MiuixIcons.extended.byName('contactsCircle')!,
          iconBackground: _iconBlue,
          title: '登录账号',
          subtitle: 'Cyrene Music 账号',
          onTap: () => _openLoginPage(context),
        ),
      ];
    }

    return [
      CyreneMenuRow(
        key: const Key('open-personal-center'),
        leading: _AccountAvatar(user: user),
        title: user.username,
        subtitle: user.email,
        onTap: () =>
            _openPage(context, PersonalCenterPage(account: account)),
      ),
    ];
  }

  Future<void> _openLoginPage(BuildContext context) async {
    account.clearError();
    final openSecondary = onOpenSecondary;
    if (openSecondary != null) {
      openSecondary(LoginPage(account: account));
      return;
    }
    final loggedIn = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(builder: (_) => LoginPage(account: account)),
    );
    if (loggedIn == true && context.mounted) {
      CyreneToast.show('登录成功，账号信息已安全保存在本机。');
    }
  }
}

/// 设置分组小标题：沿用 MiuixSmallTitle 的副标题字号与配色，但不加粗
/// （对照 HyperOS 系统设置：分组标题为常规字重小字）。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: MiuixText(
        text,
        style: theme.textStyles.subtitle.copyWith(
          fontWeight: FontWeight.w400,
        ),
        color: theme.colors.onBackgroundVariant,
      ),
    );
  }
}

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

/// 设置主页账号行的圆形头像：真实头像 + 首字母回退。与个人中心顶部
/// 沉浸式大卡片同源，此处用于列表行内的小尺寸展示。
class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final initial = user.username.trim().isEmpty
        ? '?'
        : user.username.trim().characters.first.toUpperCase();
    return CircleAvatar(
      radius: 18,
      foregroundImage: user.avatarUrl?.isNotEmpty == true
          ? CachedNetworkImageProvider(
              user.avatarUrl!,
              headers: imageHeaders(user.avatarUrl!),
            )
          : null,
      // 加载失败时静默回退到文字头像，避免未处理的异步图片异常。
      onForegroundImageError: user.avatarUrl?.isNotEmpty == true
          ? (_, _) {}
          : null,
      backgroundColor: colors.primary,
      child: Text(
        initial,
        style: TextStyle(color: colors.onPrimary, fontWeight: FontWeight.w600),
      ),
    );
  }
}
