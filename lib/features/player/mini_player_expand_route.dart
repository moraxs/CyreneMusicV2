import 'package:flutter/material.dart';

/// 迷你播放器封面 ↔ 全屏播放器大封面的共享元素标签。
///
/// 两端各挂一个同 tag 的 [Hero]：迷你播放器那侧只给**当前可见**的那个子节点
/// 挂（展开态/折叠态两个子树在 AnimatedCrossFade 里是同时存在的，都挂会撞
/// 「multiple heroes share the same tag」断言）。
const String kPlayerCoverHeroTag = 'cyrene.player.cover';

/// 裁剪窗的 key，测试拿它量「当前窗口长到多大了」。
@visibleForTesting
const Key miniPlayerExpandWindowKey = ValueKey('miniPlayerExpandWindow');

/// 整机屏幕圆角的估算值（逻辑像素）。
///
/// Flutter 拿不到显示屏的物理圆角：安卓要走平台通道读
/// `WindowInsets.getRoundedCorner`（API 31+），iOS 那个 `_displayCornerRadius`
/// 是私有 API。为一段过渡动画搭两套原生通道不划算，所以按屏幕短边估——主流
/// 全面屏手机的屏幕圆角差不多就是短边的 1/8 上下：iPhone 15 是 393pt 宽 /
/// 55pt 圆角，Pixel 那类安卓机 360~412dp 宽 / 40~50dp 圆角。
///
/// 估歪了也不会露馅：窗口在动画收尾时会把圆角收平到 0（见
/// [MiniPlayerExpandRoute]），静止态是实打实铺满整屏的，圆角只在飞行途中出现。
double screenCornerRadiusFor(Size screen) =>
    (screen.shortestSide * 0.13).clamp(28.0, 56.0);

/// 读取 [key] 对应控件在全局坐标系里的矩形；控件不在树上或还没布局时返回 null。
Rect? globalRectOfKey(GlobalKey key) {
  final renderObject = key.currentContext?.findRenderObject();
  if (renderObject is! RenderBox) return null;
  if (!renderObject.attached || !renderObject.hasSize) return null;
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

/// 迷你播放器「整块长大成全屏播放器」的路由。
///
/// 三条动线同时跑，合起来才是那种一体的膨胀感：
/// 1. **窗口**：一个圆角裁剪窗从迷你播放器的矩形长到整屏。圆角走
///    `迷你面板 20 → 整机弧度（[screenCornerRadiusFor]）→ 0`：不能简单地
///    20 → 0，那样窗口刚长到一半圆角就只剩个位数，整段动画看着全是直角。用
///    [ClipRSuperellipse] 而不是 ClipRRect——真机屏幕四角和迷你播放器的
///    `LiquidRoundedSuperellipse` 都是连续曲率的超椭圆，圆弧角接不上。
/// 2. **正文**：全屏页始终按整屏尺寸布局、钉在屏幕坐标上（窗口移动时用反向
///    平移抵消），只做以迷你播放器中心为锚点的 0.88 → 1.0 轻微放大 + 淡入。
///    不缩放布局本身，避免整页在动画期间反复 layout。
/// 3. **封面**：交给 [Hero]（tag 为 [kPlayerCoverHeroTag]）自己飞——它跑在
///    Navigator 的 overlay 里，不受上面那个裁剪窗影响，所以封面能「飞出」还没
///    长大的窗口。落点不会被这里的变换带偏：Hero 量的是封面相对**路由内容根**
///    （`ModalRoute.subtreeContext`，见 routes.dart 里挂 `_subtreeKey` 的那个
///    RepaintBoundary）的位置，而那个根就在下面这堆 Positioned/Clip/Transform
///    的里面，量到的自然是页面自己坐标系里的最终位置。
///
/// [originRect] 每帧现取而不是开场存一次：返回时迷你播放器可能已经折叠成小
/// 方块（甚至因为切歌被移走），收起动画得落到它**当下**的位置。
class MiniPlayerExpandRoute<T> extends PageRouteBuilder<T> {
  MiniPlayerExpandRoute({
    required WidgetBuilder builder,
    required this.originRect,
    this.originCornerRadius = 20,
    super.settings,
  }) : super(
         transitionDuration: const Duration(milliseconds: 520),
         reverseTransitionDuration: const Duration(milliseconds: 400),
         pageBuilder: (context, animation, secondaryAnimation) =>
             builder(context),
       );

  /// 迷你播放器面板在全局坐标系里的矩形；取不到时用屏幕底部的兜底矩形。
  final ValueGetter<Rect?> originRect;

  /// 起始圆角，跟迷你播放器的液态玻璃面板保持一致。
  final double originCornerRadius;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _ExpandFromRectTransition(
    animation: animation,
    originRect: originRect,
    originCornerRadius: originCornerRadius,
    child: child,
  );
}

class _ExpandFromRectTransition extends StatefulWidget {
  const _ExpandFromRectTransition({
    required this.animation,
    required this.originRect,
    required this.originCornerRadius,
    required this.child,
  });

  final Animation<double> animation;
  final ValueGetter<Rect?> originRect;
  final double originCornerRadius;
  final Widget child;

  @override
  State<_ExpandFromRectTransition> createState() =>
      _ExpandFromRectTransitionState();
}

class _ExpandFromRectTransitionState extends State<_ExpandFromRectTransition> {
  /// 最后一次读到的起点矩形。迷你播放器可能在全屏页打开期间被移除（切歌清空
  /// 当前曲目），缓存一份收起动画才不至于突然没有落点。
  Rect? _lastOrigin;

  /// HyperOS / Folme 那条灵动曲线，与 [CyreneHeroExpandPageRoute] 保持一致。
  late final CurvedAnimation _expand = CurvedAnimation(
    parent: widget.animation,
    curve: const Cubic(0.2, 0.0, 0.0, 1.0),
    reverseCurve: Curves.easeInCubic,
  );

  /// 正文淡入：进场前 42% 就补满，早点建立实体感；
  /// 出场则一直保持不透明，最后 45% 才淡出，收缩过程里正文始终可见。
  late final CurvedAnimation _contentFade = CurvedAnimation(
    parent: widget.animation,
    curve: const Interval(0.0, 0.42, curve: Curves.easeOut),
    reverseCurve: const Interval(0.0, 0.45, curve: Curves.easeIn),
  );

  @override
  void dispose() {
    _expand.dispose();
    _contentFade.dispose();
    super.dispose();
  }

  /// 窗口在进度 [t] 处的圆角。
  ///
  /// 两段：前 28% 从迷你面板的圆角迅速涨到整机弧度，然后一路保持——飞行途中
  /// 看起来就是「一块手机屏幕在长大」；最后 10% 再收平到 0 贴满整屏。
  ///
  /// 收平这段在墙钟上并不短：[_expand] 用的是尾部重减速的 Folme 曲线，t 从
  /// 0.9 走到 1.0 要花掉整段时长的一半左右（约 250ms），而那时窗口边缘距离屏
  /// 幕边缘已不足一成，看上去是圆角慢慢化开、把画面坐进屏幕里，不是硬切。
  ///
  /// 之所以非收到 0 不可：Flutter 读不到显示屏真实圆角（见
  /// [screenCornerRadiusFor]），静止态若留着估出来的圆角，一旦比物理圆角大，
  /// 四角就会露出底下的外壳；收到 0 则在任何设备（含直角的模拟器、平板）上都
  /// 是规规矩矩铺满整屏。
  double _cornerRadius(double t, Size screen) {
    final ramp = (t / 0.28).clamp(0.0, 1.0);
    final settle = ((t - 0.9) / 0.1).clamp(0.0, 1.0);
    final grown =
        widget.originCornerRadius +
        (screenCornerRadiusFor(screen) - widget.originCornerRadius) * ramp;
    final radius = grown * (1.0 - settle);
    // t=1 时 settle 差着一个浮点尾数收不到整 1，留下个 1e-14 的圆角。半个像素
    // 以下都没有意义，直接归零，静止态才是干干净净的直角矩形。
    return radius < 0.5 ? 0 : radius;
  }

  /// 迷你播放器不在场时的兜底起点：屏幕底部一条与它同宽同高的带子。
  Rect _fallbackOrigin(Size screen) => Rect.fromLTWH(
    16,
    (screen.height - 172).clamp(0.0, screen.height),
    (screen.width - 32).clamp(0.0, screen.width),
    68,
  );

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final full = Offset.zero & screen;

    return AnimatedBuilder(
      animation: _expand,
      child: widget.child,
      builder: (context, child) {
        // 每帧现取（见类文档）。这里只写缓存不触发重建，不会影响布局。
        final live = widget.originRect();
        if (live != null) _lastOrigin = live;
        final origin = live ?? _lastOrigin ?? _fallbackOrigin(screen);

        final t = _expand.value;
        final rect = Rect.lerp(origin, full, t)!;
        final radius = _cornerRadius(t, screen);
        final scale = 0.88 + 0.12 * t;
        // 以迷你播放器中心为放大锚点：靠近它的内容几乎不动，远处铺得更开。
        final anchor = Alignment(
          screen.width == 0 ? 0 : (origin.center.dx / screen.width) * 2 - 1,
          screen.height == 0 ? 0 : (origin.center.dy / screen.height) * 2 - 1,
        );

        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              // 超椭圆而不是 ClipRRect：连续曲率才接得上迷你播放器的液态玻璃
              // 面板和真机屏幕四角，圆弧角在这个尺度上一眼能看出「拐了一下」。
              child: ClipRSuperellipse(
                key: miniPlayerExpandWindowKey,
                borderRadius: BorderRadius.circular(radius),
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: screen.width,
                  maxWidth: screen.width,
                  minHeight: screen.height,
                  maxHeight: screen.height,
                  // 反向平移把整屏正文钉回屏幕原点：窗口在动，正文不动，
                  // 于是窗口读起来是「一个逐渐扩大的取景框」而不是在推着
                  // 页面跑。
                  child: Transform.translate(
                    offset: -rect.topLeft,
                    child: FadeTransition(
                      opacity: _contentFade,
                      child: Transform.scale(
                        scale: scale,
                        alignment: anchor,
                        child: SizedBox.fromSize(size: screen, child: child),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
