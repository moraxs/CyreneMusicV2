/// 本地音轨元数据（对应 Next.js demo/lib/services/localMusicService.ts 的 LocalTrackMetadata）。
///
/// 由原生文件扫描 / 单文件解析返回的原始元数据。Flutter 侧尚未接入平台通道前，
/// 该模型仅作为签名占位与服务间数据载体使用。
class LocalTrackMetadata {
  const LocalTrackMetadata({
    required this.filePath,
    required this.name,
    required this.artists,
    required this.album,
    required this.duration,
    this.coverDataUrl,
    this.lyric,
  });

  final String filePath;
  final String name;
  final String artists;
  final String album;

  /// 时长，单位与 Tauri 端一致（秒）。
  final double duration;
  final String? coverDataUrl;
  final String? lyric;

  factory LocalTrackMetadata.fromJson(Map<String, Object?> json) =>
      LocalTrackMetadata(
        filePath: json['filePath']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        artists: json['artists']?.toString() ?? '',
        album: json['album']?.toString() ?? '',
        duration: (json['duration'] as num?)?.toDouble() ?? 0,
        coverDataUrl: json['coverDataUrl'] as String?,
        lyric: json['lyric'] as String?,
      );
}

/// 已入库的本地音轨条目（对应 Next.js LocalTrackEntry）。
class LocalTrackEntry {
  const LocalTrackEntry({
    required this.filePath,
    required this.name,
    required this.artists,
    required this.album,
    required this.duration,
    this.coverDataUrl,
    this.lyric,
    this.hasLrcFile = false,
    required this.addedAt,
    this.folderPath,
  });

  final String filePath;
  final String name;
  final String artists;
  final String album;
  final double duration;
  final String? coverDataUrl;
  final String? lyric;
  final bool hasLrcFile;

  /// 入库时间戳（毫秒）。
  final int addedAt;

  /// 由文件夹扫描入库时记录的来源文件夹；单文件导入时为 null。
  final String? folderPath;

  factory LocalTrackEntry.fromJson(Map<String, Object?> json) =>
      LocalTrackEntry(
        filePath: json['filePath']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        artists: json['artists']?.toString() ?? '',
        album: json['album']?.toString() ?? '',
        duration: (json['duration'] as num?)?.toDouble() ?? 0,
        coverDataUrl: json['coverDataUrl'] as String?,
        lyric: json['lyric'] as String?,
        hasLrcFile: json['hasLrcFile'] == true,
        addedAt: (json['addedAt'] as num?)?.toInt() ?? 0,
        folderPath: json['folderPath'] as String?,
      );

  Map<String, Object?> toJson() => {
    'filePath': filePath,
    'name': name,
    'artists': artists,
    'album': album,
    'duration': duration,
    'coverDataUrl': coverDataUrl,
    'lyric': lyric,
    'hasLrcFile': hasLrcFile,
    'addedAt': addedAt,
    'folderPath': folderPath,
  };
}

/// 已扫描文件夹记录（对应 Next.js LocalMusicService 内的 scannedFolders store）。
class ScannedFolder {
  const ScannedFolder({required this.path, required this.scannedAt});

  final String path;

  /// 最近一次扫描时间戳（毫秒）。
  final int scannedAt;

  factory ScannedFolder.fromJson(Map<String, Object?> json) => ScannedFolder(
    path: json['path']?.toString() ?? '',
    scannedAt: (json['scannedAt'] as num?)?.toInt() ?? 0,
  );

  Map<String, Object?> toJson() => {'path': path, 'scannedAt': scannedAt};
}
