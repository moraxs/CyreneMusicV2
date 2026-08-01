import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/comment.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';

/// QQ 音乐评论服务（对应 Next.js demo/lib/services/qqCommentService.ts）。
///
/// 单例。后端 `/qq/comment/music` 已将 QQ 原始评论归一化为与网易云相同的结构，
/// 因此这里复用 [SongComments] / [CommentItem] 类型，前端评论组件可对两种音源共用
/// 同一套渲染逻辑。
class QqCommentService {
  QqCommentService._();
  static final QqCommentService instance = QqCommentService._();

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

  /// 获取 QQ 音乐评论（按页码分页）。
  ///
  /// [id] 资源 ID（QQ 轨道的 songmid，后端会自动解析为数字 songid）。
  /// [pagesize] 每页评论数，默认 20。[pagenum] 页码，从 0 开始。
  /// [sortType] 排序方式：0=按时间（默认），1=按热度。
  Future<SongComments?> fetchSongComments(
    Object id, {
    int pagesize = 20,
    int pagenum = 0,
    int sortType = 0,
  }) async {
    try {
      final url =
          '${UrlService.instance.baseUrl}/qq/comment/music?id=${Uri.encodeQueryComponent(id.toString())}'
          '&pagesize=${Uri.encodeQueryComponent(pagesize.toString())}'
          '&pagenum=${Uri.encodeQueryComponent(pagenum.toString())}'
          '&sortType=${Uri.encodeQueryComponent(sortType.toString())}';
      final response = await ApiClient.instance.apiFetch(url);
      if (!_ok(response)) return null;
      final data = _decode(response);
      if (data['status'] != 200) return null;
      // 后端返回的 total/more/moreHot/hotComments/comments 字段与 SongComments 同名，
      // fromJson 已应用与 TS 源一致的默认值（?? 0 / == true / 缺省空列表）。
      return SongComments.fromJson(data);
    } catch (e) {
      debugPrint('[QqCommentService] 获取歌曲评论失败: $e');
      return null;
    }
  }
}
