import 'dart:convert';
import 'dart:typed_data';

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

/// 是否为内嵌图片的 `data:image/<mime>;base64,<payload>` URI。
///
/// 本地音轨的封面由 AudioMetadataReader 解析后以 data URI 写入 Track.picUrl，
/// CachedNetworkImage 不认该 scheme，需解码为字节后经 Image.memory 渲染。
bool isDataUriImage(String? url) {
  if (url == null || url.isEmpty) return false;
  return url.startsWith('data:image/');
}

/// 解码 `data:image/<mime>;base64,<payload>` 封面，返回图片字节。
///
/// 非 data URI 或解析失败返回 null（调用方回退到网络图片加载路径）。
Uint8List? decodeDataUriImage(String url) {
  if (!url.startsWith('data:')) return null;
  final comma = url.indexOf(',');
  if (comma <= 0) return null;
  final header = url.substring(0, comma);
  final payload = url.substring(comma + 1);
  if (payload.isEmpty) return null;
  if (!header.toLowerCase().contains(';base64')) return null;
  try {
    return base64Decode(payload);
  } catch (_) {
    return null;
  }
}

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
