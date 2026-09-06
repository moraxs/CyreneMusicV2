import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import '../mobile/compat/image_utils.dart';

/// 把封面地址转成 [ImageProvider]，三态兼容：内嵌 data URI / 网络 / 本地文件。
///
/// 网络分支必须走 [CachedNetworkImageProvider] 并带上网易 UA——见项目约定
/// 「封面一律用原始 URL + CachedNetworkImage + 网易 UA」，强转 https 会 403。
ImageProvider? monetCoverProvider(String? url) {
  if (url == null || url.isEmpty) return null;

  if (isDataUriImage(url)) {
    final bytes = decodeDataUriImage(url);
    return bytes == null ? null : MemoryImage(bytes);
  }

  if (url.startsWith('http://') || url.startsWith('https://')) {
    return CachedNetworkImageProvider(url, headers: getImageHeaders(url));
  }

  return FileImage(File(url));
}
