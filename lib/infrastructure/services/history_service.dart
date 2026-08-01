import 'package:flutter/foundation.dart';

import '../../domain/models/history.dart';
import '../../domain/models/track.dart';

/// 播放记录服务（对应 Next.js demo/lib/services/historyService.ts）。
///
/// 单例。原 Next.js 端基于 IndexedDB 持久化播放历史；Flutter 端无 IndexedDB 等价物，
/// 此处仅做内存 [Map] 缓存以保留方法签名与逻辑形态，**持久化交给 store 层**（如
/// SharedPreferences / SQLite / Isar 等持久层另行封装）。
class HistoryService {
  HistoryService._();
  static final HistoryService instance = HistoryService._();

  /// 内存缓存，key 为 `id:source`（对应原 IndexedDB 的 [id, source] 复合键）。
  final Map<String, HistoryEntry> _cache = {};

  String _key(String id, String source) => '$id:$source';

  String _normalizeId(Object id) => id.toString().trim();

  /// 记录/更新播放。
  Future<void> recordPlay(Track track) async {
    try {
      final trackId = _normalizeId(track.id);
      final source = track.source.wireName;
      final key = _key(trackId, source);
      final now = DateTime.now().millisecondsSinceEpoch;

      final existing = _cache[key];
      if (existing != null) {
        _cache[key] = existing.copyWith(
          playCount: existing.playCount + 1,
          lastPlayedAt: now,
          firstPlayedAt: existing.firstPlayedAt ?? now,
          // 更新可能变化的元数据。
          name: track.name,
          artists: track.artists,
          album: track.album,
          picUrl: track.picUrl,
        );
      } else {
        _cache[key] = HistoryEntry(
          id: trackId,
          source: source,
          name: track.name,
          artists: track.artists,
          album: track.album,
          picUrl: track.picUrl,
          playCount: 1,
          listeningTime: 0,
          lastPlayedAt: now,
          firstPlayedAt: now,
        );
      }
    } catch (e) {
      debugPrint('[HistoryService] recordPlay failed: $e');
    }
  }

  /// 记录听歌时长。
  Future<void> recordTime(Object trackId, String source, int seconds) async {
    try {
      final sid = _normalizeId(trackId);
      final key = _key(sid, source);
      final existing = _cache[key];
      if (existing != null) {
        _cache[key] = existing.copyWith(
          listeningTime: existing.listeningTime + seconds,
        );
      }
    } catch (e) {
      debugPrint('[HistoryService] recordTime failed: $e');
    }
  }

  /// 获取单个歌曲的历史统计。
  Future<HistoryEntry?> getTrackStats(Object trackId, String source) async {
    try {
      final sid = _normalizeId(trackId);
      return _cache[_key(sid, source)];
    } catch (_) {
      return null;
    }
  }

  /// 获取所有历史记录（按 lastPlayedAt 倒序，对应原 index 的 "prev" 游标）。
  Future<List<HistoryEntry>> getHistory({int limit = 100}) async {
    try {
      final entries = _cache.values.toList()
        ..sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));
      if (entries.length <= limit) return entries;
      return entries.sublist(0, limit);
    } catch (_) {
      return const [];
    }
  }

  /// 获取所有历史记录（无数量限制，用于同步）。
  Future<List<HistoryEntry>> getAll() async {
    try {
      return _cache.values.toList();
    } catch (_) {
      return const [];
    }
  }

  /// 获取统计数据。
  Future<OverallStats> getStats() async {
    try {
      int totalListeningTime = 0;
      int totalPlayCount = 0;
      for (final entry in _cache.values) {
        totalListeningTime += entry.listeningTime;
        totalPlayCount += entry.playCount;
      }
      return OverallStats(
        totalListeningTime: totalListeningTime,
        totalPlayCount: totalPlayCount,
      );
    } catch (_) {
      return const OverallStats(totalListeningTime: 0, totalPlayCount: 0);
    }
  }
}
