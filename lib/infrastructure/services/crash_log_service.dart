import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 启动期崩溃日志：把 Dart 层未捕获异常落到文件，供无控制台的 release
/// 构建（如 Windows 发行版）排查「点击没反应 / 启动即崩溃」。
///
/// 设计约束（对应发版要求）：
/// - **仅记录异常**：只有全局异常处理器（FlutterError / PlatformDispatcher /
///   Zone）捕获到的错误才写盘，不记录任何正常运行日志。
/// - **防文件过大**：单份日志超 [maxLogBytes] 后轮转成 `crash.old.log`
///   （最多保留两份），单条 stack 截断到 [maxStackLines] 行。
/// - **启动期可用**：init() 在 main() 最开始调用，即使后续初始化崩了也能写到。
///
/// 另外写一条极短的初始化头（约 40 字节）标记「Dart 层已进入」。它用于区分
/// 两类「点击没反应」：
/// - crash.log 存在 → 已进入 Dart，异常在文件里可定位；
/// - crash.log 不存在 → 进程在 native / DLL 加载阶段就失败，去看 Windows
///   事件查看器（错误模块名会指向缺失的运行库）。
class CrashLogService {
  CrashLogService._();

  static final CrashLogService instance = CrashLogService._();

  /// 单份日志字节上限；超过后在下次写入前轮转为 [backupName]。
  static const int maxLogBytes = 512 * 1024; // 512KB

  /// 单条异常 stack 截断行数。
  static const int maxStackLines = 40;

  static const String logName = 'crash.log';
  static const String backupName = 'crash.old.log';

  File? _file;
  bool _ready = false;

  /// init() 完成前产生的异常先缓冲到内存，避免丢失启动早期的崩溃。
  final List<String> _pending = [];

  /// 串行写入链：避免并发 handler（FlutterError 与 Zone 同时触发）交错写盘。
  Future<void> _writeChain = Future.value();

  String? _lastErrorKey;

  bool get isReady => _ready;

  /// 应用支持目录下当前 crash.log 的绝对路径（null 表示 init 失败）。
  String? get logFilePath => _file?.path;

  /// 初始化日志文件并轮转超限旧文件。必须在 main() 最早期调用一次。
  Future<void> init({String appVersion = ''}) async {
    if (_ready) return;
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      _file = File(p.join(dir.path, logName));
      _rotateIfNeeded();
      _ready = true;
      // 初始化头：唯一一条非异常记录（区分 native 崩溃 vs Dart 层崩溃）。
      final platform = Platform.operatingSystem;
      _enqueue(
        '== crash log init '
        'v${appVersion.isNotEmpty ? appVersion : '(unknown)'} '
        '($platform) ==\n',
      );
      // 补写 init 前缓冲的异常。
      for (final entry in _pending) {
        _enqueue(entry);
      }
      _pending.clear();
    } catch (e) {
      // init 失败不阻塞启动：退化到内存缓冲（异常仍会经 addLog 记录到
      // 开发者日志页，只是不落盘）。
      debugPrint('[CrashLog] init 失败: $e');
    }
  }

  /// 记录一条异常。仅异步写盘，绝不抛出、绝不同步阻塞调用方。
  void logException(
    Object error,
    StackTrace? stack, {
    String context = 'unknown',
  }) {
    // 去重：同一错误连续触发（如 build 反复失败）只记第一条，防刷屏。
    final key = '$context:$error';
    if (key == _lastErrorKey) return;
    _lastErrorKey = key;

    final sb = StringBuffer()
      ..writeln('---- ${DateTime.now().toIso8601String()} [$context] ----')
      ..writeln('$error');
    if (stack != null) {
      final lines = stack.toString().split('\n');
      sb.writeln(lines.take(maxStackLines).join('\n'));
    }
    sb.writeln();

    final entry = sb.toString();
    if (_ready) {
      _enqueue(entry);
    } else {
      _pending.add(entry);
    }
  }

  /// 追加一段文本到日志文件（串行、追加写、写完即轮转检查）。
  void _enqueue(String text) {
    final file = _file;
    if (file == null) {
      _pending.add(text);
      return;
    }
    _writeChain = _writeChain.then((_) async {
      try {
        await file.writeAsString(text, mode: FileMode.append, flush: true);
        if (file.existsSync() && file.lengthSync() > maxLogBytes) {
          _rotateIfNeeded();
        }
      } catch (_) {
        // 写盘失败静默：不影响主流程。
      }
    });
  }

  /// 超限时把当前 crash.log 改名 crash.old.log（覆盖旧备份），后续写入新文件。
  void _rotateIfNeeded() {
    try {
      final file = _file;
      if (file == null || !file.existsSync()) return;
      if (file.lengthSync() <= maxLogBytes) return;
      final backup = File(p.join(p.dirname(file.path), backupName));
      if (backup.existsSync()) backup.deleteSync();
      file.renameSync(backup.path);
    } catch (_) {
      // 轮转失败忽略：下次写入再试。
    }
  }
}
