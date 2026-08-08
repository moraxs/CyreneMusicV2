// 临时诊断开关：定位桌面端启动即闪退（原生崩溃在 flutter_windows.dll 的
// 无障碍桥 accessibility_bridge.cc，伴随 "Failed to update ui::AXTree"）。
//
// 全部由环境变量驱动、默认关闭，因此一次编译即可多次运行逐个排除嫌疑点。
// 定位结束后整个文件连同各处引用一并删除。
import 'dart:io' show Platform;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

bool _on(String key) => Platform.environment[key] == '1';

/// 整树包 ExcludeSemantics：验证崩溃是否确实由语义树引起。
final bool probeNoSemantics = _on('CY_NO_SEM');

/// 去掉 MaterialApp.builder 里的全局 toast 层（Stack 的第二个孩子）。
final bool probeNoToast = _on('CY_NO_TOAST');

/// 跳过 window_manager 的 VirtualWindowFrameInit（顶部三边缩放层）。
final bool probeNoFrame = _on('CY_NO_FRAME');

/// 跳过 LiquidGlass 初始化与根 wrap。
final bool probeNoGlass = _on('CY_NO_GLASS');

/// 桌面侧栏收起态与迷你播放器上的 fluent Tooltip 全部改为直接返回 child。
final bool probeNoTooltip = _on('CY_NO_TOOLTIP');

/// 桌面内容区 IndexedStack 改为只挂当前选中页（不保活）。
final bool probeNoIndexedStack = _on('CY_NO_ISTACK');

/// 不挂底部桌面迷你播放器。
final bool probeNoMiniPlayer = _on('CY_NO_MINI');

/// 迷你播放器内部细分开关（定位畸形语义树的具体控件）。
final bool probeNoProgressBar = _on('CY_NO_PROGRESS'); // 顶部 3px ProgressBar
final bool probeNoSlider = _on('CY_NO_SLIDER'); // 音量 Slider
final bool probeNoTimeText = _on('CY_NO_TIME'); // 高频时间文字
final bool probeNoLeftSection = _on('CY_NO_LEFT'); // 封面 + 曲名区
final bool probeNoCenter = _on('CY_NO_CENTER'); // 中段传输控件
final bool probeNoRight = _on('CY_NO_RIGHT'); // 右段整体

/// 强制窄窗启动（< 900），走移动端布局，用于判断是否桌面外壳独有。
final bool probeMobile = _on('CY_MOBILE');

/// 每帧后打印语义树的节点 id（BFS）并标出重复 id。
final bool probeDumpSemantics = _on('CY_DUMP_SEM');

/// 按 [probeNoTooltip] 决定是否真的包一层提示。
Widget probeTooltip({required Widget child, required Widget Function() build}) =>
    probeNoTooltip ? child : build();

/// 安装诊断钩子：打印语义开关状态，并在需要时逐帧转储语义树。
void installProbe() {
  final flags = <String>[
    if (probeNoSemantics) 'NO_SEM',
    if (probeNoToast) 'NO_TOAST',
    if (probeNoFrame) 'NO_FRAME',
    if (probeNoGlass) 'NO_GLASS',
    if (probeNoTooltip) 'NO_TOOLTIP',
    if (probeNoIndexedStack) 'NO_ISTACK',
    if (probeNoMiniPlayer) 'NO_MINI',
    if (probeMobile) 'MOBILE',
    if (probeDumpSemantics) 'DUMP_SEM',
  ];
  debugPrint('[PROBE] flags=${flags.isEmpty ? "(none)" : flags.join(",")}');

  final binding = WidgetsBinding.instance;
  void report() => debugPrint(
    '[PROBE] semanticsEnabled=${binding.semanticsEnabled}',
  );
  report();
  binding.platformDispatcher.onSemanticsEnabledChanged = report;

  var frame = 0;
  void afterFrame(Duration _) {
    frame++;
    if (probeDumpSemantics) _dumpSemantics(frame);
    // debugPrint('[PROBE] frame#$frame done');
    binding.addPostFrameCallback(afterFrame);
  }

  binding.addPostFrameCallback(afterFrame);
}

/// BFS 转储语义树：打印节点数、最大 id 与重复出现的 id（重复即树形已损坏）。
///
/// 多视图重构后 semanticsOwner 挂在各视图自己的 PipelineOwner 上，
/// rootPipelineOwner 本身不持有，故要下钻一层找第一个有 owner 的子节点。
void _dumpSemantics(int frame) {
  SemanticsOwner? owner;
  void find(PipelineOwner node) {
    owner ??= node.semanticsOwner;
    node.visitChildren(find);
  }

  find(RendererBinding.instance.rootPipelineOwner);
  final root = owner?.rootSemanticsNode;
  if (root == null) {
    debugPrint('[PROBE] frame#$frame semantics=<null>');
    return;
  }
  final seen = <int>[];
  final dup = <int>[];
  final queue = <SemanticsNode>[root];
  while (queue.isNotEmpty) {
    final node = queue.removeAt(0);
    if (seen.contains(node.id)) {
      dup.add(node.id);
      continue;
    }
    seen.add(node.id);
    node.visitChildren((child) {
      queue.add(child);
      return true;
    });
  }
  seen.sort();
  debugPrint(
    '[PROBE] frame#$frame semantics nodes=${seen.length} '
    'maxId=${seen.isEmpty ? -1 : seen.last} '
    'dup=${dup.isEmpty ? "none" : dup.toString()}',
  );
}
