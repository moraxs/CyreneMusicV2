import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/models/discovery.dart';

/// 桌面 Spotify 榜单本地快照（对应后端 `spotify_charts_fallback.json` 的客户端镜像）。
///
/// 进入榜单页时先读快照即时绘制，再后台请求后端刷新并回写；两层互补：
/// 前端缓存负责「零网络往返的首屏秒开」，后端保底负责「跨后端重启 + 多端共享
/// 的服务端事实来源」。缓存的是页面最终展示的合并后榜单列表（5 个标准榜 +
/// 合并项「华语热门」），复用 [Toplist.toJson]/[fromJson] 完整往返（含
/// `source` 与 `externalId`）。缓存是 best-effort：任何读写异常仅记录、不抛出。
class SpotifyChartsCache {
  SpotifyChartsCache._();
  static final SpotifyChartsCache instance = SpotifyChartsCache._();

  static const _fileName = 'spotify_charts_cache.json';

  Future<File> get _file async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// 读取上次缓存的榜单列表（已合并「华语热门」）。
  /// 文件不存在 / 损坏 / 结构不符返回 null（调用方按无缓存处理）。
  Future<List<Toplist>?> read() async {
    try {
      final file = await _file;
      if (!file.existsSync()) return null;
      final raw = await file.readAsString();
      if (raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final json = Map<String, Object?>.from(decoded);
      final charts = json['charts'];
      if (charts is! List) return null;
      final result = charts
          .whereType<Map>()
          .map((e) => Toplist.fromJson(Map<String, Object?>.from(e)))
          .toList(growable: false);
      return result.isEmpty ? null : result;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// 用最新榜单列表覆盖快照。失败仅 debugPrint，不抛出（缓存是 best-effort）。
  Future<void> write(List<Toplist> charts) async {
    try {
      final file = await _file;
      final payload = jsonEncode({
        'charts': charts.map((t) => t.toJson()).toList(),
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      });
      await file.writeAsString(payload, flush: true);
    } catch (e) {
      debugPrint('[SpotifyChartsCache] write failed: $e');
    }
  }

  /// 清空快照（切换登录态/调试时可用，非必须）。
  Future<void> clear() async {
    try {
      final file = await _file;
      if (file.existsSync()) await file.delete();
    } catch (e) {
      debugPrint('[SpotifyChartsCache] clear failed: $e');
    }
  }
}
