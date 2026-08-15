import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Android 本地音乐原生导入通道客户端。
///
/// 对应 `android/.../LocalMusicPlugin.kt`。Android 上 `file_picker` 会把所选
/// 文件拷进 app 缓存、选文件夹则返回一条不一定真实存在的路径，均无法被
/// `dart:io` 稳定使用；原生 SAF 通道则把音频复制成**应用私有目录下的真实
/// 文件**，返回真实 `file://` 路径。
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
class ImportedNativeFile {
  const ImportedNativeFile({
    required this.filePath,
    required this.displayName,
    this.sidecarLrcPath,
  });

  final String filePath;
  final String displayName;
  final String? sidecarLrcPath;

  factory ImportedNativeFile.fromMap(Map<Object?, Object?> map) {
    return ImportedNativeFile(
      filePath: map['filePath']?.toString() ?? '',
      displayName: map['displayName']?.toString() ?? '',
      sidecarLrcPath: map['sidecarLrcPath'] as String?,
    );
  }
}
