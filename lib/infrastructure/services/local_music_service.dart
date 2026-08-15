import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart' show gbk;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/local_track.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';
import 'audio_metadata_reader.dart';
import 'local_music_native.dart';

/// 本地音乐服务（对应 Next.js demo/lib/services/localMusicService.ts）。
///
/// 单例。Next.js 端使用 IndexedDB 持久化本地音轨，并通过 Tauri `invoke`
/// （`scan_music_folder` / `get_audio_metadata` / `read_lrc_file`）调用 Rust
/// 后端扫描文件夹与解析元数据。
///
/// Flutter 侧实现：纯 Dart（`dart:io` + [AudioMetadataReader]），无需 platform
/// channel，跨平台支持 FLAC / MP3 / M4A / WAV / OGG / APE。
class LocalMusicService {
  LocalMusicService._();
  static final LocalMusicService instance = LocalMusicService._();

  /// 磁盘持久化文件名（存放于应用文档目录）。
  static const _fileName = 'local_music_library.json';

  /// 内存缓存：filePath -> LocalTrackEntry。
  final Map<String, LocalTrackEntry> _tracks = {};

  /// 内存缓存：path -> ScannedFolder。
  final Map<String, ScannedFolder> _folders = {};

  /// 曲库是否已从磁盘加载（避免并发读取时重复恢复）。
  Future<void>? _loading;

  Future<File> get _file async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// 从磁盘恢复曲库（单例首次调用时自动执行，后续调用直接复用内存缓存）。
  ///
  /// 持久化是 best-effort：文件不存在 / 损坏 / 结构不符时返回空库并清空内存，
  /// 任何异常仅记录、不抛出，确保 UI 不会因读盘失败而卡死。
  Future<void> _ensureLoaded() async {
    await (_loading ??= _restore());
  }

  Future<void> _restore() async {
    try {
      final file = await _file;
      if (!await file.exists()) return;

      final raw = await file.readAsString();
      if (raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final root = Map<String, Object?>.from(decoded);

      final tracksJson = root['tracks'];
      if (tracksJson is List) {
        for (final item in tracksJson.whereType<Map>()) {
          final entry = LocalTrackEntry.fromJson(
            Map<String, Object?>.from(item),
          );
          // filePath 是曲目的主键，空值条目无意义，跳过。
          if (entry.filePath.isNotEmpty) {
            _tracks[entry.filePath] = entry;
          }
        }
      }

      final foldersJson = root['folders'];
      if (foldersJson is List) {
        for (final item in foldersJson.whereType<Map>()) {
          final folder = ScannedFolder.fromJson(
            Map<String, Object?>.from(item),
          );
          if (folder.path.isNotEmpty) {
            _folders[folder.path] = folder;
          }
        }
      }
    } catch (e) {
      debugPrint('[LocalMusicService] restore failed: $e');
      _tracks.clear();
      _folders.clear();
    }
  }

  /// 将当前内存曲库写盘（best-effort，失败仅记录）。
  Future<void> _persist() async {
    try {
      final file = await _file;
      final payload = jsonEncode({
        'version': 1,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'tracks': _tracks.values.map((e) => e.toJson()).toList(),
        'folders': _folders.values.map((e) => e.toJson()).toList(),
      });
      await file.writeAsString(payload, flush: true);
    } catch (e) {
      debugPrint('[LocalMusicService] persist failed: $e');
    }
  }

  /// 扫描文件夹下所有音乐文件并入库，返回入库数量。
  Future<int> scanFolder(String folderPath) async {
    await _ensureLoaded();
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      debugPrint('[LocalMusicService] scanFolder: 目录不存在 $folderPath');
      return 0;
    }

    final audioFiles = <File>[];
    await for (final entity
        in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && AudioMetadataReader.isSupported(entity.path)) {
        audioFiles.add(entity);
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    var count = 0;
    for (final file in audioFiles) {
      if (await _importAudioFile(file.path, addedAt: now, folderPath: folderPath)) {
        count++;
      }
    }

    // 文件夹记录仅在成功扫出至少一首歌时写入，避免把空目录/无效目录
    // 留成「已扫描文件夹」，导致用户看不到它其实什么都没导入。
    if (count > 0) {
      _folders[folderPath] = ScannedFolder(path: folderPath, scannedAt: now);
    }

    debugPrint(
      '[LocalMusicService] scanFolder: 扫描 $folderPath，导入 $count 首歌曲',
    );
    await _persist();
    return count;
  }

  /// 导入指定文件路径列表，返回成功导入数量。
  Future<int> importFiles(List<String> filePaths) async {
    await _ensureLoaded();
    final now = DateTime.now().millisecondsSinceEpoch;
    var count = 0;

    for (final filePath in filePaths) {
      if (await _importAudioFile(filePath, addedAt: now)) {
        count++;
      }
    }

    debugPrint(
      '[LocalMusicService] importFiles: 导入 $count/${filePaths.length} 首歌曲',
    );
    await _persist();
    return count;
  }

  /// 导入 Android 原生通道返回的结果（复制后的真实文件）。
  ///
  /// 原生侧已完成选文件/选文件夹与复制，这里按「真实路径 + 原始文件名」入库；
  /// [LocalMusicNative.ImportedNativeFile.sidecarLrcPath] 非空时，歌词直接来自
  /// 同批复制的 .lrc 内容。返回成功导入数量。
  Future<int> importNativeFiles(
    List<ImportedNativeFile> files,
  ) async {
    await _ensureLoaded();
    final now = DateTime.now().millisecondsSinceEpoch;
    var count = 0;

    for (final file in files) {
      if (file.filePath.isEmpty) continue;
      if (!await _importAudioFile(
        file.filePath,
        addedAt: now,
        displayName: file.displayName,
      )) {
        continue;
      }
      count++;
    }

    await _persist();
    return count;
  }

  /// 解析单个音频文件并入库（folderPath 非空表示来自文件夹扫描）。
  ///
  /// [displayName]：原生导入时保留的原始文件名，元数据解析失败时用作兜底显示名；
  /// 其余导入路径可传 null，由文件名兜底。
  ///
  /// 解析失败时仍以文件名兜底导入，返回 true；格式不支持或文件不存在返回
  /// false。歌词优先内嵌，其次读取同名 .lrc 文件，均无则 hasLrcFile=false。
  Future<bool> _importAudioFile(
    String filePath, {
    required int addedAt,
    String? folderPath,
    String? displayName,
  }) async {
    final resolvedPath = await _resolveImportPath(filePath);
    if (resolvedPath == null || !AudioMetadataReader.isSupported(resolvedPath)) {
      debugPrint('[LocalMusicService] 跳过不支持的格式 $filePath');
      return false;
    }

    final file = File(resolvedPath);
    if (!await file.exists()) {
      debugPrint('[LocalMusicService] 文件不存在 $resolvedPath');
      return false;
    }

    final hasLrcFile = await _hasLrcFile(resolvedPath);
    // 内嵌歌词优先；没有内嵌时读取同名 .lrc 文件内容随曲目一并缓存，
    // 使播放器（读 track.lyric）无需再单独访问磁盘即可显示歌词。
    final sidecarLyric = hasLrcFile ? await _readSidecarLrc(resolvedPath) : null;

    var name = displayName?.isNotEmpty == true
        ? _baseName(displayName!)
        : _baseName(resolvedPath);
    var artists = '';
    var album = '';
    var duration = 0.0;
    String? coverDataUrl;
    String? lyric = sidecarLyric;
    try {
      final metadata = await AudioMetadataReader.read(resolvedPath);
      name = metadata.name.isNotEmpty ? metadata.name : name;
      artists = metadata.artists;
      album = metadata.album;
      duration = metadata.duration;
      coverDataUrl = metadata.coverDataUrl;
      if (metadata.lyric != null && metadata.lyric!.isNotEmpty) {
        lyric = metadata.lyric;
      }
    } catch (e) {
      debugPrint('[LocalMusicService] 解析失败 $resolvedPath: $e');
    }

    _tracks[resolvedPath] = LocalTrackEntry(
      filePath: resolvedPath,
      name: name,
      artists: artists,
      album: album,
      duration: duration,
      coverDataUrl: coverDataUrl,
      lyric: lyric,
      hasLrcFile: hasLrcFile,
      addedAt: addedAt,
      folderPath: folderPath,
    );
    return true;
  }

  /// 解析 `content://` 等非文件路径为可被 `dart:io` 读取的真实文件。
  ///
  /// 原生通道返回的已是复制后的 `file://` 路径，这里只是兜底：若仍拿到
  /// `content://`（例如 file_picker 的缓存路径意外透传），通过 [LocalMusicNative]
  /// 无对应能力时返回 null。普通文件路径原样返回。
  Future<String?> _resolveImportPath(String filePath) async {
    if (filePath.startsWith('content://')) {
      // 原生插件不提供 content:// → file:// 的单文件拷贝能力；此类路径
      // 属于异常输入，直接拒绝，避免 `File(content://...)` 抛错。
      debugPrint('[LocalMusicService] 不支持的 content:// 路径 $filePath');
      return null;
    }
    return filePath;
  }

  /// 获取所有本地音轨，按 [LocalTrackEntry.addedAt] 倒序。
  Future<List<LocalTrackEntry>> getAll() async {
    await _ensureLoaded();
    final entries = _tracks.values.toList();
    entries.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return entries;
  }

  /// 按关键字搜索本地音轨（匹配名称 / 艺术家 / 专辑，大小写不敏感）。
  Future<List<LocalTrackEntry>> search(String keyword) async {
    final all = await getAll();
    final kw = keyword.toLowerCase();
    return all
        .where(
          (t) =>
              t.name.toLowerCase().contains(kw) ||
              t.artists.toLowerCase().contains(kw) ||
              t.album.toLowerCase().contains(kw),
        )
        .toList();
  }

  /// 按 [filePath] 删除单条记录。
  Future<void> remove(String filePath) async {
    await _ensureLoaded();
    _tracks.remove(filePath);
    await _persist();
  }

  /// 按文件夹删除所有该文件夹下扫描的音轨，同时移除文件夹记录。
  Future<void> removeByFolder(String folderPath) async {
    await _ensureLoaded();
    _tracks.removeWhere((_, entry) => entry.folderPath == folderPath);
    _folders.remove(folderPath);
    await _persist();
  }

  /// 获取已扫描的文件夹列表。
  Future<List<ScannedFolder>> getFolders() async {
    await _ensureLoaded();
    return _folders.values.toList();
  }

  /// 重新扫描文件夹（先删后扫）。
  Future<int> rescanFolder(String folderPath) async {
    await removeByFolder(folderPath);
    return scanFolder(folderPath);
  }

  /// 将本地音轨条目转换为 [Track] 模型。
  ///
  /// 注意：[LocalTrackEntry.duration] 在 Tauri 端按秒返回，Flutter 端转换为
  /// [Duration]（毫秒）。
  Track toTrack(LocalTrackEntry entry) {
    return Track(
      id: entry.filePath,
      name: entry.name,
      artists: entry.artists,
      album: entry.album,
      picUrl: entry.coverDataUrl ?? '',
      source: MusicSource.local,
      lyric: entry.lyric,
      duration: Duration(milliseconds: (entry.duration * 1000).round()),
      filePath: entry.filePath,
    );
  }

  /// 读取音频文件对应的 .lrc 歌词文件内容。
  ///
  /// 查找与音频文件同目录、同名的 .lrc 文件（大小写不敏感）。
  /// 若音频文件本身内嵌了歌词（[LocalTrackEntry.lyric]），优先返回内嵌歌词。
  Future<String?> loadLrcForTrack(Track track) async {
    await _ensureLoaded();
    if (track.filePath == null || track.filePath!.isEmpty) {
      // 内嵌歌词回退
      return track.lyric;
    }

    // 先查缓存中是否有内嵌歌词
    final entry = _tracks[track.filePath];
    if (entry?.lyric != null && entry!.lyric!.isNotEmpty) {
      return entry.lyric;
    }

    // 尝试读取同名 .lrc 文件
    final audioPath = track.filePath!;
    final dir = p.dirname(audioPath);
    final nameWithoutExt = p.basenameWithoutExtension(audioPath);

    // 尝试 .lrc 和 .LRC
    for (final ext in ['.lrc', '.LRC']) {
      final lrcPath = p.join(dir, nameWithoutExt + ext);
      final lrcFile = File(lrcPath);
      if (await lrcFile.exists()) {
        try {
          return await lrcFile.readAsString();
        } catch (e) {
          debugPrint('[LocalMusicService] loadLrcForTrack: 读取 .lrc 失败: $e');
        }
      }
    }

    return null;
  }

  // -------------------------------------------------------------------------
  // 私有辅助
  // -------------------------------------------------------------------------

  /// 检查同名 .lrc 文件是否存在。
  Future<bool> _hasLrcFile(String audioPath) async {
    final dir = p.dirname(audioPath);
    final nameWithoutExt = p.basenameWithoutExtension(audioPath);
    for (final ext in ['.lrc', '.LRC']) {
      final lrcPath = p.join(dir, nameWithoutExt + ext);
      if (await File(lrcPath).exists()) return true;
    }
    return false;
  }

  /// 读取音频文件对应的同名 .lrc 文件内容（大小写不敏感）。
  ///
  /// .lrc 常见 UTF-8（无 BOM）与 GBK 两种编码；UTF-8 严格解码失败时按
  /// GBK 回退解码，避免中文歌词乱码。仍失败返回 null。
  Future<String?> _readSidecarLrc(String audioPath) async {
    final dir = p.dirname(audioPath);
    final nameWithoutExt = p.basenameWithoutExtension(audioPath);
    for (final ext in ['.lrc', '.LRC']) {
      final lrcFile = File(p.join(dir, nameWithoutExt + ext));
      if (!await lrcFile.exists()) continue;
      try {
        final bytes = await lrcFile.readAsBytes();
        return _decodeLrcBytes(bytes);
      } catch (e) {
        debugPrint('[LocalMusicService] 读取 .lrc 失败: $e');
      }
    }
    return null;
  }

  /// 解码 .lrc 字节：优先 UTF-8（容错宽松），失败则回退 GBK。
  static String _decodeLrcBytes(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    // 出现替换字符（U+FFFD）说明不是合法 UTF-8，按 GBK 重解。
    if (text.contains('\uFFFD')) {
      try {
        return gbk.decode(bytes);
      } catch (_) {
        // GBK 解码失败则保留 UTF-8 结果
      }
    }
    return text;
  }

  static String _baseName(String path) {
    var name = p.basenameWithoutExtension(path);
    return name;
  }
}
