import '../../../../infrastructure/core/url_service.dart' as app;

/// 原版 `UrlService()` 单例的兼容垫片：转发到新架构的 UrlService.instance。
class UrlService {
  static final UrlService _instance = UrlService._internal();
  factory UrlService() => _instance;
  UrlService._internal();

  String get baseUrl => app.UrlService.instance.baseUrl;
}
