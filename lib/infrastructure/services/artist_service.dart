import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/artist.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';

/// 歌手服务（对应 Next.js demo/lib/services/artistService.ts）。
///
/// 单例。公开接口，无需鉴权。
class ArtistService {
  ArtistService._();
  static final ArtistService instance = ArtistService._();

  Map<String, Object?> _decode(http.Response response) {
    try {
      final payload = jsonDecode(response.body);
      return payload is Map ? Map<String, Object?>.from(payload) : const {};
    } catch (e) {
      debugPrint('[ArtistService] decode failed: $e');
      return const {};
    }
  }

  bool _ok(http.Response response) =>
      response.statusCode >= 200 && response.statusCode < 300;

  /// 根据歌手名称解析歌手ID（用于没有返回ID时的聚合搜索）。
  Future<int?> resolveArtistIdByName(String artistName) async {
    if (artistName.isEmpty) return null;
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/artist/search',
        method: 'POST',
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'keywords': artistName, 'limit': '1'},
      );
      if (!_ok(response)) {
        debugPrint(
          '[ArtistService] resolveArtistIdByName Failed HTTP ${response.statusCode}',
        );
        return null;
      }
      final data = _decode(response);
      if (data['status'] == 200) {
        final result = data['result'];
        if (result is List && result.isNotEmpty) {
          final first = result.first;
          if (first is Map) {
            return (first['id'] as num?)?.toInt();
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('[ArtistService] resolveArtistIdByName Error: $e');
      return null;
    }
  }

  /// 获取歌手详情（聚合信息：包含部分热门歌曲和专辑）。
  Future<ArtistDetailInfo?> fetchArtistDetail(Object id) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        '${UrlService.instance.baseUrl}/artist/detail?id=$id',
      );
      if (!_ok(response)) {
        debugPrint(
          '[ArtistService] fetchArtistDetail Failed HTTP ${response.statusCode}',
        );
        return null;
      }
      final data = _decode(response);
      if (data['status'] == 200 && data['data'] != null) {
        final result = data['data'];
        if (result is! Map) return null;
        // 提取热门单曲
        final songs =
            (result['songs'] as List?)
                ?.whereType<Map>()
                .map(
                  (item) => Track(
                    id: item['id']?.toString() ?? '',
                    name: item['name']?.toString() ?? '',
                    artists: item['artists']?.toString() ?? '',
                    album: item['album']?.toString() ?? '',
                    picUrl: item['picUrl']?.toString() ?? '',
                    // 这里后端返回的聚合数据默认归为此源
                    source: MusicSource.netease,
                  ),
                )
                .toList() ??
            const <Track>[];
        // 提取专辑信息
        final albums =
            (result['albums'] as List?)
                ?.whereType<Map>()
                .map(
                  (item) => ArtistAlbum(
                    id: (item['id'] as num?)?.toInt() ?? 0,
                    name: item['name']?.toString() ?? '',
                    picUrl: (item['picUrl'] ?? item['coverImgUrl'])?.toString(),
                    company: item['company']?.toString(),
                    publishTime:
                        (item['publishTime'] as num?)?.toInt() ??
                        (item['publish_time'] as num?)?.toInt(),
                  ),
                )
                .toList() ??
            const <ArtistAlbum>[];
        final artistRaw = result['artist'];
        return ArtistDetailInfo(
          artist: artistRaw is Map
              ? ArtistInfo.fromJson(Map<String, Object?>.from(artistRaw))
              : const ArtistInfo(id: 0, name: ''),
          songs: songs,
          albums: albums,
        );
      }
      return null;
    } catch (e) {
      debugPrint('[ArtistService] fetchArtistDetail Error: $e');
      return null;
    }
  }
}
