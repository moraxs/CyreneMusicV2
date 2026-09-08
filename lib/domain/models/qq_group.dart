/// QQ 用户群信息，由后端 `GET /config/public` 的 `data.qq_group` 下发，
/// 字段与 config.json 的 `qq_group` 段一一对应。
class QqGroup {
  const QqGroup({required this.enabled, required this.url, required this.name});

  final bool enabled;

  /// 入群链接（形如 `https://qm.qq.com/q/xxxx`）。
  final String url;

  /// 群名称，展示用。
  final String name;

  /// 是否该渲染入群入口。
  ///
  /// 除了服务端开关，还要求链接非空：`enabled` 为 true 但忘了填 url 的话，
  /// 入口点下去只会是个死按钮，不如不渲染。
  bool get canJoin => enabled && url.isNotEmpty;

  factory QqGroup.fromJson(Map<String, Object?> json) => QqGroup(
    enabled: json['enabled'] == true,
    url: json['url']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'url': url,
    'name': name,
  };
}
