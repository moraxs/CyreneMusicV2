import 'package:flutter/material.dart';
import 'mobile_player_settings_sheet.dart';

/// 移动端播放器顶部应用栏组件（原版的 Windows 分支已随桌面端裁剪）。
class MobilePlayerAppBar extends StatelessWidget {
  final VoidCallback onBackPressed;

  const MobilePlayerAppBar({
    super.key,
    required this.onBackPressed,
  });

  @override
  Widget build(BuildContext context) {
    // 移动平台：显示普通返回按钮
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
            iconSize: 32,
            onPressed: onBackPressed,
          ),
          const Text(
            '正在播放',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {
              MobilePlayerSettingsSheet.show(context);
            },
          ),
        ],
      ),
    );
  }
}
