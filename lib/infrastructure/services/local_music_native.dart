import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Android 本地音乐原生导入通道客户端。
///
/// 对应 `android/.../LocalMusicPlugin.kt`。Android 上 `file_picker` 会把所选
/// 文件拷进 app 缓存、选文件夹则返回一条不一定真实存在的路径，均无法被
/// `dart:io` 稳定使用；原生 SAF 通道则**直接持久化 `content://` URI 权限**，
/// 把原始 URI 返回给 Flutter 端：
/// - 播放：media_kit 内部的 `AndroidContentUriProvider` 会把 `content://`
///   转为 `fd://` 供 libmpv 读取，无需复制。
/// - 元数据：通过 [readUriBytes] 用 ContentResolver 读出字节后交 Dart 解析。
///
/// 这样避免了把整库音频复制进应用私有目录导致的双倍存储占用。
class LocalMusicNative {
  LocalMusicNative._();

  static final LocalMusicNative instance = LocalMusicNative._();

  static const MethodChannel _channel = MethodChannel(
    'com.cyrene.music/local_music',
  );

  /// 是否应走原生导入（仅 Android 有效）。
  bool get isSupported => Platform.isAndroid;

  /// 弹系统文档选择器多选音频文件；用户取消返回 null。
  Future<List<ImportedNativeFile>?> pickFiles() async {
    final result = await _channel.invokeMethod<List<Object?>>('pickFiles');
    return _parseResult(result);
  }

  /// 弹系统目录选择器，递归扫描目录内所有音频；用户取消返回 null。
  Future<List<ImportedNativeFile>?> pickFolder() async {
    final result = await _channel.invokeMethod<List<Object?>>('pickFolder');
    return _parseResult(result);
  }

  /// 读取 `content://` URI 的全部字节（供 [AudioMetadataReader] 解析元数据）。
  ///
  /// 仅 Android 有效；调用方应确保 [uri] 来自原生导入通道返回的 `content://`
  /// URI 且已持有持久化读权限。失败返回 null。
  Future<Uint8List?> readUriBytes(String uri) async {
    final result = await _channel.invokeMethod<Uint8List>(
      'readUriBytes',
      <String, Object?>{'uri': uri},
    );
    return result;
  }

  List<ImportedNativeFile>? _parseResult(List<Object?>? result) {
    if (result == null) return null;
    return result
        .whereType<Map>()
        .map((e) => ImportedNativeFile.fromMap(Map<Object?, Object?>.from(e)))
        .where((e) => e.filePath.isNotEmpty)
        .toList(growable: false);
  }
}

/// 单个原生导入结果（对应 LocalMusicPlugin.kt 返回的 map）。
///
/// [filePath] 实际承载的是 SAF `content://` URI 字符串（沿用旧字段名以保持
/// 与持久化 JSON 的兼容）；[sidecarLrc] 为同名 .lrc 的已解码文本内容，无则
/// null。
class ImportedNativeFile {
  const ImportedNativeFile({
    required this.filePath,
    required this.displayName,
    this.sidecarLrc,
  });

  final String filePath;
  final String displayName;
  final String? sidecarLrc;

  factory ImportedNativeFile.fromMap(Map<Object?, Object?> map) {
    return ImportedNativeFile(
      filePath: map['filePath']?.toString() ?? '',
      displayName: map['displayName']?.toString() ?? '',
      sidecarLrc: map['sidecarLrc'] as String?,
    );
  }
}
