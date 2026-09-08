import 'package:cyrene_music_reborn/application/announcements/announcement_controller.dart';
import 'package:cyrene_music_reborn/domain/models/announcement.dart';
import 'package:cyrene_music_reborn/infrastructure/storage/announcement_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AnnouncementPreferences preferences;
  late AnnouncementController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    preferences = AnnouncementPreferences(
      preferences: await SharedPreferences.getInstance(),
    );
    controller = AnnouncementController(preferences: preferences);
  });

  tearDown(() => controller.dispose());

  group('shouldPrompt', () {
    test('从未勾过「不再提示」时照常弹', () async {
      expect(await controller.shouldPrompt(_of('announcement_2026_007')), isTrue);
    });

    test('勾过之后同一条不再弹', () async {
      await controller.dismissUntilNewer('announcement_2026_007');

      expect(await controller.shouldPrompt(_of('announcement_2026_007')), isFalse);
    });

    test('编号变大后重新弹', () async {
      await controller.dismissUntilNewer('announcement_2026_007');

      expect(await controller.shouldPrompt(_of('announcement_2026_008')), isTrue);
      expect(await controller.shouldPrompt(_of('announcement_2026_010')), isTrue);
    });

    test('编号更小的旧公告不会倒回来弹', () async {
      await controller.dismissUntilNewer('announcement_2026_007');

      expect(await controller.shouldPrompt(_of('announcement_2026_006')), isFalse);
    });

    test('跨年编号重新从 001 开始也算更新', () async {
      await controller.dismissUntilNewer('announcement_2026_099');

      expect(await controller.shouldPrompt(_of('announcement_2027_001')), isTrue);
    });

    test('后端关掉公告或关掉自动弹窗时不弹', () async {
      expect(
        await controller.shouldPrompt(
          _of('announcement_2026_008', enabled: false),
        ),
        isFalse,
      );
      expect(
        await controller.shouldPrompt(
          _of('announcement_2026_008', popup: false),
        ),
        isFalse,
      );
    });

    test('缺 id 或缺正文的公告不参与自动弹窗', () async {
      expect(await controller.shouldPrompt(_of('')), isFalse);
      expect(
        await controller.shouldPrompt(_of('announcement_2026_008', content: '')),
        isFalse,
      );
    });

    test('resetDismissed 后重新参与弹窗', () async {
      await controller.dismissUntilNewer('announcement_2026_007');
      await controller.resetDismissed();

      expect(await controller.shouldPrompt(_of('announcement_2026_007')), isTrue);
    });
  });

  group('compareAnnouncementIds', () {
    test('按数字段逐位比较，不做字符串比较', () async {
      // 字符串比较会得出 '..._010' < '..._007'（'1' < '7'），必须按数值比。
      expect(
        compareAnnouncementIds('announcement_2026_010', 'announcement_2026_007'),
        greaterThan(0),
      );
    });

    test('相同编号返回 0', () {
      expect(
        compareAnnouncementIds('announcement_2026_007', 'announcement_2026_007'),
        0,
      );
    });

    test('前缀不参与比较', () {
      expect(compareAnnouncementIds('notice_2026_007', 'announcement_2026_007'), 0);
    });

    test('无数字的 id 退化为字符串比较，不抛异常', () {
      expect(compareAnnouncementIds('beta', 'alpha'), greaterThan(0));
      expect(compareAnnouncementIds('alpha', 'beta'), lessThan(0));
      expect(compareAnnouncementIds('alpha', 'alpha'), 0);
    });

    test('一侧有编号一侧没有时，有编号的算新', () {
      expect(compareAnnouncementIds('announcement_2026_007', 'legacy'), greaterThan(0));
      expect(compareAnnouncementIds('legacy', 'announcement_2026_007'), lessThan(0));
    });
  });

  test('dismissUntilNewer 落到持久化，跨实例仍然生效', () async {
    await controller.dismissUntilNewer('announcement_2026_007');

    // 模拟重启：用同一份 SharedPreferences 重建 controller。
    final revived = AnnouncementController(preferences: preferences);
    addTearDown(revived.dispose);

    expect(await revived.shouldPrompt(_of('announcement_2026_007')), isFalse);
    expect(await revived.shouldPrompt(_of('announcement_2026_008')), isTrue);
  });
}

Announcement _of(
  String id, {
  bool enabled = true,
  bool popup = true,
  String content = '公告正文',
}) => Announcement(
  enabled: enabled,
  id: id,
  title: '公告标题',
  content: content,
  popup: popup,
);
