import 'dart:async';
import 'dart:io';

import 'package:cyrene_music_reborn/application/updates/update_controller.dart';
import 'package:cyrene_music_reborn/domain/models/app_update.dart';
import 'package:cyrene_music_reborn/domain/updates/update_installer.dart';
import 'package:cyrene_music_reborn/infrastructure/services/update_downloader.dart';
import 'package:cyrene_music_reborn/infrastructure/storage/update_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late FakeInstaller installer;
  late FakeDownloader downloader;
  late UpdateController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    installer = FakeInstaller();
    downloader = FakeDownloader();
    controller = UpdateController(
      downloader: downloader,
      preferences: UpdatePreferences(
        preferences: await SharedPreferences.getInstance(),
      ),
      installer: installer,
    );
  });

  tearDown(() => controller.dispose());

  group('shouldPrompt', () {
    test('默认提示新版本', () async {
      expect(await controller.shouldPrompt(_info('2.0.1')), isTrue);
    });

    test('「稍后提醒」后本次启动内不再提示', () async {
      controller.remindLater('2.0.1');

      expect(await controller.shouldPrompt(_info('2.0.1')), isFalse);
      // 只压住这一个版本，更高的版本照常提示。
      expect(await controller.shouldPrompt(_info('2.0.2')), isTrue);
    });

    test('「忽略此版本」压住该版本及更低版本', () async {
      await controller.ignoreVersion('2.0.5');

      expect(await controller.shouldPrompt(_info('2.0.5')), isFalse);
      expect(await controller.shouldPrompt(_info('2.0.4')), isFalse);
      expect(await controller.shouldPrompt(_info('2.0.6')), isTrue);
    });

    test('强制更新无视忽略与稍后提醒', () async {
      await controller.ignoreVersion('2.0.5');
      controller.remindLater('2.0.5');

      expect(
        await controller.shouldPrompt(_info('2.0.5', forceUpdate: true)),
        isTrue,
      );
    });

    test('维护公告始终提示', () async {
      controller.remindLater('9.9.9');

      expect(
        await controller.shouldPrompt(_info('9.9.9', fixing: true)),
        isTrue,
      );
    });
  });

  group('startUpdate', () {
    test('下载成功后交给安装器', () async {
      await controller.startUpdate(
        _info('2.0.1', downloadUrl: 'https://music.test/a.apk'),
      );

      expect(downloader.requestedUrls, ['https://music.test/a.apk']);
      expect(installer.installed, hasLength(1));
      expect(controller.errorMessage, isNull);
      expect(controller.isDownloading, isFalse);
    });

    test('进度只经独立通知广播，不触发主通知', () async {
      var mainNotifications = 0;
      final progressValues = <double>[];
      controller.addListener(() => mainNotifications += 1);
      controller.progressListenable.addListener(
        () => progressValues.add(controller.progressListenable.value),
      );
      downloader.progressSteps = const [0.25, 0.5, 0.75];

      await controller.startUpdate(
        _info('2.0.1', downloadUrl: 'https://music.test/a.apk'),
      );

      expect(progressValues, containsAll(<double>[0.25, 0.5, 0.75]));
      // 主通知只该来自结构性变化（开始下载 / 结束），与进度回调次数无关。
      // 否则整棵监听 controller 的树会跟着进度条每跳一次重建。
      expect(mainNotifications, lessThanOrEqualTo(3));
    });

    test('没有当前平台的下载地址时给出错误', () async {
      await controller.startUpdate(_info('2.0.1'));

      expect(controller.errorMessage, contains('下载地址'));
      expect(downloader.requestedUrls, isEmpty);
      expect(installer.installed, isEmpty);
    });

    test('下载失败落到 errorMessage 并复位下载态', () async {
      downloader.failure = const UpdateDownloadFailure('下载超时，请重试');

      await controller.startUpdate(
        _info('2.0.1', downloadUrl: 'https://music.test/a.apk'),
      );

      expect(controller.errorMessage, '下载超时，请重试');
      expect(controller.isDownloading, isFalse);
      expect(installer.installed, isEmpty);
    });

    test('安装失败落到 errorMessage', () async {
      installer.failure = const UpdateInstallFailure('需要授予「安装未知应用」权限才能更新');

      await controller.startUpdate(
        _info('2.0.1', downloadUrl: 'https://music.test/a.apk'),
      );

      expect(controller.errorMessage, contains('安装未知应用'));
      expect(controller.isDownloading, isFalse);
    });

    test('平台不支持应用内更新时不下载', () async {
      installer.supported = false;

      await controller.startUpdate(
        _info('2.0.1', downloadUrl: 'https://music.test/a.apk'),
      );

      expect(controller.errorMessage, contains('不支持'));
      expect(downloader.requestedUrls, isEmpty);
    });

    test('下载进行中时重复触发不会叠加', () async {
      downloader.gate = Completer<void>();
      final first = controller.startUpdate(
        _info('2.0.1', downloadUrl: 'https://music.test/a.apk'),
      );
      await controller.startUpdate(
        _info('2.0.1', downloadUrl: 'https://music.test/a.apk'),
      );
      downloader.gate!.complete();
      await first;

      expect(downloader.requestedUrls, hasLength(1));
    });
  });

  test('clearError 复位错误态', () async {
    downloader.failure = const UpdateDownloadFailure('下载超时，请重试');
    await controller.startUpdate(
      _info('2.0.1', downloadUrl: 'https://music.test/a.apk'),
    );

    controller.clearError();

    expect(controller.errorMessage, isNull);
  });
}

UpdateInfo _info(
  String version, {
  bool forceUpdate = false,
  bool fixing = false,
  String? downloadUrl,
}) => UpdateInfo(
  version: version,
  changelog: '更新说明',
  forceUpdate: forceUpdate,
  fixing: fixing,
  downloadUrl: downloadUrl,
);

class FakeInstaller implements UpdateInstaller {
  final installed = <File>[];
  bool supported = true;
  UpdateInstallFailure? failure;

  @override
  bool get isSupported => supported;

  @override
  Future<void> install(File package) async {
    if (failure != null) throw failure!;
    installed.add(package);
  }
}

class FakeDownloader implements UpdateDownloader {
  final requestedUrls = <String>[];
  List<double> progressSteps = const [];
  UpdateDownloadFailure? failure;

  /// 用来把下载「悬停」在中途，测试重入保护。
  Completer<void>? gate;

  @override
  Future<File> download(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    requestedUrls.add(url);
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    for (final step in progressSteps) {
      onProgress?.call(step);
    }
    return File('update.apk');
  }

  @override
  Future<Directory> resolveDownloadDirectory() async => Directory.current;
}
