import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';
import '../search/kugou_track_dto.dart';
import '../search/netease_track_dto.dart';

/// 跨平台播放兜底匹配结果（对应播放器内「原平台无直链时换平台可播」）。
class CrossPlatformFallbackMatch {
  const CrossPlatformFallbackMatch({
    required this.source,
    required this.id,
    required this.score,
    required this.track,
  });

  /// 兜底平台（netease / kugou）。
  final MusicSource source;

  /// 兜底平台上的歌曲 ID。
  final String id;

  /// 匹配得分，0~1，越高越相近。
  final double score;

  /// 已按新的 [source]/[id] 重映射的 [Track]（保留原曲名/歌手等展示信息，
  /// 供播放与写回歌单使用）。
  final Track track;
}

/// 跨平台兜底查找能力的抽象。实现见 [CrossPlatformFallbackService]；
/// 测试可注入假实现。
abstract interface class CrossPlatformFallbackFinder {
  Future<List<CrossPlatformFallbackMatch>> findFallbackFor(
    Track track, {
    int limit,
  });
}

/// 跨平台兜底搜索服务。
///
/// 当歌单内对应平台的 API 无法返回有效直链（如 QQ 普通账号无 VIP）时，
/// 并行请求网易云与酷狗搜索接口，按「歌曲名 + 歌手名」找到最相近的歌曲，
/// 供播放器回退到其它平台取流。网易云优先于酷狗。
class CrossPlatformFallbackService
    implements CrossPlatformFallbackFinder {
  CrossPlatformFallbackService({ApiClient? apiClient, UrlService? urls})
    : _apiClient = apiClient ?? ApiClient.instance,
      _urls = urls ?? UrlService.instance;

  final ApiClient _apiClient;
  final UrlService _urls;

  /// 网易云/酷狗搜索超时阈值。
  static const Duration _searchTimeout = Duration(seconds: 6);

  Map<String, Object?> _decode(http.Response response) {
    try {
      final payload = jsonDecode(response.body);
      return payload is Map ? Map<String, Object?>.from(payload) : const {};
    } catch (_) {
      return const {};
    }
  }

  List<Map<String, Object?>> _asListOfMaps(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, Object?>.from(e))
        .toList(growable: false);
  }

  /// 给定一首无法在原平台取到直链的歌曲，并行搜索网易云与酷狗，
  /// 返回按「相近度降序、网易云优先」排序的候选匹配。
  @override
  Future<List<CrossPlatformFallbackMatch>> findFallbackFor(
    Track track, {
    int limit = 12,
  }) async {
    final keyword = _buildKeyword(track);
    if (keyword.isEmpty) return const [];

    final neteaseFuture = _searchNetease(keyword, limit);
    final kugouFuture = _searchKugou(keyword, limit);

    final neteaseTracks = await neteaseFuture;
    final kugouTracks = await kugouFuture;

    final matches = <CrossPlatformFallbackMatch>[];
    for (final t in neteaseTracks) {
      final score = _similarity(track, t);
      if (score > 0.35) {
        matches.add(
          CrossPlatformFallbackMatch(
            source: t.source,
            id: t.id,
            score: score,
            track: _remapped(track, t),
          ),
        );
      }
    }
    // 网易云优先：先放网易云命中（同分时网易云在前），酷狗候选排后。
    for (final t in kugouTracks) {
      final score = _similarity(track, t);
      if (score > 0.35) {
        matches.add(
          CrossPlatformFallbackMatch(
            source: t.source,
            id: t.id,
            score: score,
            track: _remapped(track, t),
          ),
        );
      }
    }

    // 平台权重：网易云 +0.02，其它 +0，避免酷狗高分压过网易云接近同名的歌。
    matches.sort((a, b) {
      final aScore = a.score + (a.source == MusicSource.netease ? 0.02 : 0);
      final bScore = b.score + (b.source == MusicSource.netease ? 0.02 : 0);
      return bScore.compareTo(aScore);
    });
    return matches;
  }

  /// 构造搜索关键词：原歌名为主，歌名过短时拼接歌手名以提升区分度。
  String _buildKeyword(Track track) {
    final name = track.name.trim();
    if (name.length >= 2) return name;
    final artists = track.artists.trim();
    if (artists.isEmpty) return name;
    return '$name $artists';
  }

  Future<List<Track>> _searchNetease(String keyword, int limit) async {
    try {
      final response = await _apiClient
          .apiFetch(
            _urls.searchUrl,
            method: 'POST',
            headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {'keywords': keyword, 'limit': '$limit'},
          )
          .timeout(_searchTimeout);
      final data = _decode(response);
      if (data['status'] == 200) {
        final nameToId = <String, Track>{};
        for (final e in _asListOfMaps(data['result'])) {
          final t = NeteaseTrackDto(e).toTrack();
          if (t.id.isEmpty) continue;
          nameToId['${t.name}|${t.artists}'] = t;
        }
        return nameToId.values.toList(growable: false);
      }
      return const [];
    } catch (e) {
      debugPrint('[CrossPlatformFallback] netease search failed: $e');
      return const [];
    }
  }

  Future<List<Track>> _searchKugou(String keyword, int limit) async {
    try {
      final response = await _apiClient
          .apiFetch(
            '${_urls.kugouSearchUrl}?keywords=${Uri.encodeQueryComponent(keyword)}&limit=$limit',
          )
          .timeout(_searchTimeout);
      final data = _decode(response);
      if (data['status'] == 200) {
        final nameToId = <String, Track>{};
        for (final e in _asListOfMaps(data['result'])) {
          final t = KugouTrackDto(e).toTrack();
          if (t.id.isEmpty) continue;
          nameToId['${t.name}|${t.artists}'] = t;
        }
        return nameToId.values.toList(growable: false);
      }
      return const [];
    } catch (e) {
      debugPrint('[CrossPlatformFallback] kugou search failed: $e');
      return const [];
    }
  }

  /// 以「原始曲目」为基准，把命中曲目的展示字段替换为原曲展示字段，
  /// 但换上新平台的 id/source，供播放与后续取流。
  Track _remapped(Track original, Track hit) => Track(
    id: hit.id,
    name: original.name,
    artists: original.artists,
    album: original.album,
    picUrl: original.picUrl,
    source: hit.source,
    duration: original.duration,
  );

  /// 歌曲名 + 歌手名的综合相似度（归一化后，0~1）。
  double _similarity(Track a, Track b) {
    final nameA = _normalize(a.name);
    final nameB = _normalize(b.name);
    final artistA = _normalize(a.artists);
    final artistB = _normalize(b.artists);

    final nameSim = _jaccard(nameA, nameB);
    final artistSim = _jaccard(artistA, artistB);
    // 歌名权重更高；歌手贡献次之。歌名完全一致时已趋于 1，避免被歌手
    // 拼写细节拖低到无法触发兜底。
    return nameSim * 0.7 + artistSim * 0.3;
  }

  /// 归一化：小写、去空白、替换常见分隔符，用于跨平台比较。
  static String _normalize(String src) => src
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[、/&，,\-—_()（）\[\]【】.]'), '、');

  /// 有序字符集合的 Jaccard 相似度（0~1）。对 CJK 文本切分为单字后比较，
  /// 对拼音/英文则退化为公共子序列。
  static double _jaccard(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1.0;
    final setA = _bigrams(a);
    final setB = _bigrams(b);
    final inter = setA.where(setB.contains).length;
    final union = setA.union(setB).length;
    if (union == 0) return 0;
    return inter / union;
  }

  /// 连续两两组合（bigram）集合。单字串退化为单字。
  static Set<String> _bigrams(String s) {
    if (s.isEmpty) return const {};
    if (s.length == 1) return {s};
    final out = <String>{};
    for (var i = 0; i < s.length - 1; i++) {
      out.add(s.substring(i, i + 2));
    }
    return out;
  }
}