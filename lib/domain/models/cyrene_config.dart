/// Cyrene 配置文件模型（对应 Next.js demo/lib/services/cyreneConfigService.ts 的 CyreneConfig）。
class CyreneConfig {
  const CyreneConfig({
    required this.name,
    required this.url,
    required this.apiKey,
  });

  final String name;
  final String url;
  final String apiKey;

  factory CyreneConfig.fromJson(Map<String, Object?> json) => CyreneConfig(
    name: json['name']?.toString() ?? 'OmniParse',
    url: json['url']?.toString() ?? '',
    apiKey: json['apiKey']?.toString() ?? '',
  );

  Map<String, Object?> toJson() => {'name': name, 'url': url, 'apiKey': apiKey};
}
