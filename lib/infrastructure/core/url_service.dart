import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 后端来源类型（对应 urlService.ts 的 BackendSourceType）。
enum BackendSourceType {
  official('official'),
  custom('custom');

  const BackendSourceType(this.wireName);

  final String wireName;

  static BackendSourceType fromWireName(String? value) {
    if (value == BackendSourceType.custom.wireName) {
      return BackendSourceType.custom;
    }
    return BackendSourceType.official;
  }
}

/// 统一后端地址与端点管理（对应 Next.js demo/lib/services/urlService.ts）。
///
/// 单例 + [ChangeNotifier]：UI 可通过 [ListenableBuilder] 监听来源切换。
class UrlService extends ChangeNotifier {
  UrlService._();
  static final UrlService instance = UrlService._();

  static const String _keySourceType = 'backend_source_type';
  static const String _keyCustomUrl = 'custom_base_url';
  static const String officialBaseUrl = 'https://music.nekofun.top';

  BackendSourceType _sourceType = BackendSourceType.official;
  String _customBaseUrl = '';
  bool _isInitialized = false;

  /// 从持久化加载配置。应在应用启动（main）时 await 一次。
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _sourceType = BackendSourceType.fromWireName(
        prefs.getString(_keySourceType),
      );
      _customBaseUrl = prefs.getString(_keyCustomUrl) ?? '';
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[UrlService] Failed to load settings: $e');
    }
  }

  BackendSourceType get sourceType => _sourceType;
  String get customBaseUrl => _customBaseUrl;
  bool get isInitialized => _isInitialized;

  /// 当前生效的后端根地址。
  String get baseUrl {
    if (_sourceType == BackendSourceType.official) return officialBaseUrl;
    return _customBaseUrl.isNotEmpty ? _customBaseUrl : officialBaseUrl;
  }

  void setSourceType(BackendSourceType type) {
    if (_sourceType == type) return;
    _sourceType = type;
    _saveSettings();
    notifyListeners();
  }

  void setCustomBaseUrl(String url) {
    final clean = url.trim().replaceFirst(RegExp(r'/+$'), '');
    if (_customBaseUrl == clean) return;
    _customBaseUrl = clean;
    _saveSettings();
    notifyListeners();
  }

  bool isValidUrl(String url) {
    if (url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySourceType, _sourceType.wireName);
      await prefs.setString(_keyCustomUrl, _customBaseUrl);
    } catch (e) {
      debugPrint('[UrlService] Failed to save settings: $e');
    }
  }

  // ==================== API 端点 ====================

  String _path(String path) => '$baseUrl$path';

  // Netease
  String get searchUrl => _path('/search');
  String get searchSuggestUrl => _path('/search/suggest');
  String get searchHotUrl => _path('/search/hot');
  String get songUrl => _path('/song');
  String get toplistsUrl => _path('/toplists');

  // QQ Music
  String get qqSearchUrl => _path('/qq/search');
  String get qqSongUrl => _path('/qq/song');

  // Kugou
  String get kugouSearchUrl => _path('/kugou/search');
  String get kugouSongUrl => _path('/kugou/song');

  // Kuwo
  String get kuwoSearchUrl => _path('/kuwo/search');
  String get kuwoSongUrl => _path('/kuwo/song');

  // Apple Music
  String get appleSearchUrl => _path('/apple/search');

  // Spotify
  String get spotifySearchUrl => _path('/spotify/search');
  String spotifyPlaylistUrl(String playlistId, {int limit = 50}) =>
      _path('/spotify/playlist/$playlistId?limit=$limit');

  // Qishui
  String get qishuiSearchUrl => _path('/qishui/search');

  // Update
  /// 应用更新检查端点：返回最新版本号、更新说明与各平台下载地址。
  ///
  /// 注意与 [latestNextVersionUrl] 的区别：后者只有 version / changelog /
  /// force_update 三个字段，**没有下载链接**，不能用于自动更新。
  String get latestVersionUrl => _path('/version/latest');
  String get latestNextVersionUrl => _path('/version/next/latest');
}
