/// 封面等媒体 URL 一律按接口返回值原样使用（与原版 cyrene_music 一致），
/// 不做 http→https 改写：明文 HTTP 由 Android 的 network_security_config 放行。
///
/// 网易云图片 CDN（pX.music.126.net / 163.com）会对非官方客户端的
/// User-Agent 返回 403，需伪装成官方客户端请求头；其他域名不附加任何头。
const Map<String, String> _neteaseImageHeaders = {
  'User-Agent': 'NeteaseMusic/9.0.50 (iPhone; iOS 16.3.1; Scale/3.00)',
};

Map<String, String>? imageHeaders(String url) =>
    url.contains('126.net') || url.contains('163.com')
    ? _neteaseImageHeaders
    : null;

/// 封面解码目标像素宽,供 CachedNetworkImage 的 [memCacheWidth] 使用。
///
/// 网易等 CDN 封面常为 ~1000² 原图,若按原尺寸解码,在 100–220px 的
/// 网格/行里显示会浪费近百倍的内存带宽与 GPU 纹理,滚动时逐帧上传大位图
/// 直接拖垮帧率(即便没在播放音乐)。按「逻辑显示宽 × 设备像素比」解码,
/// 屏幕上呈现的像素完全不变——只是不再解码用不到的分辨率。
///
/// [logicalWidth] 为控件的逻辑宽度(dp),[devicePixelRatio] 取自
/// MediaQuery。上取整到 8 的倍数,避免解码尺寸随布局微抖动频繁变化。
int coverDecodeWidth(double logicalWidth, double devicePixelRatio) {
  final target = (logicalWidth * devicePixelRatio).ceil();
  if (target <= 0) return 8;
  return ((target + 7) ~/ 8) * 8;
}
