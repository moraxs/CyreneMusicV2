import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/stores/fullscreen_settings_store.dart';
import '../player/super_cyrene/super_cyrene_chat_lyrics.dart';
import '../player/super_cyrene/super_cyrene_classic_lyrics.dart';
import '../player/super_cyrene/super_cyrene_pixel_lyrics.dart';
import '../player/super_cyrene/super_cyrene_sonnet_lyrics.dart';
import 'desktop_classic_lyrics.dart';
import 'desktop_player_panel.dart';
import 'desktop_player_playback.dart';

/// 桌面壁纸播放器的歌词视图。
///
/// 与全屏播放器的关键差异：**不渲染任何背景**。这是一个透明的桌面覆盖层，
/// 背后要透出 Wallpaper Engine 的壁纸；任何底色（哪怕是半透明的）都会糊住
/// 整个桌面。歌词自带描边/阴影保证在任意壁纸上可读。
///
/// 复用的是歌词层而非整个 FullscreenPlayer：后者带背景、悬停标题栏和
/// windowManager 逻辑，在点击穿透的置底覆盖层上都没有意义。
class DesktopPlayerView extends StatefulWidget {
  const DesktopPlayerView({super.key, required this.playback});

  final DesktopPlayerPlayback playback;

  @override
  State<DesktopPlayerView> createState() => _DesktopPlayerViewState();
}

class _DesktopPlayerViewState extends State<DesktopPlayerView> {
  /// 展览馆是否打开，由 [DesktopPlayerPanel] 写入。
  ///
  /// 展览馆的背景是 DWM 壁纸亚克力（原生窗口效果，在整个 Flutter 图层之下），
  /// Flutter 画的歌词必然浮在它之上——表现为歌词穿透模糊层。因此展览馆打开
  /// 时把歌词层藏起来，关闭后恢复。
  final ValueNotifier<bool> _galleryOpen = ValueNotifier<bool>(false);

  /// 歌词编辑模式（拖拽定位 / 缩放 / 三轴旋转），同样由面板写入。
  final ValueNotifier<bool> _editMode = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _galleryOpen.dispose();
    _editMode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.playback.controller;
    return AnimatedBuilder(
      animation: Listenable.merge([
        controller,
        FullscreenSettingsStore.instance,
      ]),
      builder: (context, _) {
        final track = controller.state.currentTrack;
        if (track == null) {
          // 无曲目时仍要挂出面板：否则停止播放后就再也调不出设置了。
          return Stack(
            children: [
              const Center(
                child: Text(
                  'Cyrene 桌面歌词',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 16,
                    letterSpacing: 4,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                  ),
                ),
              ),
              DesktopPlayerPanel(
                playback: controller,
                source: widget.playback,
                galleryOpen: _galleryOpen,
                editMode: _editMode,
              ),
            ],
          );
        }

        final settings = FullscreenSettingsStore.instance;
        // 与全屏播放器共用同一份偏好。面板把「经典」也并入歌词样式：
        // superCyrene 关 → 经典，开 → 取它的歌词主题（见 desktop_player_panel）。
        final style = settings.superCyrenePlayerEnabled
            ? settings.superCyreneLyricsTheme
            : 'classic';

        final lyrics = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 64),
          child: switch (style) {
            // 经典：复用经典播放器的流体云歌词组件，与 SuperCyrene 默认主题
            // 逐行逐字渲染区分（见 DesktopClassicLyrics）。
            'classic' => DesktopClassicLyrics(
              playback: controller,
              track: track,
            ),
            'pixel' => SuperCyrenePixelLyrics(
              playback: controller,
              track: track,
              onTranslationChanged: (_) {},
            ),
            'chat' => SuperCyreneChatLyrics(
              playback: controller,
              track: track,
              // 覆盖层不加载封面/头像：它们会带来不透明色块，
              // 且桌面歌词不需要聊天气泡的身份标识。
              cover: null,
            ),
            'sonnet' => SuperCyreneSonnetLyrics(
              playback: controller,
              track: track,
              onTranslationChanged: (_) {},
            ),
            // 'default' 与 SuperCyrene 的默认逐行逐字主题对应。
            _ => SuperCyreneClassicLyrics(
              playback: controller,
              track: track,
              onTranslationChanged: (_) {},
            ),
          },
        );

        return Stack(
          children: [
            // Offstage 而非条件移除：歌词组件内部靠 ticker 和自身状态维持时序
            // （含 4s INTRO_DELAY 的进度换算），卸载会丢掉这些状态，关闭展览馆
            // 后歌词要重新对齐甚至跳位。Offstage 保留 build 与动画驱动，只是
            // 不绘制、不参与命中测试。
            ValueListenableBuilder<bool>(
              valueListenable: _galleryOpen,
              builder: (context, galleryOpen, child) =>
                  Offstage(offstage: galleryOpen, child: child),
              child: _TransformableLyrics(
                // 「默认」样式不参与变换：它自带精心设计的逐行逐字排版，
                // 平移/旋转会破坏其视觉语言。
                enabled: style != 'default',
                editMode: _editMode,
                settings: settings,
                child: lyrics,
              ),
            ),
            DesktopPlayerPanel(
              playback: controller,
              source: widget.playback,
              galleryOpen: _galleryOpen,
              editMode: _editMode,
            ),
          ],
        );
      },
    );
  }
}

/// 给歌词层套上用户自定义的 3D 变换，并在编辑模式下提供拖拽定位。
///
/// [enabled] 为 false 时原样返回 [child]（「默认」样式走这条路径），连
/// [Transform] 都不套——保证该样式的渲染与本功能加入前逐像素一致。
class _TransformableLyrics extends StatelessWidget {
  const _TransformableLyrics({
    required this.enabled,
    required this.editMode,
    required this.settings,
    required this.child,
  });

  final bool enabled;
  final ValueNotifier<bool> editMode;
  final FullscreenSettingsStore settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    final transformed = Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        // 透视：没有它，X/Y 轴旋转退化成纯粹的垂直/水平压扁，没有立体感。
        ..setEntry(3, 2, 0.001)
        ..leftTranslateByDouble(
          settings.desktopLyricOffsetX,
          settings.desktopLyricOffsetY,
          0,
          1,
        )
        ..rotateX(settings.desktopLyricRotX)
        ..rotateY(settings.desktopLyricRotY)
        ..rotateZ(settings.desktopLyricRotZ)
        // Matrix4 的 translate/scale 已弃用；这里用 leftTranslate 加显式
        // 缩放矩阵避免触发弃用告警。
        ..multiply(Matrix4.diagonal3Values(
          settings.desktopLyricScale,
          settings.desktopLyricScale,
          settings.desktopLyricScale,
        )),
      child: child,
    );

    return ValueListenableBuilder<bool>(
      valueListenable: editMode,
      builder: (context, editing, _) {
        if (!editing) return transformed;
        // 拖拽层刻意放在 Transform **之外**：手势拿到的是未变换的屏幕坐标，
        // 直接累加到 translate 上，因此无论歌词被旋转成什么角度，拖拽方向
        // 始终跟手。若放进 Transform 内部，Z 轴转 90° 后左右拖拽会变成上下移动。
        return Stack(
          fit: StackFit.expand,
          children: [
            transformed,
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) => settings.setDesktopLyricOffset(
                  settings.desktopLyricOffsetX + details.delta.dx,
                  settings.desktopLyricOffsetY + details.delta.dy,
                ),
                child: MouseRegion(
                  cursor: SystemMouseCursors.move,
                  child: CustomPaint(painter: _EditModeBorderPainter()),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 编辑模式的虚线取景框：提示「这块区域现在可以拖」。
class _EditModeBorderPainter extends CustomPainter {
  const _EditModeBorderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x66A78BFA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const dash = 12.0;
    const gap = 8.0;
    final rect = Rect.fromLTWH(4, 4, size.width - 8, size.height - 8);

    // 沿矩形四边走一圈画虚线。
    for (double x = rect.left; x < rect.right; x += dash + gap) {
      final end = math.min(x + dash, rect.right);
      canvas.drawLine(Offset(x, rect.top), Offset(end, rect.top), paint);
      canvas.drawLine(Offset(x, rect.bottom), Offset(end, rect.bottom), paint);
    }
    for (double y = rect.top; y < rect.bottom; y += dash + gap) {
      final end = math.min(y + dash, rect.bottom);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.left, end), paint);
      canvas.drawLine(Offset(rect.right, y), Offset(rect.right, end), paint);
    }
  }

  @override
  bool shouldRepaint(_EditModeBorderPainter oldDelegate) => false;
}
