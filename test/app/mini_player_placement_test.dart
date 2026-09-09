/// 迷你播放器的层级回归测试。
///
/// 它曾被提到 Navigator **之上**（为了让二级页也盖不住它），副作用是连
/// AppGate 的启动过渡页和首启引导页都被压住——那两个页面属于「还没进主界面」
/// 的阶段，本就不该出现播放器。修复是把它放回外壳、与底部标签栏同层。
///
/// 这里守住的就是那条线：**主界面之外不许出现迷你播放器**。
library;

import 'dart:async';

import 'package:cyrene_music_reborn/app/app_dependencies.dart';
import 'package:cyrene_music_reborn/app/music_app_shell.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/features/player/mini_player.dart';
import 'package:cyrene_music_reborn/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

const _track = Track(
  id: '1',
  name: '测试曲目',
  artists: '测试歌手',
  album: '测试专辑',
  picUrl: '',
  source: MusicSource.netease,
);

void main() {
  testWidgets('会话恢复中的过渡页上不出现迷你播放器', (tester) async {
    // 断点 < 900 走移动端布局（桌面端的迷你播放器是 DesktopShell 自带的）。
    tester.view
      ..physicalSize = const Size(420, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 不加 addTearDown(dependencies.dispose)：MyApp 的 State 在拆树时会自己
    // dispose 依赖，再补一次会撞上 ChangeNotifier 的「已 dispose」断言。
    final dependencies = AppDependencies.preview();

    // playTrack 在解析音源之前就先发布曲目，所以不等它完成 currentTrack 也
    // 已非空——正是「有歌在放但还没进主界面」这个会暴露 bug 的状态。
    // preview 走静音网关，解析失败无所谓，这里只要 currentTrack。
    unawaited(dependencies.playback.playTrack(_track));

    await tester.pumpWidget(
      LiquidGlassWidgets.wrap(child: MyApp(dependencies: dependencies)),
    );
    await tester.pump();

    expect(
      dependencies.playback.state.currentTrack,
      isNotNull,
      reason: '前置条件：必须真的有当前曲目，否则这个测试什么都没验证',
    );
    // 账号状态停在 initial（没人调 restore），AppGate 显示过渡页而非主界面。
    expect(find.byType(MusicAppShell), findsNothing);
    expect(find.byType(MiniPlayer), findsNothing);
  });
}
