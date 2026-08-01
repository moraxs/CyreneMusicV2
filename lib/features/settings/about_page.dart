import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../app/app_version.dart';
import '../../infrastructure/services/developer_mode_service.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
import 'user_agreement_page.dart';

/// 关于页（对应原版 about_settings_page.dart 的移动端 Material 版）。
///
/// 原版的「检查更新 / 自动更新」与新版设置主页的独立「检查更新」入口重复，
/// 不再移植；保留头部 Logo/版本、版本信息（连点开发者模式彩蛋）、用户协议
/// 与开放源代码许可。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const _iconBlue = Color(0xFF3482FF);
  static const _iconGreen = Color(0xFF3CC756);
  static const _iconPurple = Color(0xFF8A64FF);

  void _onVersionClicked() {
    final message = DeveloperModeService.instance.onVersionClicked();
    if (message != null) CyreneToast.show(message);
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return CyrenePage(
      title: '关于',
      bodyBuilder: (context, topPadding) => ListView(
        physics: const BouncingScrollPhysics(),
        padding: topPadding + const EdgeInsets.fromLTRB(12, 4, 12, 40),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/icons/new_ico_white.png',
                    width: 96,
                    height: 96,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Cyrene Music',
                  style: theme.textStyles.title3.copyWith(
                    color: theme.colors.onBackground,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                // 与原版一致：点击版本号可触发开发者模式彩蛋。
                GestureDetector(
                  onTap: _onVersionClicked,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Text(
                      'v$appVersion',
                      style: theme.textStyles.body2.copyWith(
                        color: theme.colors.onSurfaceVariantSummary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          CyreneMenuGroup(
            children: [
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('info')!,
                iconBackground: _iconBlue,
                title: '版本信息',
                subtitle: 'v$appVersion',
                trailing: const SizedBox.shrink(),
                onTap: _onVersionClicked,
              ),
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('notes')!,
                iconBackground: _iconPurple,
                title: '用户协议',
                subtitle: '查看用户协议与隐私政策',
                onTap: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => const UserAgreementPage(),
                  ),
                ),
              ),
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('file')!,
                iconBackground: _iconGreen,
                title: '开放源代码许可',
                subtitle: '查看第三方库许可信息',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Cyrene Music',
                  applicationVersion: 'v$appVersion',
                  applicationIcon: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/icons/new_ico_white.png',
                        width: 48,
                        height: 48,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
