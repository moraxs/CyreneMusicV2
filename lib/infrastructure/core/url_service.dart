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
  String get neteasePlaylistSearchUrl => _path('/search/playlist');

  // QQ Music
  String get qqSearchUrl => _path('/qq/search');
  String get qqSongUrl => _path('/qq/song');

  // Kugou
  String get kugouSearchUrl => _path('/kugou/search');
  String get kugouSongUrl => _path('/kugou/song');
  String get kugouPlaylistSearchUrl => _path('/kugou/search/playlist');

  // Kuwo
  String get kuwoSearchUrl => _path('/kuwo/search');
  String get kuwoSongUrl => _path('/kuwo/song');

  // Apple Music
  String get appleSearchUrl => _path('/apple/search');

  // Spotify
  String get spotifySearchUrl => _path('/spotify/search');
  String spotifyPlaylistUrl(String playlistId, {int limit = 50}) =>
      _path('/spotify/playlist/$playlistId?limit=$limit');
  String spotifyAlbumTracksUrl(String albumId, {int limit = 50, int offset = 0, String country = 'US'}) =>
      _path('/spotify/album/$albumId/tracks?country=$country&limit=$limit&offset=$offset');
  /// 号池 Spotify 账号的个性化首页分区（你的热门合辑 / 推荐电台 / …）。
  /// 只能看见账号收藏过的内容，是 [spotifyHomeUrl] 的降级路径。
  String spotifyPersonalizedUrl({int limit = 20}) =>
      _path('/spotify/personalized?limit=$limit');
  /// 号池 Spotify 账号的官方同款首页（Daily Mix / Your top mixes / daylist / …）。
  /// 走 Spotify 内部 GraphQL 网关，响应形状与 [spotifyPersonalizedUrl] 一致。
  String spotifyHomeUrl({int limit = 20}) =>
      _path('/spotify/home?limit=$limit');
  /// 艺术家详情（头像 / 粉丝数 / 月听众 / 简介 / 热门曲目 / 代表专辑）。
  String spotifyArtistUrl(String artistId) => _path('/spotify/artist/$artistId');
  /// 单曲电台：以某首歌为种子生成的 Spotify 推荐。
  String spotifyRecommendationsUrl(String trackId, {int limit = 30}) =>
      _path('/spotify/recommendations/$trackId?limit=$limit');

  // Update
  /// 应用更新检查端点：返回最新版本号、更新说明与各平台下载地址。
  ///
  /// 注意与 [latestNextVersionUrl] 的区别：后者只有 version / changelog /
  /// force_update 三个字段，**没有下载链接**，不能用于自动更新。
  String get latestVersionUrl => _path('/version/latest');
  String get latestNextVersionUrl => _path('/version/next/latest');
}
