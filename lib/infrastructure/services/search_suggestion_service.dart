import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/url_service.dart';

/// 搜索建议 / 热搜榜 / 搜索历史（对应 Next.js SearchBox.tsx 的数据层）。
///
/// - 建议：POST `/search/suggest`（表单编码 `keywords` + `type=mobile`），
///   取 `result.allMatch[].keyword`；
/// - 热搜：GET `/search/hot`，取 `result.hots[].first`；
/// - 历史：本地持久化，键名与 Web 端 localStorage 一致
///   （`cyrene_search_history`），上限 10 条、去重置顶。
class SearchSuggestionService {
  SearchSuggestionService._();

  static final SearchSuggestionService instance = SearchSuggestionService._();

  static const _historyKey = 'cyrene_search_history';
  static const _maxHistory = 10;

  Future<List<String>> fetchSuggestions(String keywords) async {
    try {
      final response = await ApiClient.instance.apiFetch(
        UrlService.instance.searchSuggestUrl,
        method: 'POST',
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'keywords': keywords, 'type': 'mobile'},
      );
      final data = jsonDecode(response.body);
      if (data is Map && data['status'] == 200) {
        final result = data['result'];
        final matches = result is Map ? result['allMatch'] : null;
        if (matches is List) {
          return matches
              .map(
                (item) =>
                    item is Map ? (item['keyword']?.toString() ?? '') : '',
              )
              .where((keyword) => keyword.isNotEmpty)
              .toList(growable: false);
        }
      }
    } catch (e) {
      debugPrint('[SearchSuggestion] 获取搜索建议失败: $e');
    }
    return const [];
  }

  Future<List<String>> fetchHotSearches() async {
    try {
      final response = await ApiClient.instance.apiFetch(
        UrlService.instance.searchHotUrl,
      );
      final data = jsonDecode(response.body);
      if (data is Map && data['status'] == 200) {
        final result = data['result'];
        final hots = result is Map ? result['hots'] : null;
        if (hots is List) {
          return hots
              .map(
                (item) => item is Map ? (item['first']?.toString() ?? '') : '',
              )
              .where((name) => name.isNotEmpty)
              .toList(growable: false);
        }
      }
    } catch (e) {
      debugPrint('[SearchSuggestion] 获取热搜失败: $e');
    }
    return const [];
  }

  Future<List<String>> loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_historyKey) ?? const [];
    } catch (e) {
      debugPrint('[SearchSuggestion] 读取搜索历史失败: $e');
      return const [];
    }
  }

  /// 记录一次搜索并返回更新后的历史（去重置顶，最多 [_maxHistory] 条）。
  Future<List<String>> saveHistory(String term) async {
    final keyword = term.trim();
    if (keyword.isEmpty) return loadHistory();
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = [
        keyword,
        ...(prefs.getStringList(_historyKey) ?? const []).where(
          (item) => item != keyword,
        ),
      ].take(_maxHistory).toList(growable: false);
      await prefs.setStringList(_historyKey, history);
      return history;
    } catch (e) {
      debugPrint('[SearchSuggestion] 保存搜索历史失败: $e');
      return loadHistory();
    }
  }

  Future<List<String>> removeHistory(String term) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = (prefs.getStringList(_historyKey) ?? const [])
          .where((item) => item != term)
          .toList(growable: false);
      await prefs.setStringList(_historyKey, history);
      return history;
    } catch (e) {
      debugPrint('[SearchSuggestion] 删除搜索历史失败: $e');
      return loadHistory();
    }
  }

  Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyKey);
    } catch (e) {
      debugPrint('[SearchSuggestion] 清空搜索历史失败: $e');
    }
  }
}
