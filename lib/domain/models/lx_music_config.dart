/// LxMusic 音源配置（对应 Next.js demo/lib/services/lxMusicSourceService.ts 的 LxMusicConfig）。
///
/// 由 [LxMusicSourceService.parseScript] 从洛雪音源 JS 脚本中解析得到。
class LxMusicConfig {
  const LxMusicConfig({
    required this.id,
    required this.name,
    required this.version,
    required this.apiUrl,
    required this.apiKey,
    required this.author,
    required this.description,
    required this.homepage,
    required this.scriptContent,
    required this.urlPathTemplate,
    this.isActive = false,
  });

  /// 唯一标识，通常基于脚本名称的 hash。
  final String id;
  final String name;
  final String version;
  final String apiUrl;
  final String apiKey;
  final String author;
  final String description;
  final String homepage;
  final String scriptContent;
  final String urlPathTemplate;
  final bool isActive;

  LxMusicConfig copyWith({
    String? id,
    String? name,
    String? version,
    String? apiUrl,
    String? apiKey,
    String? author,
    String? description,
    String? homepage,
    String? scriptContent,
    String? urlPathTemplate,
    bool? isActive,
  }) => LxMusicConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    version: version ?? this.version,
    apiUrl: apiUrl ?? this.apiUrl,
    apiKey: apiKey ?? this.apiKey,
    author: author ?? this.author,
    description: description ?? this.description,
    homepage: homepage ?? this.homepage,
    scriptContent: scriptContent ?? this.scriptContent,
    urlPathTemplate: urlPathTemplate ?? this.urlPathTemplate,
    isActive: isActive ?? this.isActive,
  );
}

/// LxMusic 脚本运行时信息（对应 Next.js demo/lib/services/lxMusicRuntimeService.ts 的 LxScriptInfo）。
///
/// 在脚本加载完成后，由沙箱回传的 sources / qualities 等动态信息填充。
class LxScriptInfo {
  const LxScriptInfo({
    required this.name,
    required this.version,
    required this.author,
    required this.description,
    required this.homepage,
    required this.script,
    required this.supportedSources,
    required this.supportedQualities,
    required this.platformQualities,
  });

  final String name;
  final String version;
  final String author;
  final String description;
  final String homepage;
  final String script;

  /// 脚本支持的所有来源代码（如 wy/tx/kg/kw）。
  final List<String> supportedSources;

  /// 脚本支持的所有音质（按 128k/320k/flac/flac24bit 顺序过滤）。
  final List<String> supportedQualities;

  /// key=来源代码，value=该来源支持的音质列表。
  final Map<String, List<String>> platformQualities;

  LxScriptInfo copyWith({
    String? name,
    String? version,
    String? author,
    String? description,
    String? homepage,
    String? script,
    List<String>? supportedSources,
    List<String>? supportedQualities,
    Map<String, List<String>>? platformQualities,
  }) => LxScriptInfo(
    name: name ?? this.name,
    version: version ?? this.version,
    author: author ?? this.author,
    description: description ?? this.description,
    homepage: homepage ?? this.homepage,
    script: script ?? this.script,
    supportedSources: supportedSources ?? this.supportedSources,
    supportedQualities: supportedQualities ?? this.supportedQualities,
    platformQualities: platformQualities ?? this.platformQualities,
  );
}
