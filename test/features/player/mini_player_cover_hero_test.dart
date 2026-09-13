/// 迷你播放器封面上的共享元素标签。
///
/// 展开态和折叠态两棵子树在 AnimatedCrossFade 里是**同时挂着**的，两边都打
/// tag 的话，一起飞就会撞上「multiple heroes that share the same tag」断言、
/// 直接崩在进播放器那一下。所以标签只能给当下可见的那一份——这个测试守的就是
/// 「任何时刻场上只有一个」。
library;

import 'dart:async';

import 'package:cyrene_music_reborn/app/app_dependencies.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/features/player/mini_player.dart';
import 'package:cyrene_music_reborn/features/player/mini_player_expand_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixThemeController;
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _track = Track(
  id: '1',
  name: '测试曲目',
  artists: '测试歌手',
  album: '测试专辑',
  picUrl: '',
  source: MusicSource.netease,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('展开态与折叠态加起来只有一个封面 Hero', (tester) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 不 dispose：playTrack 是没 await 的，收尾时再去动已 dispose 的控制器会
    // 撞断言（同 mini_player_placement_test 的处理）。
    final dependencies = AppDependencies.preview();
    unawaited(dependencies.playback.playTrack(_track));

    await tester.pumpWidget(
      LiquidGlassWidgets.wrap(
        child: MiuixThemeController(
          child: MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 104,
                    child: MiniPlayer(
                      playback: dependencies.playback,
                      audioSources: dependencies.audioSources,
                      account: dependencies.account,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MiniPlayer), findsOneWidget, reason: '前置条件：有歌在放');
    expect(_coverHeroes(tester), 1, reason: '展开态：只有展开那份挂 tag');

    // 闲置 5 秒自动折叠，tag 要跟着搬到折叠态那份，而不是两份都有。
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_coverHeroes(tester), 1, reason: '折叠后：只有折叠那份挂 tag');
  });
}

int _coverHeroes(WidgetTester tester) => tester
    .widgetList<Hero>(find.byType(Hero))
    .where((hero) => hero.tag == kPlayerCoverHeroTag)
    .length;
