import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music_reborn/application/stores/ai_settings_store.dart';
import 'package:cyrene_music_reborn/domain/ai/ai_models.dart';
import 'package:cyrene_music_reborn/infrastructure/ai/ai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AI 请求层：两条兼容路由的端点、鉴权头、请求体与 SSE 解析。
///
/// 用真实的 loopback HTTP 服务端而不是 mock client——要验的正是「线上真发出去
/// 的那一份」：头的大小写、SSE 分帧、错误体解析，mock 掉就等于没测。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 测试绑定默认把 HttpClient mock 成「一律 400」，真发请求前必须清掉。
  HttpOverrides.global = null;

  late _FakeAiServer server;
  final settings = AiSettingsStore.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = await _FakeAiServer.start();
    await settings.init();
    await settings.setEnabled(true);
    await settings.setRoute(AiRoute.openai);
    await settings.setBaseUrl('http://127.0.0.1:${server.port}/v1');
    await settings.setApiKey('sk-test-key');
    await settings.setModel('test-model');
  });

  tearDown(() async {
    await server.close();
    await settings.setApiKey('');
  });

  AiClient buildClient() => AiClient(settings: settings);

  test('OpenAI 路由：端点、Bearer 鉴权、消息体与增量拼接', () async {
    server.body =
        'data: ${jsonEncode({
          'choices': [
            {'delta': <String, Object?>{}},
          ],
        })}\n\n'
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': '好'},
            },
          ],
        })}\n\n'
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': '听'},
            },
          ],
        })}\n\n'
        'data: [DONE]\n\n';

    final text = await buildClient().complete(prompt: '你好', system: '系统');
    expect(text, '好听');

    expect(server.lastPath, '/v1/chat/completions');
    expect(server.lastHeaders?['authorization'], 'Bearer sk-test-key');
    final body = jsonDecode(server.lastBody!) as Map<String, Object?>;
    expect(body['model'], 'test-model');
    expect(body['stream'], isTrue);
    final messages = body['messages']! as List;
    expect(messages.length, 2);
    expect((messages.first as Map)['role'], 'system');
    expect((messages.last as Map)['content'], '你好');
  });

  test('Anthropic 路由：x-api-key + 版本头，只发最小请求体', () async {
    await settings.setRoute(AiRoute.anthropic);
    await settings.setBaseUrl('http://127.0.0.1:${server.port}');
    await settings.setModel('claude-opus-5');
    server.body =
        'event: content_block_delta\n'
        'data: ${jsonEncode({
          'type': 'content_block_delta',
          'delta': {'type': 'text_delta', 'text': '很'},
        })}\n\n'
        'event: content_block_delta\n'
        'data: ${jsonEncode({
          'type': 'content_block_delta',
          'delta': {'type': 'text_delta', 'text': '好'},
        })}\n\n'
        'event: message_stop\n'
        'data: ${jsonEncode({'type': 'message_stop'})}\n\n';

    final text = await buildClient().complete(prompt: '你好', system: '系统');
    expect(text, '很好');

    expect(server.lastPath, '/v1/messages');
    expect(server.lastHeaders?['x-api-key'], 'sk-test-key');
    expect(server.lastHeaders?['anthropic-version'], '2023-06-01');
    expect(server.lastHeaders?.containsKey('authorization'), isFalse);
    final body = jsonDecode(server.lastBody!) as Map<String, Object?>;
    // system 是顶层字段，不混进 messages。
    expect(body['system'], '系统');
    expect((body['messages']! as List).length, 1);
    // 第三方兼容网关常常不认这些新参数，一律不发。
    expect(body.containsKey('thinking'), isFalse);
    expect(body.containsKey('output_config'), isFalse);
  });

  test('Base URL 带不带 /v1 都能拼对', () async {
    server.body = 'data: [DONE]\n\n';
    await settings.setBaseUrl('http://127.0.0.1:${server.port}');
    await buildClient().complete(prompt: 'x');
    expect(server.lastPath, '/v1/chat/completions');

    await settings.setBaseUrl('http://127.0.0.1:${server.port}/v1/');
    await buildClient().complete(prompt: 'x');
    expect(server.lastPath, '/v1/chat/completions');
  });

  test('HTTP 错误把服务端原话带出来，而不是一句「请求失败」', () async {
    server.status = 401;
    server.body = jsonEncode({
      'error': {'message': 'Invalid API key provided'},
    });
    await expectLater(
      buildClient().complete(prompt: 'x'),
      throwsA(
        isA<AiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', contains('Invalid API key')),
      ),
    );
  });

  test('非 JSON 错误体（网关 HTML 页）也能给出可读原因', () async {
    server.status = 502;
    server.body = '<html><body>Bad Gateway</body></html>';
    await expectLater(
      buildClient().complete(prompt: 'x'),
      throwsA(
        isA<AiException>().having(
          (e) => e.message,
          'message',
          allOf(contains('502'), contains('Bad Gateway')),
        ),
      ),
    );
  });

  test('流中间插进来的错误帧会中断并报出来', () async {
    server.body =
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': '开头'},
            },
          ],
        })}\n\n'
        'data: ${jsonEncode({
          'error': {'message': '上游模型过载'},
        })}\n\n';
    await expectLater(
      buildClient().complete(prompt: 'x'),
      throwsA(
        isA<AiException>().having((e) => e.message, 'message', '上游模型过载'),
      ),
    );
  });

  test('没配置齐就不发请求', () async {
    await settings.setApiKey('');
    await expectLater(
      buildClient().complete(prompt: 'x'),
      throwsA(isA<AiException>()),
    );
    expect(server.requests, 0);
  });
}

/// 顶替 AI 服务端的假 HTTP 服务。
class _FakeAiServer {
  _FakeAiServer(this._server);

  final HttpServer _server;
  int requests = 0;
  int status = 200;
  String body = '';
  String? lastPath;
  String? lastBody;
  Map<String, String>? lastHeaders;

  int get port => _server.port;

  static Future<_FakeAiServer> start() async {
    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final server = _FakeAiServer(httpServer);
    httpServer.listen((request) async {
      server.requests += 1;
      server.lastPath = request.uri.path;
      server.lastBody = await utf8.decoder.bind(request).join();
      final headers = <String, String>{};
      request.headers.forEach((name, values) => headers[name] = values.first);
      server.lastHeaders = headers;

      request.response.statusCode = server.status;
      // 必须显式 UTF-8：HttpResponse 在 content-type 没带 charset 时按 latin1
      // 编码，body 里有中文就会在写入时抛错，连响应头都发不出去。
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      request.response.add(utf8.encode(server.body));
      await request.response.close();
    });
    return server;
  }

  Future<void> close() => _server.close(force: true);
}
