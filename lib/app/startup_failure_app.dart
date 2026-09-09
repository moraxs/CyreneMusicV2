import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 启动失败 / 启动超时的兜底界面。
///
/// 存在的理由是白屏这类事故本身：`runApp` 没被调用时，iOS 停在纯白的
/// LaunchScreen、macOS 停在白色窗口底色——没有崩溃、没有报错、没有任何可
/// 自查的线索，用户只能反馈「打开就是白的」。所以两条路径都改为渲染本页：
///
/// - `_bootstrap` 抛异常（见 main 的 try/catch）；
/// - 首帧迟迟不出现（见 main 的启动看门狗），此时通常没有任何异常，只有
///   [trace] 能说明卡在哪一步。
///
/// **刻意只用 `flutter/material` 的最基础组件**：Miuix 主题、LiquidGlass、各
/// 偏好 store 本身就可能是失败的那一环，兜底页不能再依赖它们，否则会连兜底
/// 一起崩掉。同理不读任何持久化配置（含深浅色），固定深色。
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({
    super.key,
    required this.error,
    required this.appVersion,
    this.title = 'Cyrene Music 启动失败',
    this.trace,
    this.logFilePath,
  });

  /// 中断启动的异常，或超时时的一句话说明。
  final Object error;

  /// 应用版本号，用户反馈时要报的第一件事。
  final String appVersion;

  /// 标题：区分「启动失败」（抛异常）与「启动超时」（卡住）。
  final String title;

  /// 启动步骤追踪（见 StartupTrace.report）。卡住时这是唯一有效线索——
  /// 它直接指出停在了哪一步。
  final String? trace;

  /// crash.log 的绝对路径；崩溃日志服务自己都没起来时为 null。
  final String? logFilePath;

  /// 汇总成一段可一键复制的文本。用户多半是在群里贴反馈，能整段复制
  /// 比让他们对着屏幕誊写现实得多。
  String get _reportText => [
    'Cyrene Music $appVersion',
    title,
    '',
    '错误: $error',
    if (trace != null) ...['', '启动追踪:', trace!],
    if (logFilePath != null) ...['', '崩溃日志: $logFilePath'],
  ].join('\n');

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
                  Text(
                    title,
                    style: const TextStyle(
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
                  if (trace != null) ...[
                    const SizedBox(height: 12),
                    _Section(title: '启动追踪', body: trace!, monospace: true),
                  ],
                  if (logFilePath != null) ...[
                    const SizedBox(height: 12),
                    _Section(title: '崩溃日志', body: logFilePath!),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    '请把以上内容连同版本号一并反馈；iOS 可在「文件 → 我的 iPhone '
                    '→ Cyrene Music Reborn」里取到 crash.log,附上它可以直接定位问题。',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _CopyButton(text: _reportText),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 一键复制整份诊断信息。
///
/// 剪贴板走 `flutter/services` 的平台通道，而这一屏出现时平台通道未必还
/// 正常，所以失败也只是换个按钮文案，绝不抛出——兜底页自己崩掉就前功尽弃了。
class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});

  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  String _label = '复制全部信息';

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.text));
      if (mounted) setState(() => _label = '已复制');
    } catch (_) {
      if (mounted) setState(() => _label = '复制失败,请手动选中文本');
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: _copy,
    icon: const Icon(Icons.copy_all_outlined, size: 18),
    label: Text(_label),
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: const BorderSide(color: Colors.white24),
    ),
  );
}

/// 一段带标题的可选中文本（用户要能把它复制出来发给我们）。
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.body,
    this.monospace = false,
  });

  final String title;
  final String body;

  /// 启动追踪是对齐过的表格，等宽字体才读得出「哪一列是耗时」。
  final bool monospace;

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
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: Colors.white,
            fontFamily: monospace ? 'monospace' : null,
            fontFamilyFallback: monospace
                ? const ['Menlo', 'Consolas', 'Courier New']
                : null,
          ),
        ),
      ),
    ],
  );
}
