import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/album.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';

/// 专辑详情服务（对应 Next.js demo/lib/services/albumService.ts）。
///
/// 单例。公开接口，无需鉴权。
class AlbumService {
  AlbumService._();
  static final AlbumService instance = AlbumService._();

  Map<String, Object?> _decode(http.Response response) {
    try {
      final payload = jsonDecode(response.body);
      return payload is Map ? Map<String, Object?>.from(payload) : const {};
    } catch (e) {
      debugPrint('[AlbumService] decode failed: $e');
      return const {};
    }
  }

  bool _ok(http.Response response) =>
      response.statusCode >= 200 && response.statusCode < 300;

  /// 获取专辑详情。
  Future<AlbumDetailInfo?> fetchAlbumDetail(Object id) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/album?id=$id',
      );
      if (!_ok(response)) return null;
      final data = _decode(response);
      // 后端返回格式: { status: 200, success: true, data: { album: { ...albumInfo, songs: [...] } } }
      if (data['status'] != 200) return null;
      final dataRoot = data['data'];
      if (dataRoot is! Map) return null;
      final albumRaw = dataRoot['album'];
      if (albumRaw is! Map) return null;
      final albumMap = Map<String, Object?>.from(albumRaw);

      // songs 嵌套在 album 对象内，需要提取出来
      final songs =
          (albumMap['songs'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, Object?>.from(e))
              .toList() ??
          const <Map<String, Object?>>[];

      // 构建 album 对象，确保 artist 字段为对象格式（页面使用 album.artist?.name）
      final picUrl = albumMap['coverImgUrl'] ?? albumMap['picUrl'] ?? '';
      final artistRaw = albumMap['artist'];
      final Object artist;
      if (artistRaw is String) {
        artist = <String, Object?>{'name': artistRaw};
      } else if (artistRaw is Map) {
        artist = Map<String, Object?>.from(artistRaw);
      } else {
        artist = <String, Object?>{'name': ''};
      }

      final album = Map<String, Object?>.from(albumMap)
        ..remove('songs') // 避免重复
        ..['picUrl'] = picUrl.toString()
        ..['artist'] = artist;

      return AlbumDetailInfo(album: album, songs: songs);
    } catch (e) {
      debugPrint('Failed to fetch album detail: $e');
      return null;
    }
  }
}
