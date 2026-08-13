import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../player/mobile/compat/image_utils.dart';
import 'taskbar_player_bridge.dart';

/// 任务栏播放器窄条 UI（子引擎侧）。
///
/// 高度就是任务栏的高度（100% 缩放下 48 逻辑像素），所以一切尺寸都必须紧凑：
/// 32px 封面 + 两行小字 + 三个 24px 按钮，垂直方向几乎没有余量。
///
/// 配色跟随系统明暗：Windows 任务栏的底色由「选择模式」系统设置决定，
/// 该设置同时反映在 platformBrightness 上。窗口本身是全透明的，文字直接
/// 画在任务栏上，因此选错明暗会直接看不清。
class TaskbarPlayerView extends StatelessWidget {
  const TaskbarPlayerView({super.key, required this.client});

  final TaskbarPlayerClient client;

  @override
  Widget build(BuildContext context) {
    // 任务栏底色跟随系统明暗；亮色任务栏用深字，暗色任务栏用浅字。
    final isDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final primary = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final secondary = isDark
        ? Colors.white.withValues(alpha: 0.62)
        : const Color(0xFF1A1A1A).withValues(alpha: 0.60);

    return ValueListenableBuilder<TaskbarPlayerState>(
      valueListenable: client.state,
      builder: (context, state, _) {
        // 没有曲目时整条隐形：任务栏空白区本来就该是空的，摆一个「未在播放」
        // 的占位反而碍眼。
        if (!state.hasTrack) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: [
              _Cover(url: state.coverUrl, isDark: isDark),
              const SizedBox(width: 8),
              Expanded(
                child: _DragArea(
                  child: _TrackInfo(
                    state: state,
                    primary: primary,
                    secondary: secondary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _ControlButton(
                icon: state.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                tooltip: state.isPlaying ? '暂停' : '播放',
                color: primary,
                onTap: () => TaskbarPlayerClient.send('togglePlay'),
              ),
              _ControlButton(
                icon: Icons.skip_next_rounded,
                tooltip: '下一首',
                color: primary,
                onTap: () => TaskbarPlayerClient.send('next'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 专辑封面。点击唤起主窗口。
class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.isDark});

  final String url;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 32,
      height: 32,
      color: isDark
          ? Colors.white.withValues(alpha: 0.10)
          : Colors.black.withValues(alpha: 0.08),
      child: Icon(
        Icons.music_note_rounded,
        size: 18,
        color: isDark
            ? Colors.white.withValues(alpha: 0.55)
            : Colors.black.withValues(alpha: 0.45),
      ),
    );

    return Tooltip(
      message: '打开 Cyrene Music',
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => TaskbarPlayerClient.send('showMain'),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: url.isEmpty
              ? placeholder
              // 封面统一走磁盘缓存 + 网易 UA（见 image_utils.dart）；
              // 不要把 url 强转 https，部分源只提供明文地址。
              : CachedNetworkImage(
                  imageUrl: url,
                  httpHeaders: getImageHeaders(url),
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => placeholder,
                  errorWidget: (_, _, _) => placeholder,
                ),
        ),
      ),
    );
  }
}

/// 拖拽把手：按下即把窗口交给 Windows 的模态移动循环。
///
/// 只包住中间的曲目信息区——封面要点击唤起主窗口，右侧两个按钮要点击控制
/// 播放，都不能被拖拽吃掉。这也符合直觉：拖「标题那一片」来移动窗口。
///
/// 用 onPanDown 而非 onPanStart：后者要等手势竞技场判定出拖拽意图（需要
/// 移动几个像素），那几像素里窗口不动，手感是「先卡一下再跟上」。onPanDown
/// 在按下瞬间就触发，之后的移动完全由系统循环接管，跟手无延迟。
///
/// 副作用是单击这片区域也会进一次系统移动循环，但用户没移动鼠标的话窗口
/// 不会动，松手即结束——无感。
class _DragArea extends StatelessWidget {
  const _DragArea({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: (_) => TaskbarPlayerClient.beginDrag(),
      child: MouseRegion(cursor: SystemMouseCursors.move, child: child),
    );
  }
}

/// 标题 + 歌手。
class _TrackInfo extends StatelessWidget {
  const _TrackInfo({
    required this.state,
    required this.primary,
    required this.secondary,
  });

  final TaskbarPlayerState state;
  final Color primary;
  final Color secondary;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: primary,
          ),
        ),
        Text(
          state.artists,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10.5, height: 1.25, color: secondary),
        ),
      ],
    );
  }
}

/// 紧凑的图标按钮。任务栏高度有限，用 24x24 的点击区。
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
