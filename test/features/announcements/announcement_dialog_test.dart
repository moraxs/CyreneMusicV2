import 'package:cyrene_music_reborn/application/announcements/announcement_controller.dart';
import 'package:cyrene_music_reborn/domain/models/announcement.dart';
import 'package:cyrene_music_reborn/features/announcements/announcement_dialog.dart';
import 'package:cyrene_music_reborn/infrastructure/storage/announcement_preferences.dart';
import 'package:cyrene_music_reborn/presentation/cyrene/cyrene_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 公告弹窗的排版守卫。
///
/// 线上出过：正文很长时「知道了」被挤出弹窗点不到。根因是内容区高度写死 360，
/// 而弹窗内容 Column 从 Miuix 外层 Column 拿到的主轴约束是无界的——矮屏上 360
/// 比可用空间还高，Column 撑爆。所以这里专挑**矮屏 + 超长正文**来跑。
void main() {
  late AnnouncementController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    controller = AnnouncementController(
      preferences: AnnouncementPreferences(
        preferences: await SharedPreferences.getInstance(),
      ),
    );
  });

  tearDown(() => controller.dispose());

  // 覆盖横屏手机 / 横屏平板 / 竖屏手机三档，矮的那两档是回归重点。
  for (final size in const [
    Size(880, 400), // 横屏手机：最矮
    Size(1280, 800), // 横屏平板
    Size(400, 900), // 竖屏手机
  ]) {
    for (final withCheckbox in [false, true]) {
      testWidgets(
        '超长公告不溢出 @ ${size.width}x${size.height}'
        '${withCheckbox ? '（带不再提示）' : ''}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await _pumpDialog(
            tester,
            content: _longContent,
            showDismissOption: withCheckbox,
            controller: controller,
          );

          // 溢出会以 FlutterError 的形式在 pump 时抛出。
          expect(tester.takeException(), isNull);

          // 按钮必须仍在弹窗里，且真的能点到（被挤出去的话 tap 会打空）。
          final button = find.text('知道了');
          expect(button, findsOneWidget);
          final buttonRect = tester.getRect(button);
          expect(
            buttonRect.bottom,
            lessThanOrEqualTo(size.height),
            reason: '「知道了」被挤出了屏幕',
          );
          expect(buttonRect.top, greaterThanOrEqualTo(0));

          if (withCheckbox) {
            expect(find.text('不再提示此公告'), findsOneWidget);
          }
        },
      );
    }
  }

  testWidgets('正文超长时可滚动', (tester) async {
    tester.view.physicalSize = const Size(880, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpDialog(
      tester,
      content: _longContent,
      showDismissOption: true,
      controller: controller,
    );

    final scrollable = find.descendant(
      of: find.byType(SingleChildScrollView),
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);

    final position = tester.state<ScrollableState>(scrollable).position;
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason: '正文放不下时应当可滚动，而不是把按钮顶出去',
    );

    // 真滚一下，确认没有被固定高度锁死。
    await tester.drag(scrollable, const Offset(0, -120));
    await tester.pump();
    expect(position.pixels, greaterThan(0));
  });

  testWidgets('正文很短时弹窗不会被撑到上限高度', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpDialog(
      tester,
      content: '短公告',
      showDismissOption: false,
      controller: controller,
    );

    expect(tester.takeException(), isNull);
    // 上限是 min(360, 屏高/2)=360；短正文该按内容高度收缩，不该顶满。
    final content = tester.getSize(find.byType(SingleChildScrollView));
    expect(content.height, lessThan(100));
  });
}

/// 够长到在任何一档尺寸下都放不下的正文。
final String _longContent = List.generate(
  40,
  (i) => '第 ${i + 1} 行公告内容，这里刻意写得足够长以撑开滚动区域。',
).join('\n');

Future<void> _pumpDialog(
  WidgetTester tester, {
  required String content,
  required bool showDismissOption,
  required AnnouncementController controller,
}) async {
  await tester.pumpWidget(
    MiuixSystemTheme(
      child: Builder(
        builder: (themeContext) => MaterialApp(
          theme: CyreneMiuixTheme.material(MiuixTheme.of(themeContext)),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showAnnouncementDialog(
                    context,
                    Announcement(
                      enabled: true,
                      id: 'announcement_2026_007',
                      title: '请认真看完',
                      content: content,
                    ),
                    showDismissOption: showDismissOption,
                    controller: controller,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  // 弹窗是入场动画驱动的，逐帧推进到稳定态（不用 pumpAndSettle，
  // Miuix 的弹层里有常驻动画）。
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}
