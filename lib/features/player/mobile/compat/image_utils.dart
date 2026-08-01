const Map<String, String> neteaseImageHeaders = {
  'User-Agent': 'NeteaseMusic/9.0.50 (iPhone; iOS 16.3.1; Scale/3.00)'
};

Map<String, String>? getImageHeaders(String? url) {
  if (url != null && (url.contains('126.net') || url.contains('163.com'))) {
    return neteaseImageHeaders;
  }
  return null;
}
