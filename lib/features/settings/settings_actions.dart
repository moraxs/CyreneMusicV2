/// 设置里那几个「点一下就弹个东西」的动作。
///
/// 抽出来是因为移动端的 [SettingsPage] 与桌面端的合并设置页都要用；留在各自
/// 页面里就是两份会分叉的弹窗代码。
library;

import 'package:flutter/material.dart';

import '../../application/announcements/announcement_controller.dart';
import '../../application/updates/update_controller.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
import '../announcements/announcement_dialog.dart';
import '../updates/update_dialogs.dart';

/// 查看服务端公告（设置页里的手动入口）。
///
/// 与启动自动弹窗共用同一个弹窗组件，区别是不给「不再提示」勾选框，也不看
/// 水位线——用户主动点进来的，哪怕早就勾过「不再提示」也照样给他看。
Future<void> openAnnouncement(BuildContext context) async {
  final announcement = await AnnouncementController.instance.fetch();
  if (!context.mounted) return;
  if (announcement == null || !announcement.enabled) {
    CyreneToast.show('暂无公告');
    return;
  }
  await showAnnouncementDialog(context, announcement);
}

/// 手动检查更新：有新版则走与启动检查同一套弹窗（下载 + 安装）。
///
/// 与启动检查的区别是不走 `shouldPrompt` —— 用户主动点的，即使之前忽略过
/// 这个版本也该给出结果。
Future<void> checkUpdateInteractively(BuildContext context) async {
  CyreneToast.show('正在检查更新…');
  final update = UpdateController.instance;
  final info = await update.check(silent: false);
  if (!context.mounted) return;
  if (info == null) {
    CyreneToast.show(update.errorMessage ?? '当前已是最新版本');
    update.clearError();
    return;
  }
  await showUpdateDialog(context, info);
}
