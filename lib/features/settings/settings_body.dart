import 'package:flutter/widgets.dart';

/// 设置正文的统一容器，同一份 [children] 支持两种落地方式。
///
/// - **独立成页**（移动端，以及桌面端从二级栈打开的老路径）：自己就是那个
///   可滚动的 `ListView`，沿用 HyperOS 的 12px 页边距与 [topPadding]。
/// - **嵌入长页**（桌面端合并设置页）：退化成一个不滚动的 `Column`，交给外层
///   那一条总滚动去管——见 `desktop/desktop_settings_page.dart` 的锚点 tab。
///
/// 之所以要这么一层：各设置页的正文本来都是 `ListView`，直接塞进外层滚动视图
/// 会得到「滚动里套滚动」。把 padding 与滚动这两件事收在这里，各页正文只需要
/// 关心自己那串 [children]，两种形态的内容才不会分叉。
class SettingsBody extends StatelessWidget {
  const SettingsBody({
    super.key,
    required this.children,
    this.topPadding = EdgeInsets.zero,
    this.embedded = false,
    this.horizontalPadding = 12,
    this.bottomPadding = 40,
  });

  final List<Widget> children;

  /// 沉浸式标题栏让出的高度，由 `CyrenePage.bodyBuilder` 给。嵌入形态下无意义。
  final EdgeInsets topPadding;

  final bool embedded;
  final double horizontalPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    if (embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding:
          topPadding +
          EdgeInsets.fromLTRB(
            horizontalPadding,
            4,
            horizontalPadding,
            bottomPadding,
          ),
      children: children,
    );
  }
}
