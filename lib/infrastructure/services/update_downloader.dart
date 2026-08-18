import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/url_service.dart';

/// 更新包下载失败。[message] 面向用户，可直接展示。
class UpdateDownloadFailure implements Exception {
  const UpdateDownloadFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 更新包的流式下载。
///
/// 不走 [ApiClient]：那边只返回完整的 [http.Response]，拿不到分块，无法上报进度；
/// 且更新包可能托管在与 API 不同的源上（后端的 update_strategy 可切到 R2 或
/// 海外代理），不需要鉴权感知。
class UpdateDownloader {
  /// [client] 供测试注入；生产环境每次下载用一个新的 [http.Client]，
  /// 用完即弃，不与 API 请求共用连接池。
  UpdateDownloader({http.Client? client}) : this._(client);

  UpdateDownloader._(this._client);

  final http.Client? _client;

  /// 整体下载超时。大包（APK 约 70MB）在弱网下也该有个尽头，否则进度条会
  /// 永远停在某个百分比而没有任何反馈。
  static const Duration _timeout = Duration(minutes: 10);

  /// 进度回调的节流间隔与步长。旧版每收到一个 chunk 就通知一次，几万次回调
  /// 打在 UI 上纯属浪费。
  static const Duration _progressInterval = Duration(milliseconds: 200);
  static const double _progressStep = 0.01;

  /// 下载 [url] 到本地并返回文件；[onProgress] 收 0.0~1.0。
  ///
  /// 响应未给 Content-Length 时无法计算百分比，此时不回调进度，由 UI 显示
  /// 不确定态。
  Future<File> download(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final resolved = normalizeUrl(url);
    final uri = Uri.parse(resolved);
    final fileName = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : 'update.bin';

    final directory = await resolveDownloadDirectory();
    final file = File(p.join(directory.path, fileName));
    // 上次下到一半的残留会让「续传」变成损坏文件，直接重下。
    if (file.existsSync()) await file.delete();

    debugPrint('[UpdateDownloader] 开始下载 $resolved → ${file.path}');

    // 生产环境每次下载新建一个 client、用完即关，不与 API 请求共用连接池；
    // 测试注入的 _client 由测试方负责关闭。
    final ownsClient = _client == null;
    final http.Client client = _client ?? http.Client();
    try {
      final response = await client
          .send(http.Request('GET', uri))
          .timeout(_timeout);
      if (response.statusCode != 200) {
        throw UpdateDownloadFailure('下载失败（HTTP ${response.statusCode}）');
      }

      final contentLength = response.contentLength ?? 0;
      var received = 0;
      var lastReported = 0.0;
      var lastReportedAt = DateTime.now();

      final sink = file.openWrite();
      try {
        await for (final chunk in response.stream.timeout(_timeout)) {
          received += chunk.length;
          sink.add(chunk);

          if (contentLength <= 0 || onProgress == null) continue;
          final progress = (received / contentLength).clamp(0.0, 1.0);
          final now = DateTime.now();
          final enoughProgress = progress - lastReported >= _progressStep;
          final enoughTime =
              now.difference(lastReportedAt) >= _progressInterval;
          if (enoughProgress || enoughTime || progress >= 1) {
            lastReported = progress;
            lastReportedAt = now;
            onProgress(progress);
          }
        }
        await sink.flush();
      } catch (e) {
        await sink.close();
        if (file.existsSync()) file.delete().ignore();
        if (e is TimeoutException) {
          throw const UpdateDownloadFailure('下载超时，请重试');
        }
        rethrow;
      }
      await sink.close();

      // 后端不下发 sha256/size，长度是唯一能校验的东西：截断的安装包装上去
      // 只会得到一个更难排查的「解析失败」。
      if (contentLength > 0 && received != contentLength) {
        if (file.existsSync()) file.delete().ignore();
        throw const UpdateDownloadFailure('下载不完整，请重试');
      }

      debugPrint('[UpdateDownloader] 下载完成: $received 字节');
      return file;
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// 更新包的落地目录（用户可写）。
  ///
  /// 桌面端同样放在应用数据目录而非安装目录：更新包、解压暂存都不再写入安装
  /// 目录（Program Files 下非管理员运行会直接写失败，旧实现因此必须"以管理员
  /// 运行主程序"才能更新）。安装目录的最终覆盖交给提权后的更新器完成
  /// （见 WindowsUpdateInstaller）。
  Future<Directory> resolveDownloadDirectory() async {
    final support = await getApplicationSupportDirectory();
    final base = Directory(p.join(support.path, 'updates'));
    if (!base.existsSync()) base.createSync(recursive: true);
    return base;
  }

  /// 应用安装目录（桌面端）。
  ///
  /// `flutter run` 时 resolvedExecutable 指向 flutter/dart 工具而非应用本体，
  /// 此时退回当前工作目录——debug 下更新流程本就跑不通，至少别去写 SDK 目录。
  static String resolveInstallDirectory() {
    try {
      final executable = File(Platform.resolvedExecutable);
      final name = p.basename(executable.path).toLowerCase();
      if (name.contains('flutter') || name.contains('dart')) {
        return Directory.current.path;
      }
      return executable.parent.path;
    } catch (_) {
      return Directory.current.path;
    }
  }

  /// 归一化下载地址。
  ///
  /// 后端返回的绝对地址带的是**它自己**推导出的 origin（或 R2 / 代理地址）。
  /// 用户切到自定义后端时，那个 origin 往往不可达，因此 host 与当前 baseUrl
  /// 不符时改用 baseUrl；相对路径同样拼到 baseUrl 上。
  @visibleForTesting
  static String normalizeUrl(String rawUrl) {
    final base = UrlService.instance.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    try {
      final uri = Uri.parse(rawUrl);
      if (!uri.hasScheme) {
        return '$base${rawUrl.startsWith('/') ? '' : '/'}$rawUrl';
      }
      final baseUri = Uri.parse(base);
      final sameOrigin =
          uri.host == baseUri.host &&
          uri.port == baseUri.port &&
          uri.scheme == baseUri.scheme;
      if (sameOrigin) return rawUrl;
      // 官方源下后端给的就是官方地址（或有意指向的 R2 / 代理），原样放行；
      // 只有用户切了自定义后端才需要改写。
      if (UrlService.instance.sourceType == BackendSourceType.official) {
        return rawUrl;
      }
      return '$base${uri.path.startsWith('/') ? '' : '/'}${uri.path}';
    } catch (_) {
      return '$base${rawUrl.startsWith('/') ? '' : '/'}$rawUrl';
    }
  }
}
