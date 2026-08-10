import 'package:flutter/material.dart';

import '../../application/stores/fullscreen_settings_store.dart';
import 'desktop_player_playback.dart';
import 'desktop_player_view.dart';

/// 壁纸层歌词播放器 App（子引擎入口）。
///
/// runner 的 desktop_lyrics_window.cpp 创建顶层 WS_POPUP 覆盖层并自托管
/// 第二个 Flutter 引擎（entrypoint args = "wallpaper-player"），该子引擎
/// 跑本 App。窗口已配置为透明置底的桌面覆盖层（per-pixel alpha、整窗穿透、
/// 命中矩形内可交互）。
///
/// 播放状态来自主窗口的推送（见 desktop_player_bridge.dart）——本窗口是
/// 独立引擎、独立 isolate，拿不到主窗口的 PlaybackController 实例。
class DesktopPlayerApp extends StatefulWidget {
  const DesktopPlayerApp({super.key});

  @override
  State<DesktopPlayerApp> createState() => _DesktopPlayerAppState();
}

class _DesktopPlayerAppState extends State<DesktopPlayerApp> {
  final DesktopPlayerPlayback _playback = DesktopPlayerPlayback();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 歌词主题偏好与主窗口共用同一份存储，子窗口需自行初始化。
    await FullscreenSettingsStore.instance.init();
    await _playback.bind();
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _playback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Desktop Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'MiSans',
        // 透明到底：这是桌面覆盖层，任何底色都会糊住桌面。
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
      ),
      home: Material(
        type: MaterialType.transparency,
        child: _ready
            ? DesktopPlayerView(playback: _playback)
            : const SizedBox.shrink(),
      ),
    );
  }
}
