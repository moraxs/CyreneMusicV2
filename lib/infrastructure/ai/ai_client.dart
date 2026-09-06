import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../application/stores/ai_settings_store.dart';
import '../../domain/ai/ai_models.dart';

/// AI 请求层：同时支持 OpenAI 兼容与 Anthropic 兼容两条路由。
///
/// 用原始 HTTP 而不是官方 SDK——Anthropic 没有 Dart SDK，而且这里本来就要
/// 同时说两家的协议。两者的差异全部收敛在 [_buildRequest] 与 [_extractDelta]
/// 里，其余流程（SSE 拆行、错误解析、超时）是共用的。
///
/// 一律走流式：赏析/总结这类输出几百字，非流式就是十来秒白屏；SSE 两家都支持，
/// 解析成本也就多几行。
class AiClient {
  AiClient({AiSettingsStore? settings, http.Client Function()? httpClientFactory})
    : _settings = settings ?? AiSettingsStore.instance,
      _httpClientFactory = httpClientFactory ?? http.Client.new;

  final AiSettingsStore _settings;
  final http.Client Function() _httpClientFactory;

  static final AiClient instance = AiClient();

  /// 首字节超时。模型思考久是正常的，但连不上要尽快报错。
  static const _connectTimeout = Duration(seconds: 45);

  /// 赏析/总结这类输出是**有意做短的**，给个够用的上限即可；这不是通用默认值。
  static const defaultMaxTokens = 2048;

  /// 流式请求，逐段吐出文本增量。
  ///
  /// 失败一律抛 [AiException]，[AiException.message] 直接可以显示给用户。
  Stream<String> stream({
    required String prompt,
    String? system,
    int maxTokens = defaultMaxTokens,
  }) async* {
    final baseUrl = _settings.baseUrl.trim();
    final apiKey = _settings.apiKey.trim();
    final model = _settings.model.trim();
    if (baseUrl.isEmpty || apiKey.isEmpty || model.isEmpty) {
      throw const AiException('还没配置 AI 服务，请先在设置里填好地址、密钥和模型');
    }

    final route = _settings.route;
    final client = _httpClientFactory();
    try {
      final request = _buildRequest(
        route: route,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        system: system,
        prompt: prompt,
        maxTokens: maxTokens,
      );
      final response = await client.send(request).timeout(_connectTimeout);
      if (response.statusCode != 200) {
        throw AiException(
          await _readError(response),
          statusCode: response.statusCode,
        );
      }

      // SSE：按行读，只认 `data:` 行；Anthropic 的 `event:` 行可以整行忽略，
      // 因为它的 data 里已经带了同名的 type 字段。
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty) continue;
        if (payload == '[DONE]') return; // OpenAI 的收尾标记
        Object? decoded;
        try {
          decoded = jsonDecode(payload);
        } catch (_) {
          continue; // 心跳/注释行，跳过
        }
        if (decoded is! Map) continue;
        final frame = Map<String, Object?>.from(decoded);
        final error = _errorInFrame(frame);
        if (error != null) throw AiException(error);
        final delta = _extractDelta(route, frame);
        if (delta != null && delta.isNotEmpty) yield delta;
      }
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw const AiException('AI 服务响应超时，检查一下网络或 Base URL');
    } catch (error) {
      throw AiException(_friendlyNetworkError(error));
    } finally {
      client.close();
    }
  }

  /// 一次性拿到完整文本（内部仍走流式，只是把增量攒起来）。
  Future<String> complete({
    required String prompt,
    String? system,
    int maxTokens = defaultMaxTokens,
  }) async {
    final buffer = StringBuffer();
    await for (final delta in stream(
      prompt: prompt,
      system: system,
      maxTokens: maxTokens,
    )) {
      buffer.write(delta);
    }
    return buffer.toString();
  }

  /// 测试连接：发一次最小请求。
  ///
  /// BYO-key 最容易卡在配置错（key 无效、模型名不对、base url 少了 /v1），
  /// 与其让用户在业务功能里猜，不如在设置页当场把服务端的原话摊开。
  Future<String> testConnection() async {
    final reply = await complete(
      prompt: '回复两个字：可用',
      system: '你是连通性测试端点，只按要求回复，不要多说。',
      maxTokens: 64,
    );
    final trimmed = reply.trim();
    return trimmed.isEmpty ? '（服务端返回了空内容，但连接本身是通的）' : trimmed;
  }

  // ───────────────────────── 两家协议的差异 ─────────────────────────

  http.Request _buildRequest({
    required AiRoute route,
    required String baseUrl,
    required String apiKey,
    required String model,
    required String? system,
    required String prompt,
    required int maxTokens,
  }) {
    final request = http.Request('POST', _endpoint(route, baseUrl))
      ..headers['content-type'] = 'application/json';

    switch (route) {
      case AiRoute.openai:
        request.headers['authorization'] = 'Bearer $apiKey';
        request.bodyBytes = utf8.encode(
          jsonEncode({
            'model': model,
            'max_tokens': maxTokens,
            'stream': true,
            'messages': [
              if (system != null && system.isNotEmpty)
                {'role': 'system', 'content': system},
              {'role': 'user', 'content': prompt},
            ],
          }),
        );
      case AiRoute.anthropic:
        request.headers['x-api-key'] = apiKey;
        request.headers['anthropic-version'] = '2023-06-01';
        // 请求体刻意只带最少的字段：这条路由多半指向第三方 Anthropic 兼容网关，
        // thinking / output_config 这类新参数在它们那儿常常直接 400。
        // 省掉 thinking 在官方模型上等于走默认（自适应），没有损失。
        request.bodyBytes = utf8.encode(
          jsonEncode({
            'model': model,
            'max_tokens': maxTokens,
            'stream': true,
            if (system != null && system.isNotEmpty) 'system': system,
            'messages': [
              {'role': 'user', 'content': prompt},
            ],
          }),
        );
    }
    return request;
  }

  /// 拼端点。用户粘进来的 Base URL 两种写法都常见（带不带 `/v1`），
  /// 都认——少一个斜杠就 404 太不值当了。
  static Uri _endpoint(AiRoute route, String baseUrl) {
    final base = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final hasVersion = RegExp(r'/v\d+$').hasMatch(base);
    final path = switch (route) {
      AiRoute.openai => hasVersion ? '/chat/completions' : '/v1/chat/completions',
      AiRoute.anthropic => hasVersion ? '/messages' : '/v1/messages',
    };
    return Uri.parse('$base$path');
  }

  /// 从一帧 SSE 里取出文本增量，取不到返回 null。
  static String? _extractDelta(AiRoute route, Map<String, Object?> frame) {
    switch (route) {
      case AiRoute.openai:
        final choices = frame['choices'];
        if (choices is! List || choices.isEmpty) return null;
        final first = choices.first;
        if (first is! Map) return null;
        final delta = first['delta'];
        if (delta is! Map) return null;
        return delta['content']?.toString();
      case AiRoute.anthropic:
        if (frame['type'] != 'content_block_delta') return null;
        final delta = frame['delta'];
        if (delta is! Map) return null;
        if (delta['type'] != 'text_delta') return null;
        return delta['text']?.toString();
    }
  }

  /// 两家的错误体都是 `{"error": {"message": ...}}`，流里也可能塞错误帧。
  static String? _errorInFrame(Map<String, Object?> frame) {
    final error = frame['error'];
    if (error is Map) {
      return error['message']?.toString() ?? 'AI 服务返回了错误';
    }
    if (frame['type'] == 'error') return 'AI 服务返回了错误';
    return null;
  }

  static Future<String> _readError(http.StreamedResponse response) async {
    String body;
    try {
      body = await response.stream.bytesToString();
    } catch (_) {
      body = '';
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] != null) {
          return error['message'].toString();
        }
        if (decoded['message'] != null) return decoded['message'].toString();
      }
    } catch (_) {
      // 不是 JSON（网关的 HTML 错误页之类），退回截断的原文。
    }
    final snippet = body.trim();
    if (snippet.isEmpty) return 'HTTP ${response.statusCode}';
    return 'HTTP ${response.statusCode}：'
        '${snippet.length > 200 ? '${snippet.substring(0, 200)}…' : snippet}';
  }

  static String _friendlyNetworkError(Object error) {
    debugPrint('[AI] 请求失败: $error');
    final text = error.toString();
    if (text.contains('Failed host lookup') || text.contains('SocketException')) {
      return '连不上 AI 服务，检查网络或 Base URL 是否写对';
    }
    if (text.contains('HandshakeException') || text.contains('CERTIFICATE')) {
      return 'TLS 握手失败，检查 Base URL 的协议与证书';
    }
    return '请求失败：$text';
  }
}
