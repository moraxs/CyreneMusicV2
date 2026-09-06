import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/stores/together_settings_store.dart';
import '../../application/together/together_controller.dart';
import '../../domain/together/together_models.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
import 'together_member_avatar.dart';

/// 播放器上的一起听图层：房间胶囊 + 弹幕 + 发言入口。
///
/// 做成一层浮在播放器 Stack 最上面的覆盖物，而不是去改各个播放器布局——
/// 经典/流体云/AMLL 三套布局各有各的结构，改一遍要动三处，还容易和歌词抢位置。
/// 未参与一起听时整层是 [SizedBox.shrink]，零成本。
class TogetherPlayerOverlay extends StatefulWidget {
  const TogetherPlayerOverlay({
    super.key,
    this.topOffset = 8,
    this.bottomOffset = 96,
    this.rightOffset = 16,
    this.excludeSemantics = false,
  });

  /// 桌面端置 true：本层对全局语义树零贡献。
  ///
  /// Windows 版 Flutter 的无障碍桥有已知缺陷（flutter#182444），往桌面播放器
  /// 这类子树里加语义节点会让它更新 AXTree 失败并原生闪退——桌面迷你播放器
  /// 和桌面首页都为此做过同样的规避。本层是浮在播放器上的装饰性图层，
  /// 房间信息与发言在设置页、大厅里都有常规入口，这里舍掉语义是划算的。
  final bool excludeSemantics;

  /// 房间胶囊距顶部的距离（再加上安全区）。桌面端要让开悬浮标题栏。
  final double topOffset;

  /// 发言按钮距底部的距离（再加上安全区）。要让开各家播放器的控制栏。
  final double bottomOffset;

  /// 发言按钮距右侧的距离。
  final double rightOffset;

  @override
  State<TogetherPlayerOverlay> createState() => _TogetherPlayerOverlayState();
}

class _TogetherPlayerOverlayState extends State<TogetherPlayerOverlay> {
  final _controller = TogetherController.instance;
  final _settings = TogetherSettingsStore.instance;

  /// 已经放过飞行动画的弹幕 id，避免重建时又飞一遍。
  final Set<String> _spawned = {};
  final List<_DanmakuFlight> _flights = [];
  int _laneCursor = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _settings.addListener(_onChanged);
    // 进页面时已有的历史消息不补飞，只飞后续新来的。
    _spawned.addAll(_controller.chat.map((message) => message.id));
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _settings.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    _collectNewDanmaku();
    setState(() {});
  }

  void _collectNewDanmaku() {
    if (!_settings.danmakuVisible) return;
    for (final message in _controller.chat) {
      if (message.isSystem || !_spawned.add(message.id)) continue;
      _flights.add(
        _DanmakuFlight(message: message, lane: _laneCursor++ % _laneCount),
      );
    }
    // 只留最近这些，防止长时间挂机后列表无限增长。
    if (_flights.length > 40) {
      _flights.removeRange(0, _flights.length - 40);
    }
  }

  static const _laneCount = 4;

  @override
  Widget build(BuildContext context) {
    // 没在一起听时也必须返回 Positioned，不能给 SizedBox.shrink()。
    //
    // 非定位子节点会参与 Stack 定尺：默认 loose 的 Stack 按最大的非定位子节点
    // 决定自身大小，一个 0×0 的空盒子会把整个 Stack 压塌成 0×0。经典桌面
    // 播放器就是这么整窗消失的——路由推上去、不报任何错，但渲染尺寸是 0，
    // 只剩一层透明的模态路由吞掉所有输入，看着就是「点了没反应、窗口卡死」。
    // 定位子节点不参与定尺，所以这里给一个零面积的 Positioned。
    if (!_controller.isActive) {
      return const Positioned(
        left: 0,
        top: 0,
        width: 0,
        height: 0,
        child: SizedBox.shrink(),
      );
    }
    final media = MediaQuery.of(context);
    // ExcludeSemantics 必须包在 Positioned 里面：Positioned 是 ParentDataWidget，
    // 得直接落到外层 Stack 上，中间夹一个 RenderObjectWidget 会直接断言失败。
    return Positioned.fill(
      child: _maybeExcludeSemantics(
        Stack(
        children: [
          // 弹幕层：不吃点击，别挡住播放器上的按钮。跟在房间胶囊下面 70px，
          // 免得两者叠在一起。
          if (_settings.danmakuVisible)
            Positioned(
              top: media.padding.top + widget.topOffset + 70,
              left: 0,
              right: 0,
              height: _laneCount * 34.0,
              child: IgnorePointer(
                child: Stack(
                  children: [
                    for (final flight in _flights)
                      _DanmakuBullet(
                        key: ValueKey(flight.message.id),
                        flight: flight,
                        laneHeight: 34,
                        onFinished: () => _flights.remove(flight),
                      ),
                  ],
                ),
              ),
            ),
          // 房间胶囊：房号 + 在线人数，点开是成员与消息面板。
          Positioned(
            top: media.padding.top + widget.topOffset,
            left: 0,
            right: 0,
            child: Center(child: _RoomPill(controller: _controller)),
          ),
          // 发言入口：只在这儿放一个小按钮，点开才升起输入条，
          // 免得常驻一条输入栏和播放控制抢底部空间。
          Positioned(
            right: widget.rightOffset,
            bottom: media.padding.bottom + widget.bottomOffset,
            child: _ChatLauncher(onTap: () => _openComposer(context)),
          ),
        ],
        ),
      ),
    );
  }

  Widget _maybeExcludeSemantics(Widget child) =>
      widget.excludeSemantics ? ExcludeSemantics(child: child) : child;

  Future<void> _openComposer(BuildContext context) async {
    final text = await showCyreneSheet<String>(
      context: context,
      title: '发送弹幕',
      builder: (sheetContext, dismiss) => _ChatComposer(
        controller: _controller,
        onSubmit: (value) => dismiss(value),
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    _controller.sendChat(text);
  }
}

class _DanmakuFlight {
  _DanmakuFlight({required this.message, required this.lane});

  final TogetherChatMessage message;
  final int lane;
}

/// 一条从右往左飞的弹幕。
class _DanmakuBullet extends StatefulWidget {
  const _DanmakuBullet({
    super.key,
    required this.flight,
    required this.laneHeight,
    required this.onFinished,
  });

  final _DanmakuFlight flight;
  final double laneHeight;
  final VoidCallback onFinished;

  @override
  State<_DanmakuBullet> createState() => _DanmakuBulletState();
}

class _DanmakuBulletState extends State<_DanmakuBullet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    // 长弹幕飞慢一点，保证可读时间大致相当。
    duration: Duration(
      milliseconds: 7000 + widget.flight.message.text.length * 90,
    ),
    vsync: this,
  )..forward();

  @override
  void initState() {
    super.initState();
    _animation.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.flight.message;
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final width = MediaQuery.of(context).size.width;
        // 从屏幕右侧外飞到左侧外，估一个文本宽度做出屏余量。
        final travel = width + message.text.length * 16 + 120;
        return Positioned(
          top: widget.flight.lane * widget.laneHeight,
          left: width - travel * _animation.value,
          child: Opacity(opacity: _animation.isAnimating ? 1 : 0, child: child),
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${message.name}：',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextSpan(
                  text: message.text,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
            maxLines: 1,
          ),
        ),
      ),
    );
  }
}

/// 顶部房间胶囊。
class _RoomPill extends StatelessWidget {
  const _RoomPill({required this.controller});

  final TogetherController controller;

  @override
  Widget build(BuildContext context) {
    final connecting = controller.connection == TogetherConnection.connecting;
    final closed = controller.connection == TogetherConnection.closed;
    return GestureDetector(
      onTap: () => showTogetherRoomSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              closed
                  ? Icons.cloud_off_rounded
                  : controller.isHost
                  ? Icons.podcasts_rounded
                  : Icons.headphones_rounded,
              size: 15,
              color: closed ? Colors.orangeAccent : Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              connecting
                  ? '连接中…'
                  : closed
                  ? '重连中…'
                  : '房间 ${controller.roomCode ?? '------'}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(width: 8),
            Container(width: 1, height: 12, color: Colors.white24),
            const SizedBox(width: 8),
            const Icon(Icons.person_rounded, size: 14, color: Colors.white70),
            const SizedBox(width: 2),
            Text(
              '${controller.listeners}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatLauncher extends StatelessWidget {
  const _ChatLauncher({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.34),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: const Icon(
        Icons.chat_bubble_outline_rounded,
        size: 20,
        color: Colors.white,
      ),
    ),
  );
}

/// 发言面板：上面是最近消息，下面是输入框。
class _ChatComposer extends StatefulWidget {
  const _ChatComposer({required this.controller, required this.onSubmit});

  final TogetherController controller;
  final ValueChanged<String> onSubmit;

  @override
  State<_ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<_ChatComposer> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final messages = widget.controller.chat.reversed
            .take(20)
            .toList(growable: false);
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: messages.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: MiuixText(
                            '还没有人说话，来打个招呼吧',
                            fontSize: 13,
                            color: colors.onSurfaceVariantSummary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        reverse: true,
                        shrinkWrap: true,
                        itemCount: messages.length,
                        itemBuilder: (context, index) =>
                            _ChatLine(message: messages[index]),
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: MiuixTextField(
                      controller: _input,
                      label: '说点什么…',
                      useLabelAsPlaceholder: true,
                      singleLine: true,
                      autofocus: true,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  MiuixButton(
                    onPressed: _submit,
                    colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                    child: MiuixText('发送', style: theme.textStyles.button),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _submit() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit(text);
  }
}

class _ChatLine extends StatelessWidget {
  const _ChatLine({required this.message});

  final TogetherChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Center(
          child: MiuixText(
            message.text,
            fontSize: 12,
            color: colors.onSurfaceVariantSummary,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${message.name}：',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.primary,
              ),
            ),
            TextSpan(
              text: message.text,
              style: TextStyle(fontSize: 14, color: colors.onSurfaceContainer),
            ),
          ],
        ),
      ),
    );
  }
}

/// 房间面板：成员列表 + 房间号 + 退出。
Future<void> showTogetherRoomSheet(BuildContext context) async {
  final controller = TogetherController.instance;
  await showCyreneSheet<void>(
    context: context,
    title: '一起听',
    builder: (sheetContext, dismiss) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = MiuixTheme.of(context);
        final colors = theme.colors;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MiuixText(
                          '房间号',
                          fontSize: 12,
                          color: colors.onSurfaceVariantSummary,
                        ),
                        const SizedBox(height: 4),
                        MiuixText(
                          controller.roomCode ?? '------',
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: colors.onBackground,
                        ),
                      ],
                    ),
                  ),
                  MiuixTextButton(
                    '复制',
                    onPressed: () {
                      final code = controller.roomCode;
                      if (code == null) return;
                      Clipboard.setData(ClipboardData(text: code));
                      CyreneToast.show('房间号已复制：$code');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            MiuixText(
              controller.isHost
                  ? (controller.roomPrivate
                        ? '私有房间：只有拿到房间号的人能进'
                        : '公开房间：任何人都能在大厅里找到你')
                  : '正在跟随房主播放',
              fontSize: 12,
              color: colors.onSurfaceVariantSummary,
            ),
            const SizedBox(height: 14),
            MiuixText(
              '房间成员 ${controller.listeners}',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.onBackground,
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final member in controller.members)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          TogetherMemberAvatar(member: member, size: 30),
                          const SizedBox(width: 10),
                          Expanded(
                            child: MiuixText(
                              member.name,
                              fontSize: 14,
                              color: colors.onBackground,
                            ),
                          ),
                          if (member.isHost)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: MiuixText(
                                '房主',
                                fontSize: 11,
                                color: colors.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            MiuixButton(
              onPressed: () {
                dismiss();
                controller.leave();
                CyreneToast.show(
                  controller.isHost ? '已结束一起听' : '已退出房间',
                );
              },
              colors: MiuixButtonColors(
                color: colors.error.withValues(alpha: 0.12),
                disabledColor: colors.disabledPrimaryButton,
                contentColor: colors.error,
                disabledContentColor: colors.disabledOnPrimaryButton,
              ),
              child: MiuixText(
                controller.isHost ? '结束一起听' : '退出房间',
                style: theme.textStyles.button,
              ),
            ),
            const SizedBox(height: 10),
          ],
        );
      },
    ),
  );
}
