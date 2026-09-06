/// AI 服务的兼容路由。
///
/// 两家的差异只有三处——端点路径、鉴权头、请求/响应体形状——所以不做成插件体系，
/// 一个枚举加两个分支就够了（见 `infrastructure/ai/ai_client.dart`）。
enum AiRoute {
  /// OpenAI 兼容：`POST {base}/chat/completions`，`Authorization: Bearer`。
  /// 绝大多数第三方中转（SiliconFlow、DeepSeek、OpenRouter、各种自建网关）都走这套。
  openai('openai', 'OpenAI 兼容'),

  /// Anthropic 兼容：`POST {base}/v1/messages`，`x-api-key` + `anthropic-version`。
  anthropic('anthropic', 'Anthropic 兼容');

  const AiRoute(this.wireName, this.label);

  final String wireName;
  final String label;

  static AiRoute fromWireName(String? value) {
    for (final route in AiRoute.values) {
      if (route.wireName == value) return route;
    }
    return AiRoute.openai;
  }

  /// 换路由时给出的默认模型，省得用户对着空输入框猜。
  String get suggestedModel => switch (this) {
    AiRoute.openai => 'deepseek-ai/DeepSeek-V3.2',
    AiRoute.anthropic => 'claude-opus-5',
  };

  /// 默认 Base URL 提示。
  String get baseUrlHint => switch (this) {
    AiRoute.openai => 'https://api.siliconflow.cn/v1',
    AiRoute.anthropic => 'https://api.anthropic.com',
  };
}

/// AI 请求失败。[message] 是可以直接摊给用户看的原因——BYO-key 最常见的问题
/// 就是配置错（key 无效、模型名不对、base url 少了 /v1），把服务端原话透出来
/// 比一句「请求失败」有用得多。
class AiException implements Exception {
  const AiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'AiException($statusCode): $message';
}
