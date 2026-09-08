import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/stores/together_settings_store.dart';
import '../../application/together/together_controller.dart';
import '../../domain/together/together_models.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
import '../together/together_lobby_page.dart';
import '../together/together_members_page.dart';
import 'settings_body.dart';

/// 「一起听」设置页：总开关、房间可见性、弹幕，以及当前房间信息。
class TogetherSettingsPage extends StatelessWidget {
  const TogetherSettingsPage({super.key, this.onOpenSecondary});

  /// 桌面端二级页在右侧栏打开（与设置主页同一套约定）。
  final ValueChanged<Widget>? onOpenSecondary;

  @override
  Widget build(BuildContext context) => CyrenePage(
    title: '一起听',
    bodyBuilder: (context, topPadding) => TogetherSettingsBody(
      topPadding: topPadding,
      onOpenSecondary: onOpenSecondary,
    ),
  );
}

/// 「一起听」设置正文，不含页面骨架。
///
/// 独立成组件是为了让桌面端的合并设置页（`desktop/desktop_settings_page.dart`）
/// 直接嵌这一份，而不是照抄一遍开关逻辑——两处各写一份必然随时间分叉。
class TogetherSettingsBody extends StatelessWidget {
  const TogetherSettingsBody({
    super.key,
    this.topPadding = EdgeInsets.zero,
    this.embedded = false,
    this.onOpenSecondary,
  });

  final EdgeInsets topPadding;
  final bool embedded;
  final ValueChanged<Widget>? onOpenSecondary;

  @override
  Widget build(BuildContext context) {
    final settings = TogetherSettingsStore.instance;
    final together = TogetherController.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([settings, together]),
      builder: (context, _) => SettingsBody(
        topPadding: topPadding,
        embedded: embedded,
        children: [
          CyreneMenuGroup(
            children: [
              CyreneMenuRow(
                key: const Key('toggle-together'),
                vector: MiuixIcons.extended.byName('community')!,
                iconBackground: const Color(0xFFFF375F),
                title: '开启一起听',
                subtitle: '开启后立刻生成房间号，朋友能同步听到你在听什么',
                trailing: MiuixSwitch(
                  value: settings.enabled,
                  onChanged: (value) => _setEnabled(value),
                ),
                onTap: () => _setEnabled(!settings.enabled),
              ),
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('lock')!,
                iconBackground: const Color(0xFF8A64FF),
                title: '私有房间',
                subtitle: settings.isPrivate
                    ? '不出现在大厅，只有拿到房间号的人能进'
                    : '任何人都能在大厅里找到并加入',
                trailing: MiuixSwitch(
                  value: settings.isPrivate,
                  onChanged: settings.setPrivate,
                ),
                onTap: () => settings.setPrivate(!settings.isPrivate),
              ),
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('playlist')!,
                iconBackground: const Color(0xFF00B0A0),
                title: '允许听众点歌',
                subtitle: settings.allowGuestControl
                    ? '房里的人可以换当前播放的歌，你这边跟着一起换'
                    : '只有你能决定放什么，听众只能听',
                trailing: MiuixSwitch(
                  value: settings.allowGuestControl,
                  onChanged: settings.setAllowGuestControl,
                ),
                onTap: () =>
                    settings.setAllowGuestControl(!settings.allowGuestControl),
              ),
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('messages')!,
                iconBackground: const Color(0xFF3482FF),
                title: '显示弹幕',
                subtitle: '在播放器上飘过房间里的发言',
                trailing: MiuixSwitch(
                  value: settings.danmakuVisible,
                  onChanged: settings.setDanmakuVisible,
                ),
                onTap: () =>
                    settings.setDanmakuVisible(!settings.danmakuVisible),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CyreneInlineAlert(
            vector: MiuixIcons.extended.byName('info')!,
            description:
                '房间里同步的只是「在听哪首歌、放到哪儿了」，音频由每台设备用自己的'
                '音源各自获取——所以你的音源和音质不会外传，听众没有对应音源时也'
                '不会把整个房间卡住。切换公开/私有对当前房间即时生效，房间号和'
                '房里的人都不变。',
          ),
          if (together.connection == TogetherConnection.connecting) ...[
            const SizedBox(height: 12),
            CyreneMenuGroup(
              children: [
                CyreneMenuRow(
                  vector: MiuixIcons.extended.byName('community')!,
                  iconBackground: const Color(0xFF3CC756),
                  title: '正在开房…',
                  subtitle: '正在连接一起听服务',
                  trailing: const MiuixCircularProgressIndicator(
                    size: 18,
                    strokeWidth: 2,
                  ),
                ),
              ],
            ),
          ],
          if (together.isActive) ...[
            const SizedBox(height: 12),
            const MiuixSmallTitle(
              '当前房间',
              insideMargin: EdgeInsets.fromLTRB(16, 4, 16, 8),
            ),
            CyreneMenuGroup(
              children: [
                CyreneMenuRow(
                  vector: MiuixIcons.extended.byName('copy')!,
                  iconBackground: const Color(0xFF3CC756),
                  title: '房间号',
                  subtitle: together.isHost ? '我是房主' : '正在跟随房主播放',
                  value: together.roomCode ?? '------',
                  onTap: () {
                    final code = together.roomCode;
                    if (code == null) return;
                    Clipboard.setData(ClipboardData(text: code));
                    CyreneToast.show('房间号已复制：$code');
                  },
                ),
                CyreneMenuRow(
                  vector: MiuixIcons.extended.byName('contacts')!,
                  iconBackground: const Color(0xFFFF9F0A),
                  title: '房间成员',
                  subtitle: together.isHost ? '可以把人移出房间' : '看看谁在一起听',
                  value: '${together.listeners} 人',
                  onTap: () => _openPage(context, const TogetherMembersPage()),
                ),
                CyreneMenuRow(
                  vector: MiuixIcons.extended.byName('close')!,
                  iconBackground: const Color(0xFF5F6368),
                  title: together.isHost ? '结束一起听' : '退出房间',
                  destructive: true,
                  onTap: () {
                    final wasHost = together.isHost;
                    together.leave();
                    CyreneToast.show(wasHost ? '已结束一起听' : '已退出房间');
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          CyreneMenuGroup(
            children: [
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('community')!,
                iconBackground: const Color(0xFF3482FF),
                title: '一起听大厅',
                subtitle: '看看别人在听什么，或凭房间号加入',
                onTap: () => _openLobby(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _setEnabled(bool value) async {
    await TogetherSettingsStore.instance.setEnabled(value);
    if (!value) {
      // 关掉开关就把房间收了，免得留着一个没人管的房间在大厅里。
      await TogetherController.instance.leave();
      return;
    }
    // 开关一开就把房间开出来：房间号是拿来发给朋友的，不能等到下一次切歌/
    // 暂停触发播放状态变化时才生成（那之前这一页是空的，看着像坏了）。
    // 没在放歌也照开——房间可以先建着等人，曲目为空时大厅显示「还没开始播放」。
    final together = TogetherController.instance;
    if (together.isActive) return;
    final ok = await together.host();
    if (!ok) {
      CyreneToast.show(together.errorMessage ?? '开房失败，请稍后再试');
    }
  }

  void _openLobby(BuildContext context) =>
      _openPage(context, const TogetherLobbyPage());

  /// 桌面端二级页走右侧栏，移动端照常入栈。
  void _openPage(BuildContext context, Widget page) {
    final openSecondary = onOpenSecondary;
    if (openSecondary != null) {
      openSecondary(page);
      return;
    }
    Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => page));
  }
}
