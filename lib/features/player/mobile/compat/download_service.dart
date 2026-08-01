import 'package:flutter/foundation.dart';

import '../../../../domain/models/track.dart';
import 'song_detail.dart';
import 'toast_utils.dart';

typedef DownloadProgressCallback = void Function(double progress);

class DownloadTask {
  DownloadTask({required this.track});

  final Track track;
  double progress = 0;
  bool isCompleted = false;
  bool isFailed = false;
}

/// 原版 `DownloadService` 的占位兼容层：新应用尚未移植下载功能，
/// 保持按钮样式与 API 不变，触发时提示暂不支持。
class DownloadService extends ChangeNotifier {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  Map<String, DownloadTask> get downloadTasks => const {};

  Future<bool> isDownloaded(Track track, [String? level]) async => false;

  Future<bool> downloadSong(
    Track track,
    SongDetail songDetail, {
    DownloadProgressCallback? onProgress,
  }) async {
    ToastUtils.info('下载功能暂未在新版中开放');
    return false;
  }
}
