import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_miuix/miuix.dart';
import '../../../../presentation/cyrene/cyrene_overlays.dart';
import '../compat/sleep_timer_service.dart';
import '../compat/playlist_service.dart';
import '../compat/playlist_queue_service.dart';
import '../compat/play_history_service.dart';
import '../compat/player_service.dart';
import '../compat/toast_utils.dart';
import '../../../../domain/models/track.dart';
import '../../../../domain/models/media_url.dart';

/// 移动端播放器对话框工具类
/// 包含睡眠定时器、添加到歌单、播放列表等对话框
class MobilePlayerDialogs {
  /// 显示睡眠定时器对话框
  static void showSleepTimer(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const MobileSleepTimerDialog(),
    );
  }

  /// 显示添加到歌单底部抽屉（Miuix 风格）
  static void showAddToPlaylist(BuildContext context, Track track) {
    final playlistService = PlaylistService();

    // 确保已加载歌单列表
    if (playlistService.playlists.isEmpty) {
      playlistService.loadPlaylists();
    }

    showCyreneSheet<void>(
      context: context,
      title: '添加到歌单',
      insideMargin: 16,
      builder: (sheetContext, dismiss) {
        final theme = MiuixTheme.of(sheetContext);

        return AnimatedBuilder(
          animation: playlistService,
          builder: (context, child) {
            final playlists = playlistService.playlists;

            if (playlists.isEmpty) {
              return const SizedBox(
                height: 180,
                child: Center(
                  child: MiuixCircularProgressIndicator(size: 36),
                ),
              );
            }

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.65,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: playlists.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return MiuixCard(
                    cornerRadius: 14,
                    insideMargin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    colors: MiuixCardColors(
                      color: theme.colors.surfaceContainer,
                      contentColor: theme.colors.onSurface,
                    ),
                    feedbackType: MiuixPressFeedbackType.sink,
                    onPressed: () async {
                      dismiss();
                      final success =
                          await playlistService.addTrackToPlaylist(
                        playlist.id,
                        track,
                      );
                      if (context.mounted) {
                        ToastUtils.info(
                          success
                              ? '已添加到「${playlist.name}」'
                              : '添加失败',
                        );
                      }
                    },
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: ShapeDecoration(
                            color: playlist.isDefault
                                ? theme.colors.primary.withValues(alpha: 0.14)
                                : theme.colors.surfaceContainer,
                            shape: const MiuixSquircleBorder(cornerRadius: 10),
                          ),
                          child: Icon(
                            playlist.isDefault
                                ? Icons.favorite_rounded
                                : Icons.queue_music_rounded,
                            color: playlist.isDefault
                                ? theme.colors.primary
                                : theme.colors.onSurfaceVariantSummary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              MiuixText(
                                playlist.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textStyles.body1.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              MiuixText(
                                '${playlist.trackCount} 首歌曲',
                                style: theme.textStyles.footnote2.copyWith(
                                  color: theme.colors.onSurfaceVariantSummary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  /// 显示播放列表底部抽屉（Miuix 风格）
  static void showPlaylistBottomSheet(BuildContext context) {
    final queueService = PlaylistQueueService();
    final history = PlayHistoryService().history;
    final currentTrack = PlayerService().currentTrack;

    // 优先使用播放队列，如果没有队列则使用播放历史
    final bool hasQueue = queueService.hasQueue;
    final List<dynamic> displayList = hasQueue
        ? queueService.queue
        : history.map((h) => h.toTrack()).toList();
    final String listTitle = hasQueue
        ? '播放队列 (${queueService.source.name})'
        : '播放历史';

    showCyreneSheet<void>(
      context: context,
      title: listTitle,
      insideMargin: 16,
      endAction: Builder(
        builder: (context) {
          final theme = MiuixTheme.of(context);
          return MiuixText(
            '${displayList.length} 首',
            style: theme.textStyles.footnote2.copyWith(
              color: theme.colors.onSurfaceVariantSummary,
            ),
          );
        },
      ),
      builder: (sheetContext, dismiss) {
        final theme = MiuixTheme.of(sheetContext);

        if (displayList.isEmpty) {
          return SizedBox(
            height: 220,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.music_off_rounded,
                    size: 48,
                    color: theme.colors.onSurfaceVariantSummary,
                  ),
                  const SizedBox(height: 12),
                  MiuixText(
                    '播放列表为空',
                    style: theme.textStyles.body2.copyWith(
                      color: theme.colors.onSurfaceVariantSummary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: displayList.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final item = displayList[index];
              final track = item is Track
                  ? item
                  : (item as PlayHistoryItem).toTrack();
              final isCurrentTrack = currentTrack != null &&
                  track.id.toString() == currentTrack.id.toString() &&
                  track.source == currentTrack.source;

              return _buildPlaylistItem(
                context,
                track,
                index,
                isCurrentTrack,
                dismiss,
              );
            },
          ),
        );
      },
    );
  }

  /// 构建 Miuix 风格播放列表项
  static Widget _buildPlaylistItem(
    BuildContext context,
    Track track,
    int index,
    bool isCurrentTrack,
    void Function([dynamic result]) dismiss,
  ) {
    final theme = MiuixTheme.of(context);

    return MiuixCard(
      cornerRadius: 14,
      insideMargin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      colors: MiuixCardColors(
        color: isCurrentTrack
            ? theme.colors.secondaryContainer
            : Colors.transparent,
        contentColor: theme.colors.onSurface,
      ),
      feedbackType: MiuixPressFeedbackType.sink,
      onPressed: () {
        PlayerService().playTrack(track);
        dismiss();
        ToastUtils.info('正在播放: ${track.name}');
      },
      child: Row(
        children: [
          // 序号或正在播放指示
          SizedBox(
            width: 28,
            child: Center(
              child: isCurrentTrack
                  ? Icon(
                      Icons.volume_up_rounded,
                      color: theme.colors.primary,
                      size: 18,
                    )
                  : MiuixText(
                      '${index + 1}',
                      style: theme.textStyles.footnote1.copyWith(
                        color: theme.colors.onSurfaceVariantSummary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ),

          const SizedBox(width: 8),

          // 封面图片（超椭圆圆角）
          ClipPath.shape(
            shape: const MiuixSquircleBorder(cornerRadius: 10),
            child: SizedBox(
              width: 44,
              height: 44,
              child: _buildCoverImage(track.picUrl),
            ),
          ),

          const SizedBox(width: 12),

          // 歌曲信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MiuixText(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.body1.copyWith(
                    color: isCurrentTrack
                        ? theme.colors.primary
                        : theme.colors.onSurface,
                    fontWeight:
                        isCurrentTrack ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                MiuixText(
                  track.artists,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.footnote2.copyWith(
                    color: theme.colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建封面图片（支持网络 URL 和本地文件路径）
  static Widget _buildCoverImage(String imageUrl) {
    // 判断是网络 URL 还是本地文件路径
    final isNetwork =
        imageUrl.startsWith('http://') || imageUrl.startsWith('https://');

    if (isNetwork) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        httpHeaders: imageHeaders(imageUrl),
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (context, url) => Container(
          width: 44,
          height: 44,
          color: Colors.white12,
        ),
        errorWidget: (context, url, error) => Container(
          width: 44,
          height: 44,
          color: Colors.white12,
          child: const Icon(
            Icons.music_note,
            color: Colors.white38,
            size: 24,
          ),
        ),
      );
    } else {
      // 本地文件
      return SizedBox(
        width: 44,
        height: 44,
        child: Image.file(
          File(imageUrl),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            width: 44,
            height: 44,
            color: Colors.white12,
            child: const Icon(
              Icons.music_note,
              color: Colors.white38,
              size: 24,
            ),
          ),
        ),
      );
    }
  }
}

/// 睡眠定时器对话框（移动端版本）
class MobileSleepTimerDialog extends StatefulWidget {
  const MobileSleepTimerDialog({super.key});

  @override
  State<MobileSleepTimerDialog> createState() => _MobileSleepTimerDialogState();
}

class _MobileSleepTimerDialogState extends State<MobileSleepTimerDialog> {
  int _selectedTabIndex = 0; // 0: 时长, 1: 时间
  int _selectedDuration = 30; // 默认30分钟

  // 预设时长选项（分钟）
  final List<int> _durationOptions = [15, 30, 45, 60, 90, 120];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final timer = SleepTimerService();

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('睡眠定时器'),
          if (timer.isActive)
            TextButton.icon(
              onPressed: () {
                timer.cancel();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('定时器已取消')),
                );
              },
              icon: const Icon(Icons.cancel),
              label: const Text('取消定时'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 当前定时器状态
            if (timer.isActive)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      color: colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '定时器运行中',
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          AnimatedBuilder(
                            animation: timer,
                            builder: (context, child) {
                              return Text(
                                '剩余时间: ${timer.remainingTimeString}',
                                style: TextStyle(
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    if (timer.isActive)
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () {
                          timer.extend(15);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已延长15分钟')),
                          );
                        },
                        tooltip: '延长15分钟',
                        color: colorScheme.onPrimaryContainer,
                      ),
                  ],
                ),
              ),

            // 标签选择器
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('播放时长'),
                  icon: Icon(Icons.timer_outlined),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('指定时间'),
                  icon: Icon(Icons.schedule),
                ),
              ],
              selected: {_selectedTabIndex},
              onSelectionChanged: (Set<int> selected) {
                setState(() {
                  _selectedTabIndex = selected.first;
                });
              },
            ),

            const SizedBox(height: 24),

            // 内容区域
            if (_selectedTabIndex == 0) _buildDurationTab(colorScheme),
            if (_selectedTabIndex == 1) _buildTimeTab(context, colorScheme),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }

  /// 时长选择标签页
  Widget _buildDurationTab(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选择播放时长',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _durationOptions.map((duration) {
            final isSelected = duration == _selectedDuration;
            return FilterChip(
              label: Text('$duration分钟'),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedDuration = duration;
                  });
                  SleepTimerService().setTimerByDuration(duration);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('定时器已设置: $duration分钟后停止播放'),
                    ),
                  );
                }
              },
              showCheckmark: false,
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 时间选择标签页
  Widget _buildTimeTab(BuildContext context, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选择停止时间',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () async {
              final TimeOfDay? selectedTime = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
                builder: (context, child) {
                  return MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      alwaysUse24HourFormat: true,
                    ),
                    child: child!,
                  );
                },
              );

              if (selectedTime != null) {
                SleepTimerService().setTimerByTime(selectedTime);
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '定时器已设置: ${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')} 停止播放',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.access_time),
            label: const Text('选择时间'),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '音乐将在指定时间自动停止播放',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
