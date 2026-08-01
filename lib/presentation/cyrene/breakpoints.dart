import 'package:flutter/widgets.dart';

import '../../app/debug_probe.dart';

/// 是否启用桌面横屏布局(WinUI3 风格:rail + 标题栏 + 内容区)。
///
/// 按窗口宽度断点:>= 900 走桌面布局,否则移动端布局。Android 平板横屏
/// 也会切到桌面布局。阈值偏保守(窄窗仍移动),可按需调整。
bool isDesktopLayout(BuildContext context) =>
    !probeMobile && MediaQuery.sizeOf(context).width >= 900;
