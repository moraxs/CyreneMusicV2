import 'package:flutter/material.dart';

/// 启动失败兜底界面。
///
/// `_bootstrap` 里任何一步抛异常，`runApp` 就永远不会被调用，表现是一片白屏：
/// 没有崩溃、没有报错、没有任何可自查的线索。iOS/macOS 上尤其难查——用户拿不
/// 到控制台，只能反馈「打开就是白的」。所以那条路径改为渲染本页，把异常摘要
/// 和崩溃日志路径直接摆在屏幕上。
///
/// **刻意只用 `flutter/material` 的最基础组件**：Miuix 主题、LiquidGlass、各
/// 偏好 store 本身就可能是失败的那一环，兜底页不能再依赖它们，否则会连兜底
/// 一起崩掉。同理不读任何持久化配置（含深浅色），固定深色。
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({
    super.key,
    required this.error,
    required this.appVersion,
    this.logFilePath,
  });

  /// 中断启动的异常。
  final Object error;

  /// 应用版本号，用户反馈时要报的第一件事。
  final String appVersion;

  /// crash.log 的绝对路径；崩溃日志服务自己都没起来时为 null。
  final String? logFilePath;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Color(0xFFFF6B6B),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Cyrene Music 启动失败',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '版本 $appVersion',
                    style: const TextStyle(fontSize: 13, color: Colors.white54),
                  ),
                  const SizedBox(height: 20),
                  _Section(title: '错误', body: error.toString()),
                  if (logFilePath != null) ...[
                    const SizedBox(height: 12),
                    _Section(title: '崩溃日志', body: logFilePath!),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    '请把以上内容连同版本号一并反馈；若能取到崩溃日志文件，'
                    '附上它可以直接定位问题。',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 一段带标题的可选中文本（用户要能把它复制出来发给我们）。
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white54,
        ),
      ),
      const SizedBox(height: 6),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SelectableText(
          body,
          style: const TextStyle(
            fontSize: 12,
            height: 1.5,
            color: Colors.white,
          ),
        ),
      ),
    ],
  );
}
