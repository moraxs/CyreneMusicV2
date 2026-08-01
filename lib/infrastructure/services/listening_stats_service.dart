import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/listening_stats.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';

/// 听歌统计服务（对应 Next.js demo/lib/services/listeningStatsService.ts）。
///
/// 单例。负责把听歌时长 / 播放次数 / 播放事件上报到后端，并拉取用户统计与历史。
///
/// **职责边界**：原 Next.js 版本在构造函数内 `setInterval` 自动同步，并直接读取
/// `useAuthStore`。Flutter 端 service 层不持有 store 也不启动定时器，token 由调用方
/// （store / UI 层）传入；外部 store 若需定时同步，可在外部 `Timer.periodic` 中调用
/// [syncListeningTime]。
class ListeningStatsService {
  ListeningStatsService._();
  static final ListeningStatsService instance = ListeningStatsService._();

  /// 待上报的听歌时长（秒）。对应原 pendingSeconds 字段。
  int _pendingSeconds = 0;

  Map<String, String> _jsonHeaders(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

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

  /// 累积听歌时长。
  ///
  /// @param seconds 秒数
  void accumulateListeningTime(int seconds) {
    _pendingSeconds += seconds;
  }

  /// 同步听歌时长到服务器。
  ///
  /// 调用方需提供有效 [token]；未登录（token 为空）时直接返回。
  Future<void> syncListeningTime(String? token) async {
    if (_pendingSeconds <= 0) return;
    if (token == null || token.isEmpty) return;

    final secondsToSync = _pendingSeconds;
    _pendingSeconds = 0; // 先重置，防止请求期间重复累加。

    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/stats/listening-time',
        method: 'POST',
        headers: _jsonHeaders(token),
        body: jsonEncode({'seconds': secondsToSync}),
      );

      if (!_ok(response)) {
        // 鉴权失败时已由 ApiClient 触发会话过期处理，无需把秒数加回以免反复触发。
        if (!ApiClient.isAuthFailureStatus(response.statusCode)) {
          _pendingSeconds += secondsToSync;
        }
      }
    } catch (e) {
      debugPrint('[ListeningStatsService] syncListeningTime failed: $e');
      _pendingSeconds += secondsToSync; // 异常也加回去。
    }
  }

  /// 记录歌曲播放次数。
  Future<void> recordPlayCount(Track track, String token) async {
    if (token.isEmpty) {
      debugPrint('[ListeningStatsService] 未登录，跳过记录播放次数');
      return;
    }

    final payload = {
      'trackId': track.id.trim(),
      'trackName': track.name.trim(),
      'artists': track.artists.trim(),
      'album': track.album.trim(),
      'picUrl': track.picUrl.trim(),
      'source': track.source.wireName,
    };

    try {
      await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/stats/play-count',
        method: 'POST',
        headers: _jsonHeaders(token),
        body: jsonEncode(payload),
      );
    } catch (e) {
      debugPrint('[ListeningStatsService] recordPlayCount failed: $e');
    }
  }

  /// 记录一次播放事件（后端历史存储）。
  ///
  /// @param track 歌曲对象
  /// @param token 用户 token
  /// @param playDuration 本次播放时长（秒）
  /// @param language 仅 source==='netease' 时携带的歌曲语种（用于听歌语言统计）
  Future<void> recordPlayEvent(
    Track track,
    String token,
    int playDuration, {
    String? language,
  }) async {
    if (token.isEmpty) return;

    final payload = <String, Object?>{
      'trackId': track.id.trim(),
      'trackName': track.name.trim(),
      'artists': track.artists.trim(),
      'album': track.album.trim(),
      'picUrl': track.picUrl.trim(),
      'source': track.source.wireName,
      'playDuration': playDuration.round(),
    };
    if (track.source == MusicSource.netease &&
        language != null &&
        language.trim().isNotEmpty) {
      payload['language'] = language.trim();
    }

    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/history/record',
        method: 'POST',
        headers: _jsonHeaders(token),
        body: jsonEncode(payload),
      );
      if (!_ok(response)) {
        debugPrint(
          '[ListeningStatsService] recordPlayEvent failed: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[ListeningStatsService] recordPlayEvent failed: $e');
    }
  }

  /// 清空服务器保存的播放历史。
  Future<ClearHistoryResult> clearServerHistory(String token) async {
    if (token.isEmpty) {
      return const ClearHistoryResult(success: false, message: '未登录');
    }

    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/history',
        method: 'DELETE',
        headers: {'Authorization': 'Bearer $token'},
      );

      if (_ok(response)) {
        final result = _decode(response);
        return ClearHistoryResult(
          success: true,
          message: result['message']?.toString() ?? '清空成功',
        );
      }
      return ClearHistoryResult(
        success: false,
        message: '请求失败: ${response.statusCode}',
      );
    } catch (e) {
      debugPrint('[ListeningStatsService] clearServerHistory failed: $e');
      return const ClearHistoryResult(success: false, message: '网络异常');
    }
  }

  /// 获取用户统计数据与播放历史。
  ///
  /// 后端 `data` 为对象：{ totalListeningTime, totalPlayCount, playCounts: [...] }。
  Future<ListeningStatsData?> fetchStats(String token) async {
    if (token.isEmpty) return null;

    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/stats',
        headers: {'Authorization': 'Bearer $token'},
      );

      if (_ok(response)) {
        final result = _decode(response);
        return result['data'] is Map
            ? ListeningStatsData.fromJson(
                Map<String, Object?>.from(result['data'] as Map),
              )
            : null;
      }
      debugPrint(
        '[ListeningStatsService] fetchStats failed: ${response.statusCode}',
      );
      return null;
    } catch (e) {
      debugPrint('[ListeningStatsService] fetchStats failed: $e');
      return null;
    }
  }

  /// 获取本周播放的歌曲列表。
  ///
  /// 后端 `data` 为**数组**（与 Next.js `weeklyPlays.slice/length` 一致），
  /// 因此不能按 Map 处理。
  Future<List<WeeklyPlayItem>?> fetchWeeklyPlays(String token) async {
    if (token.isEmpty) return null;

    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/history/weekly',
        headers: {'Authorization': 'Bearer $token'},
      );

      if (_ok(response)) {
        final result = _decode(response);
        final data = result['data'];
        if (data is List) {
          return data
              .whereType<Map>()
              .map((e) => WeeklyPlayItem.fromJson(Map<String, Object?>.from(e)))
              .toList(growable: false);
        }
        return null;
      }
      debugPrint(
        '[ListeningStatsService] fetchWeeklyPlays failed: ${response.statusCode}',
      );
      return null;
    } catch (e) {
      debugPrint('[ListeningStatsService] fetchWeeklyPlays failed: $e');
      return null;
    }
  }

  /// 获取用户播放历史（分页）。
  Future<Map<String, Object?>?> fetchPlayHistory(
    String token, {
    PlayHistoryOptions? options,
  }) async {
    if (token.isEmpty) return null;

    try {
      final qs = (options ?? const PlayHistoryOptions()).toQueryString();
      final url = qs.isEmpty
          ? '${UrlService.instance.baseUrl}/history'
          : '${UrlService.instance.baseUrl}/history?$qs';

      final response = await ApiClient.instance.apiFetch(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (_ok(response)) {
        final result = _decode(response);
        return result['data'] is Map
            ? Map<String, Object?>.from(result['data'] as Map)
            : null;
      }
      return null;
    } catch (e) {
      debugPrint('[ListeningStatsService] fetchPlayHistory failed: $e');
      return null;
    }
  }

  /// 获取用户对特定歌曲的回忆坐标。
  ///
  /// @param trackId 歌曲ID
  /// @param source 音乐平台来源
  Future<Map<String, Object?>?> fetchSongMemory(
    Object trackId,
    String source,
    String token,
  ) async {
    if (token.isEmpty) return null;

    try {
      final url =
          '${UrlService.instance.baseUrl}/stats/song-memory?trackId=${Uri.encodeQueryComponent(trackId.toString())}&source=${Uri.encodeQueryComponent(source)}';
      final response = await ApiClient.instance.apiFetch(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (_ok(response)) {
        final result = _decode(response);
        if (result['code'] == 200) {
          return result['data'] is Map
              ? Map<String, Object?>.from(result['data'] as Map)
              : null;
        }
        return null;
      }
      debugPrint(
        '[ListeningStatsService] fetchSongMemory failed: ${response.statusCode}',
      );
      return null;
    } catch (e) {
      debugPrint('[ListeningStatsService] fetchSongMemory failed: $e');
      return null;
    }
  }

  /// 获取听歌语言统计（仅网易云歌曲参与）。
  Future<LanguageStatsData?> fetchLanguageStats(String token) async {
    if (token.isEmpty) return null;

    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/stats/languages',
        headers: {'Authorization': 'Bearer $token'},
      );

      if (_ok(response)) {
        final result = _decode(response);
        return result['data'] is Map
            ? LanguageStatsData.fromJson(
                Map<String, Object?>.from(result['data'] as Map),
              )
            : null;
      }
      debugPrint(
        '[ListeningStatsService] fetchLanguageStats failed: ${response.statusCode}',
      );
      return null;
    } catch (e) {
      debugPrint('[ListeningStatsService] fetchLanguageStats failed: $e');
      return null;
    }
  }

  /// 释放资源。Flutter 端定时器由外部管理，此处保留方法以兼容原签名。
  void cleanup() {}
}
