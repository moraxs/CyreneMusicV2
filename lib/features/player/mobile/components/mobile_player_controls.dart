import 'package:flutter/material.dart';
// 只取进度指示器：原版文件按逐行移植保留，避免 miuix 全量导入与原版符号撞名。
import 'package:flutter_miuix/miuix.dart'
    show MiuixCircularProgressIndicator, MiuixProgressIndicatorColors;
import 'package:flutter_svg/flutter_svg.dart';
import '../compat/player_service.dart';
import '../compat/playback_mode_service.dart';
import '../compat/sleep_timer_service.dart';
import '../compat/download_service.dart';
import '../../../../domain/models/track.dart';
import '../compat/song_detail.dart';
import '../widgets/wavy_split_progress_bar.dart';

/// 移动端播放器控制区域组件
/// 包含进度条、播放控制按钮等（不包含音量控制，改为控制中心按钮）
class MobilePlayerControls extends StatelessWidget {
  final VoidCallback onPlaylistPressed;
  final VoidCallback onSleepTimerPressed;
  final VoidCallback onVolumeControlPressed;
  final Function(Track) onAddToPlaylistPressed;

  const MobilePlayerControls({
    super.key,
    required this.onPlaylistPressed,
    required this.onSleepTimerPressed,
    required this.onVolumeControlPressed,
    required this.onAddToPlaylistPressed,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据屏幕宽度自适应调整边距
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        final horizontalPadding = (screenWidth * 0.05).clamp(16.0, 24.0);
        final verticalPadding = (screenHeight * 0.015).clamp(12.0, 16.0);
        final itemSpacing = (screenHeight * 0.015).clamp(12.0, 20.0);
        
        return Container(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 进度条
              _buildProgressBar(),
              
              SizedBox(height: itemSpacing),
              
              // 第一行：播放模式、上一首、播放/暂停、下一首、播放列表
              _buildMainControlRow(),
              
              SizedBox(height: itemSpacing * 0.8),
              
              // 第二行：添加到歌单、睡眠定时器、音量控制、下载
              _buildSecondaryControlRow(),
            ],
          ),
        );
      },
    );
  }


  /// 构建进度条
  Widget _buildProgressBar() {
    return AnimatedBuilder(
      animation: PlayerService(),
      builder: (context, child) {
        final player = PlayerService();
        final position = player.position;
        final duration = player.duration;
        
        return ValueListenableBuilder<List<Map<String, int>>?>(
          valueListenable: player.chorusTimesNotifier,
          builder: (context, chorusTimes, child) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: WavySplitProgressBar(
                    value: duration.inMilliseconds > 0
                        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
                        : 0.0,
                    isPlaying: player.isPlaying,
                    onChanged: (value) {
                      final seekTo = duration.inMilliseconds * value;
                      player.seek(Duration(milliseconds: seekTo.toInt()));
                    },
                    activeColor: Colors.white,
                    inactiveColor: Colors.white.withValues(alpha: 0.2),
                    chorusTimes: chorusTimes,
                    durationMs: duration.inMilliseconds.toDouble(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(position),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _formatDuration(duration),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 构建主控制按钮行（第一行）
  Widget _buildMainControlRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据可用宽度自适应按钮大小和间距
        final availableWidth = constraints.maxWidth;
        final buttonSpacing = (availableWidth * 0.02).clamp(8.0, 16.0);
        final sideIconSize = (availableWidth * 0.065).clamp(24.0, 32.0);
        final skipIconSize = (availableWidth * 0.09).clamp(36.0, 48.0);
        final playButtonSize = (availableWidth * 0.15).clamp(56.0, 72.0);
        final playIconSize = (availableWidth * 0.08).clamp(32.0, 40.0);
        
        return AnimatedBuilder(
          animation: PlayerService(),
          builder: (context, child) {
            final player = PlayerService();
            
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
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
                        width: sideIconSize,
                        height: sideIconSize,
                        colorFilter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.srcIn,
                        ),
                      ),
                      iconSize: sideIconSize,
                      onPressed: () {
                        PlaybackModeService().toggleMode();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('播放模式: ${PlaybackModeService().getModeName()}'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                      tooltip: PlaybackModeService().getModeName(),
                    );
                  },
                ),
                
                SizedBox(width: buttonSpacing),
                
                // 上一首
                IconButton(
                  icon: Icon(
                    Icons.skip_previous_rounded,
                    color: player.hasPrevious ? Colors.white : Colors.white38,
                  ),
                  iconSize: skipIconSize,
                  onPressed: player.hasPrevious ? () => player.playPrevious() : null,
                  tooltip: '上一首',
                ),
                
                SizedBox(width: buttonSpacing),
                
                // 播放/暂停
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  width: playButtonSize,
                  height: playButtonSize,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(
                      player.isPlaying ? 16 : playButtonSize / 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: player.isLoading
                      ? Padding(
                          padding: EdgeInsets.all(playButtonSize * 0.28),
                          child: MiuixCircularProgressIndicator(
                            size: playButtonSize * 0.44,
                            strokeWidth: 3,
                            colors: const MiuixProgressIndicatorColors(
                              foregroundColor: Colors.black87,
                              disabledForegroundColor: Colors.black87,
                              backgroundColor: Colors.transparent,
                            ),
                          ),
                        )
                      : IconButton(
                          icon: Icon(
                            player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.black87,
                          ),
                          iconSize: playIconSize,
                          onPressed: () => player.togglePlayPause(),
                          tooltip: player.isPlaying ? '暂停' : '播放',
                        ),
                ),
                
                SizedBox(width: buttonSpacing),
                
                // 下一首
                IconButton(
                  icon: Icon(
                    Icons.skip_next_rounded,
                    color: player.hasNext ? Colors.white : Colors.white38,
                  ),
                  iconSize: skipIconSize,
                  onPressed: player.hasNext ? () => player.playNext() : null,
                  tooltip: '下一首',
                ),
                
                SizedBox(width: buttonSpacing),
                
                // 播放列表
                IconButton(
                  icon: const Icon(Icons.queue_music_rounded, color: Colors.white),
                  iconSize: sideIconSize,
                  onPressed: onPlaylistPressed,
                  tooltip: '播放列表',
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 构建次要控制按钮行（第二行）
  Widget _buildSecondaryControlRow() {
    return AnimatedBuilder(
      animation: PlayerService(),
      builder: (context, child) {
        final player = PlayerService();
        final track = player.currentTrack;
        final song = player.currentSong;
        
        if (track == null) {
          return const SizedBox.shrink();
        }
        
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 添加到歌单
            IconButton(
              icon: const Icon(Icons.playlist_add_rounded, color: Colors.white),
              iconSize: 28,
              onPressed: () => onAddToPlaylistPressed(track),
              tooltip: '添加到歌单',
            ),
            
            const SizedBox(width: 32),
            
            // 睡眠定时器
            AnimatedBuilder(
              animation: SleepTimerService(),
              builder: (context, child) {
                final timer = SleepTimerService();
                final isActive = timer.isActive;
                
                return IconButton(
                  icon: Icon(
                    isActive ? Icons.schedule : Icons.schedule_outlined,
                    color: isActive ? Colors.amber : Colors.white,
                  ),
                  iconSize: 28,
                  onPressed: onSleepTimerPressed,
                  tooltip: isActive ? '定时停止: ${timer.remainingTimeString}' : '睡眠定时器',
                );
              },
            ),
            
            const SizedBox(width: 32),
            
            // 音量控制（控制中心）
            _buildVolumeButton(),
            
            const SizedBox(width: 32),
            
            // 下载
            if (song != null)
              AnimatedBuilder(
                animation: DownloadService(),
                builder: (context, child) {
                  final downloadService = DownloadService();
                  final trackId = '${track.source.name}_${track.id}';
                  final isDownloading = downloadService.downloadTasks.containsKey(trackId);
                  
                  return IconButton(
                    icon: Icon(
                      isDownloading ? Icons.downloading_rounded : Icons.download_rounded,
                      color: Colors.white,
                    ),
                    iconSize: 28,
                    onPressed: isDownloading ? null : () => _handleDownload(context, track, song),
                    tooltip: isDownloading ? '下载中...' : '下载',
                  );
                },
              ),
          ],
        );
      },
    );
  }

  /// 处理下载
  Future<void> _handleDownload(BuildContext context, Track track, SongDetail song) async {
    try {
      // 检查是否已下载
      final isDownloaded = await DownloadService().isDownloaded(track);
      
      if (isDownloaded) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('该歌曲已下载'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
      
      // 开始下载
      final success = await DownloadService().downloadSong(track, song);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '开始下载' : '下载失败'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('下载失败: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// 构建音量控制按钮
  Widget _buildVolumeButton() {
    return AnimatedBuilder(
      animation: PlayerService(),
      builder: (context, child) {
        final player = PlayerService();
        final volume = player.volume;
        
        return IconButton(
          icon: Icon(
            volume == 0 
                ? Icons.volume_off_rounded 
                : volume < 0.5 
                    ? Icons.volume_down_rounded 
                    : Icons.volume_up_rounded,
            color: Colors.white,
          ),
          iconSize: 28,
          onPressed: onVolumeControlPressed,
          tooltip: '控制中心',
        );
      },
    );
  }

  /// 格式化时长
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}