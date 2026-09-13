/// 迷你播放器 →/← 全屏播放器的展开/收起动画。
///
/// 守两条线：
/// 1. **窗口**要从迷你播放器的矩形长到整屏（返回时反过来），中途必须处在两者
///    之间——不是「瞬间铺满 + 淡入」。
/// 2. **封面**要真的位移并放大：飞行途中它既不在起点也不在终点，尺寸和位置都
///    在两端之间。这条是需求的核心，别的元素怎么进场都行，封面必须飞。
/// 3. **圆角**飞行途中要有整机弧度那么圆（曾经是 20 → 0 直插，窗口刚长到一半
///    圆角就只剩个位数，看着通篇直角），静止态又必须收平成 0，免得在圆角比估
///    算值小的设备上四角露出底下的外壳。
library;

import 'package:cyrene_music_reborn/features/player/mini_player_expand_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sourceCoverKey = ValueKey('source-cover');
const _destCoverKey = ValueKey('destination-cover');

/// 全屏页里大封面的最终位置，跟流体云布局一样是「靠上、接近满宽」。
const _destCoverRect = Rect.fromLTWH(40, 96, 320, 320);

void main() {
  testWidgets('展开：窗口从迷你播放器长到整屏，封面同步位移放大', (tester) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final navigatorKey = GlobalKey<NavigatorState>();
    final anchorKey = GlobalKey();
    await tester.pumpWidget(_harness(navigatorKey, anchorKey));

    final panel = tester.getRect(find.byKey(anchorKey));
    final miniCover = tester.getRect(find.byKey(_sourceCoverKey));
    expect(panel.size, const Size(368, 68), reason: '前置条件：起点面板是底部那条');
    expect(miniCover.size, const Size(48, 48));

    await tester.tap(find.text('打开'));
    // 第一帧推路由并把目标路由 offstage 量一遍（Hero 靠这帧确定落点），
    // 第二帧起飞行才真正开始。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    final window = tester.getRect(find.byKey(miniPlayerExpandWindowKey));
    expect(window.width, greaterThan(panel.width));
    expect(window.width, lessThan(400));
    expect(window.height, greaterThan(panel.height));
    expect(window.height, lessThan(800));

    // 飞行中的封面：Hero 把目标那份换成占位、把实体搬到 overlay，
    // 所以此刻 _destCoverKey 命中的就是正在飞的那个。
    final flying = tester.getRect(find.byKey(_destCoverKey));
    expect(flying.width, greaterThan(miniCover.width), reason: '封面要放大');
    expect(flying.width, lessThan(_destCoverRect.width));
    expect(flying.top, lessThan(miniCover.top), reason: '封面要往上位移');
    expect(flying.top, greaterThan(_destCoverRect.top));

    // 圆角：飞行途中要接近整机弧度，不是残留的个位数。
    final phoneRadius = screenCornerRadiusFor(const Size(400, 800));
    expect(phoneRadius, greaterThan(40), reason: '前置条件：估出来的整机弧度够圆');
    expect(_windowRadius(tester), closeTo(phoneRadius, 0.01));

    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(miniPlayerExpandWindowKey)),
      const Rect.fromLTWH(0, 0, 400, 800),
    );
    expect(tester.getRect(find.byKey(_destCoverKey)), _destCoverRect);
    expect(_windowRadius(tester), 0, reason: '静止态收平，四角不许露出外壳');
  });

  testWidgets('圆角全程不塌：从迷你面板的 20 涨到整机弧度，只在贴屏那下收平', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final navigatorKey = GlobalKey<NavigatorState>();
    final anchorKey = GlobalKey();
    await tester.pumpWidget(_harness(navigatorKey, anchorKey));

    final phoneRadius = screenCornerRadiusFor(const Size(400, 800));

    await tester.tap(find.text('打开'));
    // 第一帧目标路由是 offstage 的（Hero 量落点用），量不到也不该量：那帧的
    // 路由动画被强制视为已完成。第二帧（还没走时间）才是真正的 t=0。
    await tester.pump();
    await tester.pump(Duration.zero);
    expect(_windowRadius(tester), closeTo(20, 0.01), reason: '起手是迷你面板的圆角');

    // 逐帧扫过整段动画：只要窗口还没贴到屏幕边，圆角就不该掉回「看着像直角」
    // 的水平——老实现是 20 → 0 直插，窗口长到一半时只剩 10 出头。
    var sawPhoneRadius = false;
    for (var elapsed = 0; elapsed < 520; elapsed += 20) {
      await tester.pump(const Duration(milliseconds: 20));
      final radius = _windowRadius(tester);
      final window = tester.getRect(find.byKey(miniPlayerExpandWindowKey));
      if (window.height < 720) {
        expect(
          radius,
          greaterThanOrEqualTo(20),
          reason: '窗口 $window 时圆角塌到了 $radius',
        );
      }
      if ((radius - phoneRadius).abs() < 0.01) sawPhoneRadius = true;
    }
    expect(sawPhoneRadius, isTrue, reason: '中途要真的涨到整机弧度');

    await tester.pumpAndSettle();
    expect(_windowRadius(tester), 0);
  });

  testWidgets('收起：窗口缩回迷你播放器，封面原路飞回', (tester) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final navigatorKey = GlobalKey<NavigatorState>();
    final anchorKey = GlobalKey();
    await tester.pumpWidget(_harness(navigatorKey, anchorKey));

    final miniCover = tester.getRect(find.byKey(_sourceCoverKey));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    navigatorKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    final window = tester.getRect(find.byKey(miniPlayerExpandWindowKey));
    expect(window.width, lessThan(400));
    expect(window.height, lessThan(800));

    // 回程 Hero 用的是「目标」——也就是迷你播放器那份——的 child 当飞行帧。
    final flying = tester.getRect(find.byKey(_sourceCoverKey));
    expect(flying.width, greaterThan(miniCover.width));
    expect(flying.width, lessThan(_destCoverRect.width));
    expect(flying.top, lessThan(miniCover.top));

    await tester.pumpAndSettle();
    expect(find.byKey(_destCoverKey), findsNothing);
    expect(tester.getRect(find.byKey(_sourceCoverKey)), miniCover);
  });

  testWidgets('迷你播放器不在场时退化为屏幕底部的兜底起点，不崩', (tester) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MiniPlayerExpandRoute<void>(
                  originRect: () => null,
                  builder: (_) => const _FakeFullscreenPlayer(),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    final window = tester.getRect(find.byKey(miniPlayerExpandWindowKey));
    expect(window.width, greaterThan(368));
    expect(window.width, lessThan(400));

    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(miniPlayerExpandWindowKey)),
      const Rect.fromLTWH(0, 0, 400, 800),
    );
  });
}

/// 当前裁剪窗的左上角圆角半径。
double _windowRadius(WidgetTester tester) => tester
    .widget<ClipRSuperellipse>(find.byKey(miniPlayerExpandWindowKey))
    .borderRadius
    .resolve(TextDirection.ltr)
    .topLeft
    .x;

/// 底部一条 368×68 的「迷你播放器」+ 一个入口按钮。
Widget _harness(GlobalKey<NavigatorState> navigatorKey, GlobalKey anchorKey) =>
    MaterialApp(
      navigatorKey: navigatorKey,
      home: Scaffold(
        body: Stack(
          children: [
            Center(
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MiniPlayerExpandRoute<void>(
                      originRect: () => globalRectOfKey(anchorKey),
                      builder: (_) => const _FakeFullscreenPlayer(),
                    ),
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 104,
              child: SizedBox(
                key: anchorKey,
                height: 68,
                child: const Padding(
                  padding: EdgeInsets.only(left: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Hero(
                      tag: kPlayerCoverHeroTag,
                      child: SizedBox(
                        key: _sourceCoverKey,
                        width: 48,
                        height: 48,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

class _FakeFullscreenPlayer extends StatelessWidget {
  const _FakeFullscreenPlayer();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF101010),
    child: Stack(
      children: [
        Positioned(
          left: _destCoverRect.left,
          top: _destCoverRect.top,
          width: _destCoverRect.width,
          height: _destCoverRect.height,
          child: const Hero(
            tag: kPlayerCoverHeroTag,
            child: SizedBox(key: _destCoverKey),
          ),
        ),
      ],
    ),
  );
}
