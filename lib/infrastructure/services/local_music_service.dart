import 'package:flutter/foundation.dart';

import '../../domain/models/local_track.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';

/// 本地音乐服务（对应 Next.js demo/lib/services/localMusicService.ts）。
///
/// 单例。Next.js 端使用 IndexedDB 持久化本地音轨，并通过 Tauri `invoke`
/// （`scan_music_folder` / `get_audio_metadata` / `read_lrc_file`）调用 Rust
/// 后端扫描文件夹与解析元数据。
///
/// Flutter 侧移植策略：
/// - **持久化**：原 IndexedDB 改为内存 Map 缓存（`_tracks` / `_folders`），
///   待 store 层（如 sqflite / shared_preferences）接管后替换。
/// - **文件扫描 / 元数据解析**：原 Tauri invoke 在 Flutter 侧没有对应实现，
///   保留方法签名 + TODO 注释。完整实现需要：
///   - 移动端：`path_provider` + platform channel 调用原生 MediaStore（Android）/
///     MPMediaPredicate（iOS）；元数据可用 `on_audio_query` 或原生 AVFoundation。
///   - 桌面端：可直接基于 `dart:io` 递归遍历音频扩展名 + `audiotags` / 原生库
///     解析元数据。
/// - 不引入新的 pub 依赖。
class LocalMusicService {
  LocalMusicService._();
  static final LocalMusicService instance = LocalMusicService._();

  /// 内存缓存：filePath -> LocalTrackEntry。
  final Map<String, LocalTrackEntry> _tracks = {};

  /// 内存缓存：path -> ScannedFolder。
  final Map<String, ScannedFolder> _folders = {};

  /// 扫描文件夹下所有音乐文件并入库，返回入库数量。
  ///
  /// TODO(platform): Next.js 通过 Tauri `invoke('scan_music_folder', {path})`
  /// 调用 Rust 后端完成递归扫描与元数据解析。Flutter 侧需要：
  /// - 移动端：`path_provider` + platform channel 调用原生 MediaStore / MPMediaPredicate。
  /// - 桌面端：可基于 `dart:io` 递归遍历音频扩展名（mp3/flac/wav/m4a/ape/ogg），
  ///   配合 `audiotags` 或原生库解析元数据。
  /// 当前实现仅记录扫描文件夹，返回 0（未扫描任何文件）。
  Future<int> scanFolder(String folderPath) async {
    debugPrint(
      '[LocalMusicService] scanFolder TODO: requires platform channel + '
      'path_provider to scan $folderPath on Flutter.',
    );
    _folders[folderPath] = ScannedFolder(
      path: folderPath,
      scannedAt: DateTime.now().millisecondsSinceEpoch,
    );
    return 0;
  }

  /// 导入指定文件路径列表，返回成功导入数量。
  ///
  /// TODO(platform): Next.js 通过 Tauri `invoke('get_audio_metadata', {path})`
  /// 解析单文件元数据。Flutter 侧需要 platform channel 实现，当前返回 0。
  Future<int> importFiles(List<String> filePaths) async {
    debugPrint(
      '[LocalMusicService] importFiles TODO: requires platform channel to parse '
      'audio metadata for ${filePaths.length} files.',
    );
    return 0;
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
  /// TODO(platform): Next.js 通过 Tauri `invoke('read_lrc_file', {audioPath})`
  /// 读取同名 .lrc 文件。Flutter 侧需要 `dart:io`（桌面端）或 platform channel
  /// （移动端沙盒访问）实现。当前返回 null。
  Future<String?> loadLrcForTrack(Track track) async {
    if (track.filePath == null || track.filePath!.isEmpty) return null;
    debugPrint(
      '[LocalMusicService] loadLrcForTrack TODO: requires dart:io or platform '
      'channel to read .lrc file for ${track.filePath}.',
    );
    return null;
  }
}
