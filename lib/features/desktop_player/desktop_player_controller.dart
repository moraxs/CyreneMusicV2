import 'package:flutter/foundation.dart';

import '../../application/auth/account_session_controller.dart';
import '../../application/playback/playback_controller.dart';
import '../../app/desktop/window_workerw.dart';
import 'desktop_player_bridge.dart';

/// 桌面壁纸播放器控制器（主窗口侧）。
///
/// 不再依赖 desktop_multi_window：覆盖层窗口由 runner 自建并自托管子引擎
/// （见 windows/runner/desktop_lyrics_window.cpp），本类只负责协调主窗口的
/// 状态推送与窗口生命周期。
class DesktopPlayerController {
  DesktopPlayerController._();
  static final DesktopPlayerController instance = DesktopPlayerController._();

  DesktopPlayerStateSender? _sender;
  bool _enabled = false;
  bool get isEnabled => _enabled;

  /// 主窗口的播放控制器。启用桌面播放器前必须先设置，否则子窗口收不到
  /// 任何播放状态（歌词恒为空）。
  PlaybackController? playback;

  /// 登录态来源：面板上的收藏按钮由主窗口代为执行（子窗口没有鉴权栈）。
  /// 为空或未登录时，面板把爱心置灰。
  AccountSessionController? account;

  /// 启用桌面播放器：先建状态推送（注册 toMain 命令 handler）再创建窗口。
  ///
  /// 顺序很关键：先把主窗口的命令 handler 挂上，子引擎启动后索要状态
  /// （requestState）时主窗口一定已就绪——消灭了原插件方案下「sender 早于
  /// handler 注册导致第一帧丢失」的竞态。
  Future<String?> enable() async {
    if (_enabled) return null;
    return _enableViaNative();
  }

  Future<String?> _enableViaNative() async {
    try {
      debugPrint('[桌面播放器] 开始创建覆盖层...');

      // 1) 先建状态推送（注册 toMain handler）。子窗口的 requestState 会经
      //    原生中继到达这里，必须先就绪。
      final source = playback;
      if (source == null) {
        debugPrint('[桌面播放器] 未设置 playback，歌词将为空');
      } else {
        _sender = DesktopPlayerStateSender(playback: source, account: account);
      }

      // 2) 创建覆盖层窗口（runner 自建 + 自托管子引擎，一步到位）。
      final screenInfo = await WindowWorkerW.instance.createLyricsWindow();
      if (screenInfo.isEmpty) {
        debugPrint('[桌面播放器] 覆盖层创建失败');
        _sender?.dispose();
        _sender = null;
        return '覆盖层创建失败';
      }

      _enabled = true;
      debugPrint('[桌面播放器] 已启用，屏幕尺寸: $screenInfo');
      return null;
    } catch (e, stackTrace) {
      debugPrint('[桌面播放器] 启用失败: $e');
      debugPrint('[桌面播放器] 堆栈: $stackTrace');
      _sender?.dispose();
      _sender = null;
      _enabled = false;
      return '启用失败: $e';
    }
  }

  /// 禁用桌面播放器：销毁覆盖层窗口并恢复桌面图标。
  Future<String?> disable() async {
    // 先停推送再销毁窗口：否则销毁后仍有 invokeMethod 打到已失效的引擎。
    _sender?.dispose();
    _sender = null;
    try {
      await WindowWorkerW.instance.closeWindow()
          .timeout(const Duration(seconds: 5), onTimeout: () {
        debugPrint('[桌面播放器] closeWindow 超时，强制清理状态');
      });
      _enabled = false;
      debugPrint('[桌面播放器] 已禁用');
      return null;
    } catch (e) {
      debugPrint('[桌面播放器] 禁用失败: $e');
      _enabled = false;
      return '禁用失败: $e';
    }
  }
}
