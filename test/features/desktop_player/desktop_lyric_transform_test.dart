import 'dart:math' as math;

import 'package:cyrene_music_reborn/application/stores/fullscreen_settings_store.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/features/desktop_player/desktop_player_playback.dart';
import 'package:cyrene_music_reborn/features/desktop_player/desktop_player_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 桌面歌词编辑模式的变换逻辑。
///
/// 核心约束：仅「经典 / 像素 / 对话」样式受用户变换影响，「默认」样式必须
/// 保持原样、不套用户变换（它自带精心设计的逐行逐字排版）。
void main() {
  final settings = FullscreenSettingsStore.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 构造一个带 currentTrack 的 desktop playback。
  ///
  /// 直接经 controller.playTrack 注入曲目：_RemoteAudioGateway 的 load 是空实现、
  /// 且无 sourceResolver，playTrack 会把曲目 publish 成 currentTrack 而不真的发声。
  Future<DesktopPlayerPlayback> playbackWithTrack() async {
    final playback = DesktopPlayerPlayback();
    await playback.controller.playTrack(
      const Track(
        id: '1',
        name: '晴天',
        artists: '周杰伦',
        album: '叶惠美',
        picUrl: '',
        source: MusicSource.netease,
      ),
      queue: const [],
    );
    return playback;
  }

  // —— 纯 store 单元测试 ——

  test('六个变换字段默认值正确', () {
    expect(settings.desktopLyricOffsetX, 0);
    expect(settings.desktopLyricOffsetY, 0);
    expect(settings.desktopLyricScale, 1);
    expect(settings.desktopLyricRotX, 0);
    expect(settings.desktopLyricRotY, 0);
    expect(settings.desktopLyricRotZ, 0);
    expect(settings.desktopLyricTransformIsDefault, isTrue);
  });

  test('resetDesktopLyricTransform 一次性清零全部参数', () {
    settings.setDesktopLyricOffset(120, -80);
    settings.setDesktopLyricScale(1.5);
    settings.setDesktopLyricRotZ(math.pi / 6);
    expect(settings.desktopLyricTransformIsDefault, isFalse);

    settings.resetDesktopLyricTransform();

    expect(settings.desktopLyricOffsetX, 0);
    expect(settings.desktopLyricOffsetY, 0);
    expect(settings.desktopLyricScale, 1);
    expect(settings.desktopLyricRotX, 0);
    expect(settings.desktopLyricRotY, 0);
    expect(settings.desktopLyricRotZ, 0);
    expect(settings.desktopLyricTransformIsDefault, isTrue);
  });

  test('缩放与旋转写入后被爬取并夹紧到合法区间', () {
    settings.setDesktopLyricScale(1.25);
    settings.setDesktopLyricRotX(0.4);
    expect(settings.desktopLyricScale, 1.25);
    expect(settings.desktopLyricRotX, 0.4);

    settings.setDesktopLyricScale(99);
    expect(settings.desktopLyricScale, FullscreenSettingsStore.maxDesktopLyricScale);
    settings.setDesktopLyricRotX(99);
    expect(
      settings.desktopLyricRotX,
      FullscreenSettingsStore.maxDesktopLyricRotation,
    );
    settings.setDesktopLyricRotZ(-99);
    expect(
      settings.desktopLyricRotZ,
      -FullscreenSettingsStore.maxDesktopLyricRotation,
    );
  });

  test('持久化往返：写入后重新 init 从 SharedPreferences 读回', () async {
    settings.setDesktopLyricOffset(30, -20);
    settings.setDesktopLyricScale(1.4);
    settings.setDesktopLyricRotY(0.3);

    await settings.init();

    expect(settings.desktopLyricOffsetX, 30);
    expect(settings.desktopLyricOffsetY, -20);
    expect(settings.desktopLyricScale, 1.4);
    expect(settings.desktopLyricRotY, 0.3);
  });

  // —— widget 测试：验证「默认」不套变换、「经典」套 ——

  /// 是否存在把 [offsetX] 作为平移量的 Transform 组件。
  ///
  /// Matrix4 是列主序，平移在 storage[12]/[13]；后续的旋转/缩放都是右乘，
  /// 不会改动平移列，因此可以直接用相等值匹配。
  bool hasTransformWithOffset(WidgetTester tester, double offsetX) {
    for (final t in tester.widgetList<Transform>(find.byType(Transform))) {
      final s = t.transform.storage;
      if ((s[12] - offsetX).abs() < 0.01) return true;
    }
    return false;
  }

  testWidgets('默认样式：改变变换参数不产生用户变换层', (tester) async {
    final playback = await playbackWithTrack();
    addTearDown(playback.dispose);

    // 默认样式：superCyrene 开 + theme=default。
    settings.setSuperCyrenePlayerEnabled(true);
    settings.setSuperCyreneLyricsTheme('default');

    await tester.pumpWidget(
      MaterialApp(home: DesktopPlayerView(playback: playback)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    // 先记录默认样式下偏移为 0 的 Transform 数量。
    final baseline = tester
        .widgetList<Transform>(find.byType(Transform))
        .length;

    // 故意把偏移改到非默认，验证默认样式确实不受影响。
    settings.setDesktopLyricOffset(200, 100);
    settings.setDesktopLyricScale(1.8);
    await tester.pump();

    // 默认样式下绝不能出现带用户偏移的 Transform。
    expect(hasTransformWithOffset(tester, 200), isFalse);
    // 且 Transform 数量不变——偏移没有给歌词多加一层。
    expect(
      tester.widgetList<Transform>(find.byType(Transform)).length,
      baseline,
    );
  });

  testWidgets('经典样式：改变偏移产生用户变换层', (tester) async {
    final playback = await playbackWithTrack();
    addTearDown(playback.dispose);

    // 经典样式：superCyrene 关。
    settings.setSuperCyrenePlayerEnabled(false);

    await tester.pumpWidget(
      MaterialApp(home: DesktopPlayerView(playback: playback)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    settings.setDesktopLyricOffset(200, 100);
    await tester.pump();

    // 经典样式下，歌词被带用户偏移的 Transform 包裹。
    expect(hasTransformWithOffset(tester, 200), isTrue);
  });
}

// 注：DesktopPlayerPlayback 的 dispose 会关网关流；controller.playTrack 依赖
// _RemoteAudioGateway 的空实现 load，不会真拉音频，widget 测试安全。