import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/comment.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';

/// 网易云歌曲评论服务（对应 Next.js demo/lib/services/neteaseCommentService.ts）。
///
/// 单例。获取歌曲热门评论与最新评论。
class NeteaseCommentService {
  NeteaseCommentService._();
  static final NeteaseCommentService instance = NeteaseCommentService._();

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

  /// 获取歌曲评论（热门评论 + 最新评论）。
  ///
  /// [id] 歌曲 ID。[limit] 取出评论数量，默认 20。[offset] 偏移数量，用于分页。
  /// [before] 分页参数，取上一页最后一项的 time 获取下一页（超过 5000 条评论时使用）。
  /// [sortType] 排序方式：0=按时间（默认），1=按热度。
  Future<SongComments?> fetchSongComments(
    Object id, {
    int limit = 20,
    int offset = 0,
    int before = 0,
    int sortType = 0,
  }) async {
    try {
      final url =
          '${UrlService.instance.baseUrl}/comment/music?id=${Uri.encodeQueryComponent(id.toString())}'
          '&limit=${Uri.encodeQueryComponent(limit.toString())}'
          '&offset=${Uri.encodeQueryComponent(offset.toString())}'
          '&before=${Uri.encodeQueryComponent(before.toString())}'
          '&sortType=${Uri.encodeQueryComponent(sortType.toString())}';
      final response = await ApiClient.instance.apiFetch(url);
      if (!_ok(response)) return null;
      final data = _decode(response);
      if (data['status'] != 200) return null;
      // 后端返回的 total/more/moreHot/hotComments/comments 字段与 SongComments 同名，
      // fromJson 已应用与 TS 源一致的默认值（?? 0 / == true / 缺省空列表）。
      return SongComments.fromJson(data);
    } catch (e) {
      debugPrint('[NeteaseCommentService] 获取歌曲评论失败: $e');
      return null;
    }
  }
}
