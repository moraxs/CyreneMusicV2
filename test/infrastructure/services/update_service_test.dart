import 'dart:convert';

import 'package:cyrene_music_reborn/domain/models/app_update.dart';
import 'package:cyrene_music_reborn/infrastructure/core/api_client.dart';
import 'package:cyrene_music_reborn/infrastructure/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  late UpdateService service;

  setUp(() {
    service = UpdateService.instance..setCurrentVersion('2.0.0');
  });

  group('checkUpdate', () {
    test('解析后端响应', () async {
      _stub(
        jsonEncode({
          'status': 200,
          'data': {
            'version': '2.0.1',
            'changelog': '修复若干问题',
            'force_update': false,
            'platform_downloads': {'android': 'https://music.test/a.apk'},
          },
        }),
      );

      final info = await service.checkUpdate();

      expect(info, isNotNull);
      expect(info!.version, '2.0.1');
      expect(service.hasUpdate(info), isTrue);
    });

    test('业务码非 200 时返回 null', () async {
      _stub(jsonEncode({'status': 500, 'data': {'version': '2.0.1'}}));

      expect(await service.checkUpdate(), isNull);
    });

    test('HTTP 错误时返回 null', () async {
      _stub('{}', statusCode: 502);

      expect(await service.checkUpdate(), isNull);
    });

    test('版本号为空时返回 null', () async {
      _stub(jsonEncode({'status': 200, 'data': {'changelog': 'x'}}));

      expect(await service.checkUpdate(), isNull);
    });

    test('网络异常静默返回 null', () async {
      // 检查更新是锦上添花，后端抽风不该把错误弹到用户脸上。
      ApiClient.instance.useClient(
        MockClient((_) async => throw const SocketExceptionStub()),
      );

      expect(await service.checkUpdate(), isNull);
    });

    test('响应不是 JSON 时返回 null', () async {
      _stub('<html>502 Bad Gateway</html>');

      expect(await service.checkUpdate(), isNull);
    });
  });

  group('hasUpdate', () {
    test('仅高于当前版本才算有更新', () async {
      expect(service.hasUpdate(_info('2.0.1')), isTrue);
      expect(service.hasUpdate(_info('2.1.0')), isTrue);
      expect(service.hasUpdate(_info('2.0.0')), isFalse);
      expect(service.hasUpdate(_info('1.9.9')), isFalse);
    });
  });

  group('compareVersions', () {
    test('逐段按整数比较，而非字符串', () {
      // 字符串比较会认为 '2.0.9' > '2.0.10'。
      expect(service.compareVersions('2.0.10', '2.0.9'), 1);
      expect(service.compareVersions('2.0.9', '2.0.10'), -1);
    });

    test('相等与位数不等', () {
      expect(service.compareVersions('2.0.0', '2.0.0'), 0);
      expect(service.compareVersions('2.0', '2.0.0'), 0);
      expect(service.compareVersions('2.0.1', '2.0'), 1);
    });

    test('只剥开头的 v 前缀', () {
      expect(service.compareVersions('v2.0.1', '2.0.1'), 0);
      expect(service.compareVersions('V2.0.1', '2.0.0'), 1);
    });

    test('已知限制：预发布标签解析错误', () {
      // '2.0.0-beta.1' 被切成 ['2','0','0-beta','1']：'0-beta' 解析失败记 0，
      // 而多出来的第四段 '1' 让它反而"大于" 2.0.0 —— 预发布版会被当成正式
      // 版的升级推给用户。点分整数比较无法表达 semver 语义，发版请用纯数字
      // 版本号（见 app_version.dart 的说明）。
      expect(service.compareVersions('2.0.0-beta.1', '2.0.0'), 1);
      // 不带序号的预发布标签则退化成相等，同样不是 semver 语义。
      expect(service.compareVersions('2.0.0-beta', '2.0.0'), 0);
    });
  });
}

void _stub(String body, {int statusCode = 200}) {
  ApiClient.instance.useClient(
    MockClient(
      (_) async => http.Response(
        body,
        statusCode,
        headers: const {'content-type': 'application/json'},
      ),
    ),
  );
}

UpdateInfo _info(String version) =>
    UpdateInfo(version: version, changelog: '', forceUpdate: false);

class MockClient extends http.BaseClient {
  MockClient(this.handler);

  final Future<http.Response> Function(http.BaseRequest request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
