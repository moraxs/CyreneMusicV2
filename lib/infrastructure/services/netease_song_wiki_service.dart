import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/song_wiki.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';

/// 网易云歌曲百科服务（对应 Next.js demo/lib/services/neteaseSongWikiService.ts）。
///
/// 单例。提供歌曲百科摘要、音轨元数据、发行时间、语种查询，并对发行时间与语种做
/// 进程内缓存与并发去重（避免短时间内同曲目并发触发多次请求）。
class NeteaseSongWikiService {
  NeteaseSongWikiService._();
  static final NeteaseSongWikiService instance = NeteaseSongWikiService._();

  // 进程内语言缓存：避免同一首歌反复请求百科。
  // 已查询但无语言的曲目缓存为空字符串，避免每次切歌都重新请求。
  final Map<String, String> _languageCache = {};
  // 进行中的请求缓存：避免短时间内同曲目并发触发多次请求。
  final Map<String, Future<String>> _inflightLanguage = {};

  // 发行时间缓存与并发去重，同上。
  final Map<String, int> _publishTimeCache = {};
  final Map<String, Future<int>> _inflightPublishTime = {};

  Map<String, Object?> _decode(http.Response response) {
    try {
      final payload = jsonDecode(response.body);
      return payload is Map ? Map<String, Object?>.from(payload) : const {};
    } catch (_) {
      return const {};
    }
  }

  bool _ok(http.Response response) =>
      response.statusCode >= 200 && response.statusCode < 300;

  /// 获取歌曲百科摘要 (Wiki Summary)。
  /// 包含：曲风、语种、发行时间、简介等。
  Future<SongWikiSummary?> fetchSongWiki(Object id) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/song/wiki/summary?id=${Uri.encodeQueryComponent(id.toString())}',
      );
      if (!_ok(response)) return null;
      final data = _decode(response);
      if (data['status'] != 200) return null;
      final wikiData = data['data'];
      if (wikiData is! Map) return null;
      return SongWikiSummary.fromJson(Map<String, Object?>.from(wikiData));
    } catch (e) {
      debugPrint('[NeteaseSongWikiService] 获取百科失败: $e');
      return null;
    }
  }

  /// 获取歌曲音轨详细信息 (Music Detail)。
  /// 包含：BPM、能量值、情感倾向等。结构由后端定义，这里以原始 Map 返回。
  Future<Map<String, Object?>?> fetchSongMusicDetail(Object id) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/song/music/detail/get?id=${Uri.encodeQueryComponent(id.toString())}',
      );
      if (!_ok(response)) return null;
      final data = _decode(response);
      if (data['status'] != 200) return null;
      final detail = data['data'];
      return detail is Map ? Map<String, Object?>.from(detail) : null;
    } catch (e) {
      debugPrint('[NeteaseSongWikiService] 获取歌曲元数据失败: $e');
      return null;
    }
  }

  /// 获取歌曲发行时间（毫秒时间戳）。
  /// 进程内缓存：避免同一首歌反复请求。
  Future<int> fetchPublishTime(Object id) async {
    final key = id.toString();

    if (_publishTimeCache.containsKey(key)) {
      return _publishTimeCache[key] ?? 0;
    }
    final inflight = _inflightPublishTime[key];
    if (inflight != null) return inflight;

    final task = _fetchPublishTimeTask(id, key);
    _inflightPublishTime[key] = task;
    return task;
  }

  Future<int> _fetchPublishTimeTask(Object id, String key) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/song/publish-time?id=${Uri.encodeQueryComponent(id.toString())}',
      );
      if (!_ok(response)) return 0;
      final data = _decode(response);
      final pub = data['status'] == 200
          ? ((data['publishTime'] as num?)?.toInt() ?? 0)
          : 0;
      _publishTimeCache[key] = pub;
      return pub;
    } catch (e) {
      debugPrint('[NeteaseSongWikiService] 获取歌曲发行时间失败: $e');
      return 0;
    } finally {
      _inflightPublishTime.remove(key);
    }
  }

  /// 仅获取歌曲语种（轻量、带缓存），用于听歌语言统计。
  /// 命中缓存（含空字符串）则直接返回，未命中时复用 [fetchSongWiki] 并解析
  /// `creativeType === 'language'`。
  Future<String> fetchSongLanguage(Object id) async {
    final key = id.toString();

    if (_languageCache.containsKey(key)) {
      return _languageCache[key] ?? '';
    }
    final inflight = _inflightLanguage[key];
    if (inflight != null) return inflight;

    final task = _fetchSongLanguageTask(id, key);
    _inflightLanguage[key] = task;
    return task;
  }

  Future<String> _fetchSongLanguageTask(Object id, String key) async {
    try {
      final data = await fetchSongWiki(id);
      final language = _extractLanguage(data);
      _languageCache[key] = language;
      return language;
    } catch (e) {
      debugPrint('[NeteaseSongWikiService] 获取歌曲语言失败: $e');
      return '';
    } finally {
      _inflightLanguage.remove(key);
    }
  }

  /// 从百科摘要中提取语种。
  /// 查找 code 为 `SONG_PLAY_ABOUT_SONG_BASIC` 的 block，再在其 creatives 中
  /// 找 `creativeType === 'language'`，取首个 textLink 的 text。
  String _extractLanguage(SongWikiSummary? data) {
    final blocks = data?.blocks;
    if (blocks == null) return '';
    WikiBlock? basicBlock;
    for (final b in blocks) {
      if (b.code == 'SONG_PLAY_ABOUT_SONG_BASIC') {
        basicBlock = b;
        break;
      }
    }
    final creatives = basicBlock?.creatives ?? const <WikiCreative>[];
    for (final creative in creatives) {
      if (creative.creativeType == 'language') {
        final textLinks =
            creative.uiElement?.textLinks ?? const <WikiTextLink>[];
        if (textLinks.isNotEmpty && textLinks.first.text.isNotEmpty) {
          return textLinks.first.text;
        }
      }
    }
    return '';
  }
}
