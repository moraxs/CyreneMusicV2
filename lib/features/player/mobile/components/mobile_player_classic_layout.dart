import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixIcon, MiuixIcons;
import 'package:flutter_svg/flutter_svg.dart';
import '../compat/player_service.dart';
import '../compat/player_background_service.dart';
import 'mobile_player_app_bar.dart';
import 'mobile_player_dialogs.dart';
// import 'mobile_player_song_info.dart';
import 'mobile_player_karaoke_lyric.dart';
import '../mobile_lyric_page.dart';
import '../compat/lyric_line.dart';
import '../compat/playback_mode_service.dart';
import '../widgets/wavy_split_progress_bar.dart';

/// 移动端经典播放器布局 (Material Design Expressive)
/// 特点：
/// 1. 分段式播放控制 (Previous | Play/Pause | Next) - 胶囊形状
/// 2. 大圆角专辑封面
/// 3. 粗体大字号歌曲信息
/// 4. 动态取色主题适配
class MobilePlayerClassicLayout extends StatelessWidget {
  final List<LyricLine> lyrics;
  final int currentLyricIndex;
  final VoidCallback onBackPressed;
  final VoidCallback? onPlaylistPressed;

  const MobilePlayerClassicLayout({
    super.key,
    required this.lyrics,
    required this.currentLyricIndex,
    required this.onBackPressed,
    this.onPlaylistPressed,
  });

  @override
  Widget build(BuildContext context) {
    final player = PlayerService();
    final backgroundService = PlayerBackgroundService();
    
    // 检查是否显示封面 (非自适应背景时)
    final showCover = !backgroundService.enableGradient || 
                      backgroundService.backgroundType != PlayerBackgroundType.adaptive;

    return Column(
      children: [
        // 顶部栏
        MobilePlayerAppBar(
          onBackPressed: onBackPressed,
        ),

        // 主要内容区域
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 响应式布局参数
              final screenHeight = MediaQuery.of(context).size.height;
              final isSmallScreen = screenHeight < 700;
              
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. 专辑封面区域 (弹性空间，但有最大限制)
                         if (showCover)
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 16 : 32),
                            child: Center(
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: Container(
                                  constraints: const BoxConstraints(maxHeight: 380, maxWidth: 380),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.3),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: _buildAlbumCover(player),
                                ),
                              ),
                            ),
                          )
                        else
                          // 如果不显示封面（例如纯色背景或歌词模式），则显示歌词/可视化占位
                          Container(
                            height: 300,
                            alignment: Alignment.center,
                            child: MobilePlayerKaraokeLyric(
                              lyrics: lyrics,
                              currentLyricIndex: currentLyricIndex,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const MobileLyricPage(),
                                ),
                              ),
                              showTranslation: true,
                            ),
                          ),

                        const SizedBox(height: 24),

                        // 2. 歌曲信息 (大标题)
                        _buildSongInfo(context, player),
                        
                        const SizedBox(height: 24),

                        // 3. 进度条 (Expressive Style - 粗轨道)
                        _buildExpressiveProgressBar(context, player),
                        
                        const SizedBox(height: 12), // 时间标签和进度条之间的间距

                        // 4. 控制区域 (分段式胶囊按钮)
                        _buildExpressiveControls(context, player),

                        // 5. 底部次要功能 (播放列表、更多等)
                        const SizedBox(height: 24),
                        _buildBottomActions(context),
                        
                        const SizedBox(height: 48), // 底部安全留白
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumCover(PlayerService player) {
    // 复用现有逻辑获取封面URL
    final song = player.currentSong;
    final track = player.currentTrack;
    final picUrl = song?.pic ?? track?.picUrl;

    if (picUrl == null || picUrl.isEmpty) {
      return Container(
        color: Colors.white10,
        child: const Icon(Icons.music_note_rounded, size: 80, color: Colors.white24),
      );
    }
    
    // 这里使用 Image.network 或 CachedNetworkImage，暂用简单的 Image via Network
    return Image.network(
      picUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        color: Colors.white10,
        child: const Icon(Icons.broken_image_rounded, size: 60, color: Colors.white24),
      ),
    );
  }

  Widget _buildSongInfo(BuildContext context, PlayerService player) {
    final song = player.currentSong;
    final track = player.currentTrack;
    final title = song?.name ?? track?.name ?? '未知歌曲';
    final artist = song?.arName ?? track?.artists ?? '未知艺术家';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                artist,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        // 收藏/喜欢按钮
        if (track != null)
           IconButton(
            icon: const Icon(Icons.favorite_border_rounded, color: Colors.white), // TODO: 集成真实的喜欢状态
            // icon: Icon(isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded, 
            //       color: isLiked ? Colors.redAccent : Colors.white),
            onPressed: () {
              // TODO: 喜欢逻辑
               ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('功能开发中')),
                );
            },
          ),
      ],
    );
  }

  Widget _buildExpressiveProgressBar(BuildContext context, PlayerService player) {
    return AnimatedBuilder(
      animation: player.positionNotifier,
      builder: (context, _) {
        final position = player.positionNotifier.value;
        final duration = player.duration;
        final max = duration.inMilliseconds.toDouble();
        final value = position.inMilliseconds.toDouble().clamp(0.0, max > 0 ? max : 0.0);

        return Column(
          children: [
            WavySplitProgressBar(
              value: max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0,
              isPlaying: player.isPlaying,
              onChanged: (v) {
                player.seek(Duration(milliseconds: (v * max).toInt()));
              },
              activeColor: Colors.white,
              inactiveColor: Colors.white.withValues(alpha: 0.15),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(position),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    _formatDuration(duration),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildExpressiveControls(BuildContext context, PlayerService player) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 上一首
        _buildExpressiveControlButton(
          context: context,
          icon: Icons.skip_previous_rounded,
          onTap: player.hasPrevious ? player.playPrevious : null,
          size: 64,
          iconSize: 32,
          color: colorScheme.surfaceContainerHighest,
          iconColor: player.hasPrevious ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: 0.38),
        ),
        
        const SizedBox(width: 12),

        // 播放/暂停
        AnimatedBuilder(
          animation: player,
          builder: (context, _) => _buildExpressiveControlButton(
            context: context,
            icon: player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            onTap: player.togglePlayPause,
            size: 84,
            iconSize: 48,
            color: colorScheme.primaryContainer,
            iconColor: colorScheme.onPrimaryContainer,
            isPrimary: true,
            borderRadius: player.isPlaying ? 16 : 42, // 播放时方形(16)，暂停时圆(84/2=42)
          ),
        ),

        const SizedBox(width: 12),

        // 下一首
        _buildExpressiveControlButton(
          context: context,
          icon: Icons.skip_next_rounded,
          onTap: player.hasNext ? player.playNext : null,
          size: 64,
          iconSize: 32,
          color: colorScheme.surfaceContainerHighest,
          iconColor: player.hasNext ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: 0.38),
        ),
      ],
    );
  }
  Widget _buildExpressiveControlButton({
    required BuildContext context,
    required IconData icon,
    required VoidCallback? onTap,
    required double size,
    required double iconSize,
    required Color color,
    required Color iconColor,
    bool isPrimary = false,
    double? borderRadius,
  }) {
    final effectiveBorderRadius = borderRadius ?? (isPrimary ? 28.0 : 24.0);
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: size,
      height: size,
      decoration: ShapeDecoration(
        color: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(effectiveBorderRadius),
        ),
        shadows: isPrimary ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ] : null,
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(effectiveBorderRadius),
        ),
        child: Center(
          child: Icon(
            icon,
            size: iconSize,
            color: iconColor,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
         // 播放模式
        AnimatedBuilder(
          animation: PlaybackModeService(),
          builder: (context, child) {
            final mode = PlaybackModeService().currentMode;
            final asset = switch (mode) {
              PlaybackMode.sequential => 'assets/icons/LucideRepeat.svg',
              PlaybackMode.repeatOne => 'assets/icons/MaterialSymbolsRepeatOneRounded.svg',
              PlaybackMode.shuffle => 'assets/icons/BxShuffle.svg',
            };
            return IconButton(
              icon: SvgPicture.asset(
                asset,
                width: 26,
                height: 26,
                colorFilter: const ColorFilter.mode(
                  Colors.white70,
                  BlendMode.srcIn,
                ),
              ),
              iconSize: 26,
              onPressed: () {
                PlaybackModeService().toggleMode();
                 ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('播放模式: ${PlaybackModeService().getModeName()}'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
              },
            );
          },
        ),

        // 睡眠定时器
        IconButton(
          icon: const Icon(Icons.schedule_rounded, color: Colors.white70),
          iconSize: 26,
          onPressed: () => MobilePlayerDialogs.showSleepTimer(context),
        ),

        // 下载
        IconButton(
           icon: MiuixIcon(
             vector: MiuixIcons.extended.byName('download')!,
             size: 26,
             tint: Colors.white70,
           ),
           onPressed: () {
              final track = PlayerService().currentTrack;
              if (track != null) {
                 ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('检查下载状态...')),
                );
                // 实际逻辑可参考 MobilePlayerControls
              }
           },
        ),

        // 播放列表
        IconButton(
          icon: MiuixIcon(
            vector: MiuixIcons.extended.byName('playlist')!,
            size: 26,
            tint: Colors.white70,
          ),
          onPressed: () => MobilePlayerDialogs.showPlaylistBottomSheet(context),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
