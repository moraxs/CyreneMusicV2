enum AudioSourceType {
  omniParse(0, 'OmniParse'),
  lxMusic(1, 'Lx Music');

  const AudioSourceType(this.code, this.displayName);

  final int code;
  final String displayName;

  static AudioSourceType? tryFromCode(int? code) => switch (code) {
    null || 0 => AudioSourceType.omniParse,
    1 => AudioSourceType.lxMusic,
    _ => null,
  };
}

class AudioSourceConfig {
  const AudioSourceConfig({
    required this.id,
    required this.type,
    required this.name,
    required this.url,
    this.apiKey = '',
    this.isEnabled = true,
    this.supportedPlatforms = const [],
    this.version = '',
    this.author = '',
    this.description = '',
    this.scriptSource = '',
    this.scriptContent = '',
    this.urlPathTemplate = '',
  });

  final String id;
  final AudioSourceType type;
  final String name;
  final String url;
  final String apiKey;
  final bool isEnabled;
  final List<String> supportedPlatforms;

  final String version;
  final String author;
  final String description;
  final String scriptSource;
  final String scriptContent;
  final String urlPathTemplate;

  bool get isLxMusic => type == AudioSourceType.lxMusic;

  static AudioSourceConfig? tryFromJson(Map<String, Object?> json) {
    final code = (json['type'] as num?)?.toInt();
    final type = AudioSourceType.tryFromCode(code);
    if (type == null) return null;

    final config = AudioSourceConfig(
      id: json['id']?.toString() ?? '',
      type: type,
      name: json['name']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      apiKey: json['apiKey']?.toString() ?? '',
      isEnabled: json['isEnabled'] is bool ? json['isEnabled'] as bool : true,
      supportedPlatforms:
          (json['supportedPlatforms'] as List?)
              ?.map((value) => value.toString())
              .toList(growable: false) ??
          const [],
      version: json['version']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      scriptSource: json['scriptSource']?.toString() ?? '',
      scriptContent: json['scriptContent']?.toString() ?? '',
      urlPathTemplate: json['urlPathTemplate']?.toString() ?? '',
    );
    if (config.id.isEmpty || config.name.isEmpty || config.url.isEmpty) {
      return null;
    }
    return config;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.code,
    'name': name,
    'url': url,
    'apiKey': apiKey,
    'isEnabled': isEnabled,
    'supportedPlatforms': supportedPlatforms,
    'version': version,
    'author': author,
    'description': description,
    'scriptSource': scriptSource,
    'scriptContent': scriptContent,
    'urlPathTemplate': urlPathTemplate,
  };

  AudioSourceConfig copyWith({
    String? id,
    AudioSourceType? type,
    String? name,
    String? url,
    String? apiKey,
    bool? isEnabled,
    List<String>? supportedPlatforms,
    String? version,
    String? author,
    String? description,
    String? scriptSource,
    String? scriptContent,
    String? urlPathTemplate,
  }) => AudioSourceConfig(
    id: id ?? this.id,
    type: type ?? this.type,
    name: name ?? this.name,
    url: url ?? this.url,
    apiKey: apiKey ?? this.apiKey,
    isEnabled: isEnabled ?? this.isEnabled,
    supportedPlatforms: supportedPlatforms ?? this.supportedPlatforms,
    version: version ?? this.version,
    author: author ?? this.author,
    description: description ?? this.description,
    scriptSource: scriptSource ?? this.scriptSource,
    scriptContent: scriptContent ?? this.scriptContent,
    urlPathTemplate: urlPathTemplate ?? this.urlPathTemplate,
  );
}
