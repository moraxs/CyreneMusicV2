import 'package:flutter/material.dart';

import '../../application/stores/fullscreen_settings_store.dart';
import '../player/super_cyrene/super_cyrene_chat_lyrics.dart';
import '../player/super_cyrene/super_cyrene_classic_lyrics.dart';
import '../player/super_cyrene/super_cyrene_pixel_lyrics.dart';
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

  @override
  void dispose() {
    _galleryOpen.dispose();
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
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 48,
                  vertical: 64,
                ),
                child: switch (style) {
                  // 经典：复用经典播放器的流体云歌词组件，与 SuperCyrene 默认
                  // 主题逐行逐字渲染区分（见 DesktopClassicLyrics）。
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
                  // 'default' 与 SuperCyrene 的默认逐行逐字主题对应。
                  _ => SuperCyreneClassicLyrics(
                    playback: controller,
                    track: track,
                    onTranslationChanged: (_) {},
                  ),
                },
              ),
            ),
            DesktopPlayerPanel(
              playback: controller,
              source: widget.playback,
              galleryOpen: _galleryOpen,
            ),
          ],
        );
      },
    );
  }
}
