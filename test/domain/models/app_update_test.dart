import 'package:cyrene_music_reborn/domain/models/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解析后端 data 字段', () {
    final info = UpdateInfo.fromJson({
      'version': '2.0.1',
      'changelog': '1. 修复问题\n2. 新增功能',
      'force_update': false,
      'fixing': false,
      'download_url': 'https://music.test/update/2.0.1/2.0.1-full.zip',
      'platform_downloads': {
        'windows': 'https://music.test/update/2.0.1/2.0.1-full.zip',
        'android': 'https://music.test/update/2.0.1/2.0.1-full.apk',
        'mobile': 'https://music.test/update/2.0.1/2.0.1-full.apk',
      },
    });

    expect(info.version, '2.0.1');
    expect(info.changelog, contains('修复问题'));
    expect(info.forceUpdate, isFalse);
    expect(info.fixing, isFalse);
    expect(info.platformDownloads['windows'], endsWith('-full.zip'));
  });

  test('force_update 兼容布尔与字符串', () {
    // 后端 manifest 解析处两种都放行，客户端跟随同样的宽容度。
    expect(UpdateInfo.fromJson({'force_update': true}).forceUpdate, isTrue);
    expect(UpdateInfo.fromJson({'force_update': 'true'}).forceUpdate, isTrue);
    expect(UpdateInfo.fromJson({'force_update': 'True'}).forceUpdate, isTrue);
    expect(UpdateInfo.fromJson({'force_update': false}).forceUpdate, isFalse);
    expect(UpdateInfo.fromJson({'force_update': 'no'}).forceUpdate, isFalse);
    expect(UpdateInfo.fromJson(const {}).forceUpdate, isFalse);
  });

  test('识别服务器维护标记', () {
    final info = UpdateInfo.fromJson({
      'version': '9.9.9',
      'changelog': '服务器正在维护中',
      'fixing': true,
      'platform_downloads': const <String, Object?>{},
    });

    expect(info.fixing, isTrue);
    expect(info.platformDownloads, isEmpty);
  });

  test('字段缺失时给出可用默认值', () {
    final info = UpdateInfo.fromJson(const {});

    expect(info.version, isEmpty);
    expect(info.changelog, '暂无更新说明');
    expect(info.downloadUrl, isNull);
    expect(info.platformDownloads, isEmpty);
    // 空字符串的下载地址等同于没有，否则会拿去 Uri.parse 出一个空地址。
    expect(UpdateInfo.fromJson({'download_url': ''}).downloadUrl, isNull);
  });

  test('resolveDownloadUrl 回退到 download_url', () {
    // 测试跑在桌面（linux/macos/windows）上，平台键均不匹配 android/ios，
    // 因此这里验证的是「无平台专属链接时回退主链接」这条路径。
    final info = UpdateInfo.fromJson({
      'version': '2.0.1',
      'download_url': 'https://music.test/fallback.zip',
      'platform_downloads': const <String, Object?>{},
    });

    expect(info.resolveDownloadUrl(), 'https://music.test/fallback.zip');
  });

  test('没有任何下载地址时返回 null', () {
    final info = UpdateInfo.fromJson({'version': '2.0.1'});

    expect(info.resolveDownloadUrl(), isNull);
  });

  test('toJson 往返保持字段', () {
    const original = UpdateInfo(
      version: '2.0.1',
      changelog: '更新说明',
      forceUpdate: true,
      fixing: false,
      downloadUrl: 'https://music.test/a.zip',
      platformDownloads: {'windows': 'https://music.test/a.zip'},
    );

    final restored = UpdateInfo.fromJson(original.toJson());

    expect(restored.version, original.version);
    expect(restored.changelog, original.changelog);
    expect(restored.forceUpdate, isTrue);
    expect(restored.platformDownloads, original.platformDownloads);
  });
}
