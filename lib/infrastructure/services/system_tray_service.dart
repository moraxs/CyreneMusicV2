import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Windows 系统托盘服务。
///
/// 关闭主窗口时不退出进程，仅隐藏窗口并驻留系统托盘；点击托盘图标/「显示主
/// 界面」恢复窗口，「退出」才真正销毁窗口结束进程。此语义与主流音乐应用一致。
///
/// 仅 Windows 生效；其他平台各方法为空操作。图标用原生 `NOTIFYICONDATA`
/// （tray_manager 底层），由系统按 DPI 缩放，呈现 Win11 原生托盘样式。
class SystemTrayService {
  SystemTrayService._();

  static final SystemTrayService instance = SystemTrayService._();

  bool _initialized = false;
  bool _isQuitting = false;

  bool get isQuitting => _isQuitting;

  /// 初始化托盘：设置图标、提示与右键菜单，并接管窗口关闭事件。
  Future<void> initialize() async {
    if (!Platform.isWindows || _initialized) return;
    _initialized = true;

    try {
      // Windows 托盘图标用 .ico：tray_manager 在 Windows 上经 LoadImage(…,
      // IMAGE_ICON, SM_CXSMICON, SM_CYSMICON, LR_LOADFROMFILE) 把 PNG 强制按
      // 图标格式加载。普通 256x256 PNG 没有图标帧，会失败/空白；.ico 内置
      // 16~256 多分辨率图标帧，系统按 DPI 选帧，托盘里才是实体而非空白。
      await trayManager.setIcon('assets/icons/tray_icon.ico');
      await trayManager.setToolTip('Cyrene Music');
      await _rebuildMenu();

      trayManager.addListener(_TrayEventListener(service: this));
      // 拦截原生关闭：WM_CLOSE 走 onWindowClose，改为隐藏而不是退出。
      await windowManager.setPreventClose(true);
    } catch (e) {
      // 托盘创建失败不影响主功能，仅记录。
      debugPrint('[SystemTray] 初始化失败: $e');
      _initialized = false;
    }
  }

  Future<void> _rebuildMenu() async {
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(
            key: 'show',
            label: '显示主界面',
            onClick: (_) => showMainWindow(),
          ),
          MenuItem(
            key: 'play_pause',
            label: '播放 / 暂停',
            onClick: (_) => _onPlayPause?.call(),
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'quit',
            label: '退出',
            onClick: (_) => quit(),
          ),
        ],
      ),
    );
  }

  /// 播放/暂停回调，由主应用在装配时注入。
  void Function()? _onPlayPause;

  void bind({required void Function() onPlayPause}) {
    _onPlayPause = onPlayPause;
  }

  /// 由窗口关闭事件触发：隐藏窗口并驻留托盘。
  Future<void> hideToTray() async {
    if (_isQuitting) return;
    // 关闭即隐藏到托盘（后台运行）。
    await windowManager.hide();
    debugPrint('[SystemTray] 窗口已隐藏到托盘');
  }

  /// 从托盘恢复主窗口。
  Future<void> showMainWindow() async {
    if (!_initialized) return;
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('[SystemTray] 恢复窗口失败: $e');
    }
  }

  /// 真正退出：标记退出态并销毁窗口（触发原生 WM_CLOSE → 进程结束）。
  Future<void> quit() async {
    _isQuitting = true;
    await trayManager.destroy();
    await windowManager.destroy();
  }
}

/// 托盘事件监听：左键/右键点击图标均恢复主窗口（右击由插件弹菜单，此处兜底）。
class _TrayEventListener with TrayListener {
  _TrayEventListener({required this.service});

  final SystemTrayService service;

  @override
  void onTrayIconMouseDown() {
    service.showMainWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    // Windows 上右键菜单不会由插件自动弹出：插件在 WM_RBUTTONUP 时只回调
    // Dart（onTrayIconRightMouseDown），从不调用 TrackPopupMenu，而本项目
    // 之前把右击当成了"恢复窗口"，导致右键看似无反应。这里改为显式弹菜单
    // （原生经 GetCursorPos + TrackPopupMenu 在光标处弹出）；若个别环境
    // 菜单未弹出，仍兜底恢复窗口。
    // 托盘菜单要正确弹出并能在点击别处后收起，需先 SetForegroundWindow；
    // 该参数虽被标记废弃（仅 Windows 支持、未来会移除），但本项目仅此一处
    // Windows 托盘弹菜单，按官方推荐保留。
    // ignore: deprecated_member_use
    trayManager.popUpContextMenu(bringAppToFront: true);
  }

  @override
  void onTrayIconMouseUp() {}

  @override
  void onTrayIconRightMouseUp() {}

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    // 菜单项回调已在 MenuItem.onClick 里处理，这里无需额外动作。
  }
}
