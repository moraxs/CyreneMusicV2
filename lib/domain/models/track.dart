import 'music_source.dart';

/// 同一逻辑歌曲在另一个音乐平台上的标识。
class TrackSourceRef {
  const TrackSourceRef({required this.id, required this.source});

  final String id;
  final MusicSource source;

  factory TrackSourceRef.fromTrack(Track track) =>
      TrackSourceRef(id: track.id, source: track.source);

  factory TrackSourceRef.fromJson(Map<String, Object?> json) => TrackSourceRef(
    id: json['id']?.toString() ?? '',
    source: MusicSource.fromWireName(json['source']?.toString() ?? ''),
  );

  Map<String, Object?> toJson() => {'id': id, 'source': source.wireName};
}

/// 副歌时间区间（对应 Next.js Track.chorus 的内联结构）。
class ChorusRange {
  const ChorusRange({required this.startTime, required this.endTime});

  final Duration startTime;
  final Duration endTime;

  factory ChorusRange.fromJson(Map<String, Object?> json) => ChorusRange(
    startTime: Duration(
      milliseconds: ((json['startTime'] as num?) ?? 0).round(),
    ),
    endTime: Duration(milliseconds: ((json['endTime'] as num?) ?? 0).round()),
  );

  Map<String, Object?> toJson() => {
    'startTime': startTime.inMilliseconds,
    'endTime': endTime.inMilliseconds,
  };
}

/// 歌曲轨道详情（对应 Next.js demo/lib/models/track.ts 的 Track）。
class Track {
  const Track({
    required this.id,
    required this.name,
    required this.artists,
    required this.album,
    required this.picUrl,
    required this.source,
    this.lyric,
    this.yrc,
    this.tlyric,
    this.ytlrc,
    this.romaji,
    this.chorus,
    this.duration,
    this.filePath,
    this.playbackUrl,
    this.alternatives = const [],
  });

  /// 平台内部 ID。
  final String id;
  final String name;
  final String artists;
  final String album;
  final String picUrl;
  final MusicSource source;
  final String? lyric;
  final String? yrc;
  final String? tlyric;
  final String? ytlrc;

  /// 行级罗马音歌词原始串（后端 `romalrc` 字段）。
  final String? romaji;

  /// 副歌时间区间。
  final List<ChorusRange>? chorus;
  final Duration? duration;

  /// 本地文件路径（仅 source=local 时有值）。
  final String? filePath;

  /// 解析后的播放地址（Flutter 端扩展字段）。
  final Uri? playbackUrl;

  /// 同名歌曲在其他平台上的标识，按搜索结果优先级排序。
  final List<TrackSourceRef> alternatives;

  String get key => '${source.wireName}:$id';

  Iterable<TrackSourceRef> get sourceCandidates sync* {
    yield TrackSourceRef(id: id, source: source);
    yield* alternatives;
  }

  Track withSource(TrackSourceRef ref) => Track(
    id: ref.id,
    name: name,
    artists: artists,
    album: album,
    picUrl: picUrl,
    source: ref.source,
    lyric: lyric,
    yrc: yrc,
    tlyric: tlyric,
    ytlrc: ytlrc,
    romaji: romaji,
    chorus: chorus,
    duration: duration,
    filePath: filePath,
    alternatives: alternatives,
  );

  Track copyWith({
    String? lyric,
    String? yrc,
    String? tlyric,
    String? ytlrc,
    String? romaji,
    List<ChorusRange>? chorus,
    Duration? duration,
    String? filePath,
    Uri? playbackUrl,
    List<TrackSourceRef>? alternatives,
  }) => Track(
    id: id,
    name: name,
    artists: artists,
    album: album,
    picUrl: picUrl,
    source: source,
    lyric: lyric ?? this.lyric,
    yrc: yrc ?? this.yrc,
    tlyric: tlyric ?? this.tlyric,
    ytlrc: ytlrc ?? this.ytlrc,
    romaji: romaji ?? this.romaji,
    chorus: chorus ?? this.chorus,
    duration: duration ?? this.duration,
    filePath: filePath ?? this.filePath,
    playbackUrl: playbackUrl ?? this.playbackUrl,
    alternatives: alternatives ?? this.alternatives,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'artists': artists,
    'album': album,
    'picUrl': picUrl,
    'source': source.wireName,
    'lyric': lyric,
    'yrc': yrc,
    'tlyric': tlyric,
    'ytlrc': ytlrc,
    'romaji': romaji,
    'chorus': chorus?.map((c) => c.toJson()).toList(),
    'durationMs': duration?.inMilliseconds,
    'filePath': filePath,
    'playbackUrl': playbackUrl?.toString(),
    'alternatives': alternatives.map((item) => item.toJson()).toList(),
  };

  factory Track.fromJson(Map<String, Object?> json) => Track(
    id: json['id'].toString(),
    name: json['name']?.toString() ?? '',
    artists: json['artists']?.toString() ?? '',
    album: json['album']?.toString() ?? '',
    picUrl: json['picUrl']?.toString() ?? '',
    source: MusicSource.fromWireName(json['source']?.toString() ?? ''),
    lyric: json['lyric'] as String?,
    yrc: json['yrc'] as String?,
    tlyric: json['tlyric'] as String?,
    ytlrc: json['ytlrc'] as String?,
    romaji: json['romaji'] as String?,
    chorus: (json['chorus'] as List?)
        ?.whereType<Map>()
        .map((e) => ChorusRange.fromJson(Map<String, Object?>.from(e)))
        .toList(),
    duration: switch (json['durationMs']) {
      final num milliseconds => Duration(milliseconds: milliseconds.round()),
      _ => null,
    },
    filePath: json['filePath'] as String?,
    playbackUrl: switch (json['playbackUrl']) {
      final String value when value.isNotEmpty => Uri.tryParse(value),
      _ => null,
    },
    alternatives:
        (json['alternatives'] as List?)
            ?.whereType<Map>()
            .map(
              (item) =>
                  TrackSourceRef.fromJson(Map<String, Object?>.from(item)),
            )
            .toList(growable: false) ??
        const [],
  );

  @override
  bool operator ==(Object other) => other is Track && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// 合并后的歌曲轨道，支持多源播放（对应 Next.js MergedTrack）。
///
/// 标准化键为 `name|artists`，不同来源的同名曲合并为同一逻辑歌曲。
class MergedTrack {
  MergedTrack(List<Track> tracks) : tracks = List.unmodifiable(tracks) {
    if (tracks.isEmpty) {
      throw ArgumentError('Tracks cannot be empty');
    }
    final first = tracks.first;
    name = first.name;
    artists = first.artists;
    picUrl = first.picUrl;
    mainSource = first.source;
    key = '${_normalize(name)}|${_normalize(artists)}';
  }

  late final String key;
  late final String name;
  late final String artists;
  late final String picUrl;
  final List<Track> tracks;
  late final MusicSource mainSource;

  static String _normalize(String str) => str
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s'), '')
      .replaceAll(RegExp(r'[、/&，]'), ',');

  static MergedTrack fromTracks(List<Track> tracks) => MergedTrack(tracks);
}
