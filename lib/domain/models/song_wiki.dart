/// 歌曲百科摘要（对应 Next.js SongWikiSummary）。
///
/// 包含曲风、语种、发行时间、简介等结构化 blocks。结构由网易云百科接口定义，
/// 各字段均可缺省，因此均使用 nullable。
class SongWikiSummary {
  const SongWikiSummary({this.blocks});

  final List<WikiBlock>? blocks;

  factory SongWikiSummary.fromJson(Map<String, Object?> json) =>
      SongWikiSummary(blocks: _parseBlocks(json['blocks']));

  Map<String, Object?> toJson() => {
    'blocks': blocks?.map((e) => e.toJson()).toList(),
  };

  static List<WikiBlock>? _parseBlocks(Object? data) => data is List
      ? data
            .whereType<Map>()
            .map((e) => WikiBlock.fromJson(Map<String, Object?>.from(e)))
            .toList()
      : null;
}

/// 百科 block（对应 SongWikiSummary.blocks[]）。
class WikiBlock {
  const WikiBlock({required this.code, this.creatives});

  final String code;
  final List<WikiCreative>? creatives;

  factory WikiBlock.fromJson(Map<String, Object?> json) => WikiBlock(
    code: json['code']?.toString() ?? '',
    creatives: _parseCreatives(json['creatives']),
  );

  Map<String, Object?> toJson() => {
    'code': code,
    'creatives': creatives?.map((e) => e.toJson()).toList(),
  };

  static List<WikiCreative>? _parseCreatives(Object? data) => data is List
      ? data
            .whereType<Map>()
            .map((e) => WikiCreative.fromJson(Map<String, Object?>.from(e)))
            .toList()
      : null;
}

/// 百科 creative（对应 creatives[]）。
class WikiCreative {
  const WikiCreative({
    required this.creativeType,
    this.uiElement,
    this.resources,
  });

  final String creativeType;
  final WikiCreativeUiElement? uiElement;
  final List<WikiResource>? resources;

  factory WikiCreative.fromJson(Map<String, Object?> json) => WikiCreative(
    creativeType: json['creativeType']?.toString() ?? '',
    uiElement: _parseUiElement(json['uiElement']),
    resources: _parseResources(json['resources']),
  );

  Map<String, Object?> toJson() => {
    'creativeType': creativeType,
    'uiElement': uiElement?.toJson(),
    'resources': resources?.map((e) => e.toJson()).toList(),
  };

  static WikiCreativeUiElement? _parseUiElement(Object? data) => data is Map
      ? WikiCreativeUiElement.fromJson(Map<String, Object?>.from(data))
      : null;

  static List<WikiResource>? _parseResources(Object? data) => data is List
      ? data
            .whereType<Map>()
            .map((e) => WikiResource.fromJson(Map<String, Object?>.from(e)))
            .toList()
      : null;
}

/// creative 的 UI 元素（对应 creatives[].uiElement）。
class WikiCreativeUiElement {
  const WikiCreativeUiElement({this.textLinks, this.mainTitle});

  final List<WikiTextLink>? textLinks;
  final WikiTitle? mainTitle;

  factory WikiCreativeUiElement.fromJson(Map<String, Object?> json) =>
      WikiCreativeUiElement(
        textLinks: _parseTextLinks(json['textLinks']),
        mainTitle: _parseTitle(json['mainTitle']),
      );

  Map<String, Object?> toJson() => {
    'textLinks': textLinks?.map((e) => e.toJson()).toList(),
    'mainTitle': mainTitle?.toJson(),
  };

  static List<WikiTextLink>? _parseTextLinks(Object? data) => data is List
      ? data
            .whereType<Map>()
            .map((e) => WikiTextLink.fromJson(Map<String, Object?>.from(e)))
            .toList()
      : null;

  static WikiTitle? _parseTitle(Object? data) =>
      data is Map ? WikiTitle.fromJson(Map<String, Object?>.from(data)) : null;
}

/// 文本链接（对应 uiElement.textLinks[]）。
class WikiTextLink {
  const WikiTextLink({required this.text});

  final String text;

  factory WikiTextLink.fromJson(Map<String, Object?> json) =>
      WikiTextLink(text: json['text']?.toString() ?? '');

  Map<String, Object?> toJson() => {'text': text};
}

/// 主标题（对应 uiElement.mainTitle / resources[].uiElement.mainTitle）。
class WikiTitle {
  const WikiTitle({required this.title});

  final String title;

  factory WikiTitle.fromJson(Map<String, Object?> json) =>
      WikiTitle(title: json['title']?.toString() ?? '');

  Map<String, Object?> toJson() => {'title': title};
}

/// 百科资源（对应 creatives[].resources[]）。
class WikiResource {
  const WikiResource({this.uiElement});

  final WikiResourceUiElement? uiElement;

  factory WikiResource.fromJson(Map<String, Object?> json) =>
      WikiResource(uiElement: _parseUiElement(json['uiElement']));

  Map<String, Object?> toJson() => {'uiElement': uiElement?.toJson()};

  static WikiResourceUiElement? _parseUiElement(Object? data) => data is Map
      ? WikiResourceUiElement.fromJson(Map<String, Object?>.from(data))
      : null;
}

/// 资源 UI 元素（对应 resources[].uiElement）。
class WikiResourceUiElement {
  const WikiResourceUiElement({this.mainTitle});

  final WikiTitle? mainTitle;

  factory WikiResourceUiElement.fromJson(Map<String, Object?> json) =>
      WikiResourceUiElement(
        mainTitle: WikiCreativeUiElement._parseTitle(json['mainTitle']),
      );

  Map<String, Object?> toJson() => {'mainTitle': mainTitle?.toJson()};
}
