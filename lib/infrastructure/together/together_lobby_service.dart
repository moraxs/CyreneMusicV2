import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/together/together_models.dart';
import '../core/api_client.dart';
import '../core/url_service.dart';

/// 一起听大厅的只读接口（房间列表 / 房间预览）。
///
/// 房间本身的状态同步走 WebSocket，见 [TogetherClient]；这里只服务「进房之前」
/// 的浏览与校验。
class TogetherLobbyService {
  TogetherLobbyService({ApiClient? apiClient, UrlService? urls})
    : _apiClient = apiClient ?? ApiClient.instance,
      _urls = urls ?? UrlService.instance;

  static final TogetherLobbyService instance = TogetherLobbyService();

  final ApiClient _apiClient;
  final UrlService _urls;

  Map<String, Object?> _decode(http.Response response) {
    try {
      final payload = jsonDecode(response.body);
      return payload is Map ? Map<String, Object?>.from(payload) : const {};
    } catch (_) {
      return const {};
    }
  }

  /// 公开房间列表，按在线人数排序。失败返回空列表（大厅显示空态即可）。
  Future<List<TogetherRoomSummary>> fetchRooms() async {
    try {
      final response = await _apiClient.apiFetch('${_urls.baseUrl}/together/rooms');
      final payload = _decode(response);
      final data = payload['data'];
      if (data is! Map) return const [];
      final rooms = data['rooms'];
      if (rooms is! List) return const [];
      return rooms
          .whereType<Map>()
          .map(
            (item) =>
                TogetherRoomSummary.fromJson(Map<String, Object?>.from(item)),
          )
          .where((room) => room.code.isNotEmpty)
          .toList(growable: false);
    } catch (error) {
      debugPrint('[Together] 拉取大厅失败: $error');
      return const [];
    }
  }

  /// 房间是否存在（凭房间号加入前的校验）。私有房也返回 true。
  Future<bool> roomExists(String code) async {
    if (code.isEmpty) return false;
    try {
      final response = await _apiClient.apiFetch(
        '${_urls.baseUrl}/together/room/${Uri.encodeComponent(code)}',
      );
      final payload = _decode(response);
      return payload['status'] == 200;
    } catch (error) {
      debugPrint('[Together] 查询房间失败: $error');
      return false;
    }
  }
}
