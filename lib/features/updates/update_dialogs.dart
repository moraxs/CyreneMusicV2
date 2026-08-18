import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_version.dart';
import '../../application/updates/update_controller.dart';
import '../../domain/models/app_update.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_toast.dart';

/// 弹出更新提示。
///
/// 三种形态共用一个弹窗：
/// - 服务器维护（`fixing`）：只展示公告，不给下载入口。
/// - 强制更新：不可关闭，只有「立即更新」。
/// - 普通更新：稍后提醒 / 忽略此版本 / 立即更新。
Future<void> showUpdateDialog(
  BuildContext context,
  UpdateInfo info, {
  UpdateController? controller,
}) async {
  final update = controller ?? UpdateController.instance;
  // 强制更新与维护公告都不允许点遮罩溜走。
  final dismissible = !info.forceUpdate && !info.fixing;

  // 返回用户是否点了「立即更新」。不能在按钮回调里直接压进度弹窗：dismiss 只是
  // 触发 Miuix 退场动画，真正的 Navigator.pop 要等动画结束才发生。若此刻立刻
  // push 进度弹窗，退场动画收尾的 pop 会误关掉压在顶上的进度弹窗（见
  // _CyreneOverlayPage.onDismissFinished）。所以先等这里完整 pop 返回，再压进度弹窗。
  final proceed = await showCyreneDialog<bool>(
    context: context,
    title: info.fixing ? '服务器正在维护' : '发现新版本',
    summary: info.fixing ? null : 'v$appVersion → v${info.version}',
    barrierDismissible: dismissible,
    builder: (dialogContext, dismiss) {
      final theme = MiuixTheme.of(dialogContext);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: SingleChildScrollView(
              child: Text(
                info.changelog,
                style: theme.textStyles.body2.copyWith(
                  color: theme.colors.onSurfaceContainer,
                ),
              ),
            ),
          ),
          if (info.forceUpdate && !info.fixing) ...[
            const SizedBox(height: 12),
            _Notice(text: '此版本为强制更新，请立即更新后继续使用。'),
          ],
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 12,
            runSpacing: 8,
            children: [
              if (dismissible) ...[
                MiuixTextButton(
                  '稍后提醒',
                  onPressed: () {
                    update.remindLater(info.version);
                    dismiss(false);
                    CyreneToast.show('下次启动时会再次提示');
                  },
                ),
                MiuixTextButton(
                  '忽略此版本',
                  onPressed: () async {
                    await update.ignoreVersion(info.version);
                    dismiss(false);
                    CyreneToast.show('已忽略 v${info.version}');
                  },
                ),
              ],
              if (info.fixing)
                MiuixTextButton('我知道了', onPressed: () => dismiss(false))
              else
                MiuixButton(
                  onPressed: () => dismiss(true),
                  colors: MiuixButtonDefaults.buttonColorsPrimary(
                    dialogContext,
                  ),
                  child: MiuixText(
                    update.isPlatformSupported ? '立即更新' : '前往下载',
                    style: theme.textStyles.button,
                  ),
                ),
            ],
          ),
        ],
      );
    },
  );

  if (proceed == true && context.mounted) {
    _startUpdate(context, info, update);
  }
}

/// 平台支持应用内更新就走下载安装流程，否则把下载地址交给系统浏览器。
/// iOS（自签名分发）额外弹出「重新签名覆盖安装」引导，而非直接跳浏览器。
void _startUpdate(
  BuildContext context,
  UpdateInfo info,
  UpdateController update,
) {
    if (!update.isPlatformSupported) {
    final url = info.resolveDownloadUrl();
    if (url == null || url.isEmpty) {
      CyreneToast.show('该版本没有提供当前平台的下载地址');
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _showIosSideloadGuide(context, url);
      return;
    }
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    return;
  }

  showUpdateProgressDialog(
    context,
    controller: update,
    forceUpdate: info.forceUpdate,
    retry: () => update.startUpdate(info),
  );
  update.startUpdate(info);
}

/// iOS 自签名分发的更新引导。
///
/// iOS 不允许应用自行替换/安装自己（非 App Store 安装的应用，更新 = 用户用
/// AltStore / Sideloadly 重新签名覆盖安装）。因此这里先讲清步骤，再让用户
/// 决定是否跳去浏览器下载新版 .ipa，而不是把链接静默丢给系统浏览器。
Future<void> _showIosSideloadGuide(BuildContext context, String url) async {
  final proceed = await showCyreneDialog<bool>(
    context: context,
    title: '更新需重新安装',
    summary: 'iOS 自签名安装的应用无法在应用内自动更新',
    builder: (dialogContext, dismiss) {
      final theme = MiuixTheme.of(dialogContext);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _GuideStep(
            step: 1,
            text: '点击「去下载」，在浏览器打开新版安装包（.ipa）的下载页面。',
          ),
          const SizedBox(height: 10),
          const _GuideStep(
            step: 2,
            text: '下载后用 AltStore / Sideloadly 等工具为该安装包重新签名。',
          ),
          const SizedBox(height: 10),
          const _GuideStep(
            step: 3,
            text: '以相同的 Bundle ID 覆盖安装即可完成更新，歌单、设置等本地数据会保留。',
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 12,
            runSpacing: 8,
            children: [
              MiuixTextButton('取消', onPressed: () => dismiss(false)),
              MiuixButton(
                onPressed: () => dismiss(true),
                colors: MiuixButtonDefaults.buttonColorsPrimary(dialogContext),
                child: MiuixText('去下载', style: theme.textStyles.button),
              ),
            ],
          ),
        ],
      );
    },
  );

  if (proceed == true && context.mounted) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

/// 引导弹窗里的编号步骤行。
class _GuideStep extends StatelessWidget {
  const _GuideStep({required this.step, required this.text});

  final int step;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$step',
            style: theme.textStyles.body2.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: theme.textStyles.body2.copyWith(
              color: colors.onSurfaceContainer,
            ),
          ),
        ),
      ],
    );
  }
}

/// 下载进度弹窗。
///
/// 下载期间不可关闭（中途退出会留下半截文件）；失败后转为可关闭的错误态，
/// 让用户能退出去重试。强制更新时连错误态也不允许关闭——只给「重试」，
/// 避免用户以失败为由停留在旧版本继续使用。
Future<void> showUpdateProgressDialog(
  BuildContext context, {
  UpdateController? controller,
  bool forceUpdate = false,
  VoidCallback? retry,
}) {
  final update = controller ?? UpdateController.instance;
  return showCyreneDialog<void>(
    context: context,
    title: '正在更新',
    barrierDismissible: false,
    builder: (dialogContext, dismiss) => _UpdateProgressContent(
      update: update,
      onDismiss: dismiss,
      forceUpdate: forceUpdate,
      retry: retry,
    ),
  );
}

class _UpdateProgressContent extends StatefulWidget {
  const _UpdateProgressContent({
    required this.update,
    required this.onDismiss,
    this.forceUpdate = false,
    this.retry,
  });

  final UpdateController update;
  final void Function([void result]) onDismiss;
  final bool forceUpdate;
  final VoidCallback? retry;

  @override
  State<_UpdateProgressContent> createState() => _UpdateProgressContentState();
}

class _UpdateProgressContentState extends State<_UpdateProgressContent> {
  @override
  void initState() {
    super.initState();
    widget.update.addListener(_onUpdateChanged);
  }

  @override
  void dispose() {
    widget.update.removeListener(_onUpdateChanged);
    super.dispose();
  }

  /// 下载结束且没有错误说明安装已经拉起（安卓切到系统安装器 / Windows 即将
  /// 退出进程），此时把弹窗收掉，不然它会一直盖在上面。
  void _onUpdateChanged() {
    if (!mounted) return;
    if (!widget.update.isDownloading && widget.update.errorMessage == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDismiss();
      });
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final error = widget.update.errorMessage;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          _Notice(text: error),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (widget.forceUpdate && widget.retry != null)
                  MiuixButton(
                    onPressed: () {
                      widget.update.clearError();
                      widget.retry!();
                    },
                    colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                    child: MiuixText('重试', style: theme.textStyles.button),
                  )
                else ...[
                  if (widget.retry != null)
                    MiuixTextButton(
                      '重试',
                      onPressed: () {
                        widget.update.clearError();
                        widget.retry!();
                      },
                    ),
                  MiuixTextButton(
                    '关闭',
                    onPressed: () {
                      widget.update.clearError();
                      widget.onDismiss();
                    },
                  ),
                ],
              ],
            ),
          ),
        ] else
          // 进度走独立 ValueListenable：它每 200ms 一跳，不该带着整个弹窗
          // （连同外层监听 controller 的部分）一起重建。
          ValueListenableBuilder<double>(
            valueListenable: widget.update.progressListenable,
            builder: (context, progress, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  progress > 0 ? '正在下载更新包…' : '正在准备下载…',
                  style: theme.textStyles.body2.copyWith(
                    color: theme.colors.onSurfaceContainer,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    // 服务端没给 Content-Length 时进度恒为 0，显示不确定态
                    // 比一条永远不动的进度条诚实。
                    value: progress > 0 ? progress : null,
                    minHeight: 6,
                    backgroundColor: theme.colors.surfaceContainerHigh,
                    color: theme.colors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  progress > 0
                      ? '${(progress * 100).toStringAsFixed(1)}%'
                      : '请保持网络连接',
                  style: theme.textStyles.body2.copyWith(
                    color: theme.colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 警示条：强制更新提示与错误信息共用。
class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: theme.textStyles.body2.copyWith(color: theme.colors.primary),
      ),
    );
  }
}
