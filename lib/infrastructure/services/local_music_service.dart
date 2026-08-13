import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/local_track.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';
import 'audio_metadata_reader.dart';

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

  /// 内存缓存：filePath -> LocalTrackEntry。
  final Map<String, LocalTrackEntry> _tracks = {};

  /// 内存缓存：path -> ScannedFolder。
  final Map<String, ScannedFolder> _folders = {};

  /// 扫描文件夹下所有音乐文件并入库，返回入库数量。
  Future<int> scanFolder(String folderPath) async {
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
    _folders[folderPath] = ScannedFolder(path: folderPath, scannedAt: now);

    var count = 0;
    for (final file in audioFiles) {
      final metadata = await AudioMetadataReader.read(file.path);
      _tracks[file.path] = LocalTrackEntry(
        filePath: metadata.filePath,
        name: metadata.name,
        artists: metadata.artists,
        album: metadata.album,
        duration: metadata.duration,
        coverDataUrl: metadata.coverDataUrl,
        lyric: metadata.lyric,
        hasLrcFile: await _hasLrcFile(file.path),
        addedAt: now,
        folderPath: folderPath,
      );
      count++;
    }

    debugPrint(
      '[LocalMusicService] scanFolder: 扫描 $folderPath，导入 $count 首歌曲',
    );
    return count;
  }

  /// 导入指定文件路径列表，返回成功导入数量。
  Future<int> importFiles(List<String> filePaths) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var count = 0;

    for (final filePath in filePaths) {
      if (!AudioMetadataReader.isSupported(filePath)) {
        debugPrint('[LocalMusicService] importFiles: 跳过不支持的格式 $filePath');
        continue;
      }

      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('[LocalMusicService] importFiles: 文件不存在 $filePath');
        continue;
      }

      try {
        final metadata = await AudioMetadataReader.read(filePath);
        _tracks[filePath] = LocalTrackEntry(
          filePath: metadata.filePath,
          name: metadata.name,
          artists: metadata.artists,
          album: metadata.album,
          duration: metadata.duration,
          coverDataUrl: metadata.coverDataUrl,
          lyric: metadata.lyric,
          hasLrcFile: await _hasLrcFile(filePath),
          addedAt: now,
        );
        count++;
      } catch (e) {
        debugPrint('[LocalMusicService] importFiles: 解析失败 $filePath: $e');
        // 解析失败时仍以文件名导入
        _tracks[filePath] = LocalTrackEntry(
          filePath: filePath,
          name: _baseName(filePath),
          artists: '',
          album: '',
          duration: 0,
          hasLrcFile: await _hasLrcFile(filePath),
          addedAt: now,
        );
        count++;
      }
    }

    debugPrint(
      '[LocalMusicService] importFiles: 导入 $count/${filePaths.length} 首歌曲',
    );
    return count;
  }

  /// 获取所有本地音轨，按 [LocalTrackEntry.addedAt] 倒序。
  Future<List<LocalTrackEntry>> getAll() async {
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
    _tracks.remove(filePath);
  }

  /// 按文件夹删除所有该文件夹下扫描的音轨，同时移除文件夹记录。
  Future<void> removeByFolder(String folderPath) async {
    _tracks.removeWhere((_, entry) => entry.folderPath == folderPath);
    _folders.remove(folderPath);
  }

  /// 获取已扫描的文件夹列表。
  Future<List<ScannedFolder>> getFolders() async {
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

  static String _baseName(String path) {
    var name = p.basenameWithoutExtension(path);
    return name;
  }
}
