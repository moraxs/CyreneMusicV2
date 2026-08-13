import 'package:flutter/material.dart';

import 'taskbar_player_bridge.dart';
import 'taskbar_player_view.dart';

/// 任务栏播放器 App（子引擎入口）。
///
/// runner 的 taskbar_player_window.cpp 创建顶层 WS_POPUP 窗口并自托管第三个
/// Flutter 引擎（entrypoint args = "taskbar-player"），该子引擎跑本 App。
/// 窗口已配置为置顶、owner 为 Shell_TrayWnd 的透明窄条（per-pixel alpha），
/// 视觉上浮在任务栏的空白区里。
///
/// 播放状态来自主窗口的推送（见 taskbar_player_bridge.dart）——本窗口是
/// 独立引擎、独立 isolate，拿不到主窗口的 PlaybackController 实例。
class TaskbarPlayerApp extends StatefulWidget {
  const TaskbarPlayerApp({super.key});

  @override
  State<TaskbarPlayerApp> createState() => _TaskbarPlayerAppState();
}

class _TaskbarPlayerAppState extends State<TaskbarPlayerApp> {
  final TaskbarPlayerClient _client = TaskbarPlayerClient();

  @override
  void initState() {
    super.initState();
    // 不必等：view 全程用 ValueListenableBuilder 监听，状态到了自然会重建。
    _client.bind();
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Taskbar Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'MiSans',
        // 透明到底：这是浮在任务栏上的覆盖层，任何底色都会糊住任务栏。
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
      ),
      home: Material(
        type: MaterialType.transparency,
        child: TaskbarPlayerView(client: _client),
      ),
    );
  }
}
