import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/playback/playback_controller.dart';
import '../../domain/models/history.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';
import '../../infrastructure/services/history_service.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../player/cyrene_track_tile.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.playback});

  final PlaybackController playback;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<HistoryEntry> _entries = const [];
  OverallStats? _stats;
  String? _errorMessage;
  var _isLoading = true;
  var _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _requestId++;
    super.dispose();
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final results = await Future.wait<Object>([
        HistoryService.instance.getHistory(),
        HistoryService.instance.getStats(),
      ]);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _entries = results[0] as List<HistoryEntry>;
        _stats = results[1] as OverallStats;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _errorMessage = '无法读取播放历史，请稍后重试。';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => CyrenePage(
    title: '播放历史',
    actions: [
      MiuixIconButton(
        key: const Key('refresh-history-button'),
        enabled: !_isLoading,
        onPressed: _load,
        child: MiuixIcon(
          vector: MiuixIcons.extended.byName('refresh')!,
          size: 20,
        ),
      ),
      const SizedBox(width: 8),
    ],
    bodyBuilder: (context, topPadding) => _buildBody(topPadding),
  );

  Widget _buildBody(EdgeInsets topPadding) {
    if (_isLoading) {
      return const Center(child: MiuixCircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return CyreneEmptyState(
        icon: Icons.error_outline,
        title: '历史记录加载失败',
        description: _errorMessage!,
        action: MiuixButton(
          onPressed: _load,
          child: MiuixText(
            '重试',
            style: MiuixTheme.of(context).textStyles.button,
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return CyrenePullToRefresh(
        onRefresh: _load,
        contentPadding: EdgeInsets.only(top: topPadding.top),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          padding: topPadding,
          children: const [
            SizedBox(height: 120),
            CyreneEmptyState(
              icon: Icons.history,
              title: '还没有播放记录',
              description: '播放过的歌曲会按最近时间出现在这里。',
            ),
          ],
        ),
      );
    }

    final tracks = _entries.map(_toTrack).toList(growable: false);
    return CyrenePullToRefresh(
      onRefresh: _load,
      contentPadding: EdgeInsets.only(top: topPadding.top),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        padding: topPadding + const EdgeInsets.fromLTRB(16, 20, 16, 40),
        itemCount: _entries.length + 2,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _StatsRow(stats: _stats!);
          }
          if (index == 1) {
            return const Padding(
              padding: EdgeInsets.only(top: 12),
              child: CyreneSectionTitle(
                title: '最近播放',
                description: '点击歌曲将以这份历史记录作为播放队列。',
              ),
            );
          }
          final theme = MiuixTheme.of(context);
          final entryIndex = index - 2;
          final entry = _entries[entryIndex];
          final track = tracks[entryIndex];
          return CyreneTrackTile(
            track: track,
            onPlay: () => widget.playback.playTrack(track, queue: tracks),
            trailing: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '${entry.playCount} 次',
                style: theme.textStyles.body2.copyWith(
                  color: theme.colors.onSurfaceVariantSummary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Track _toTrack(HistoryEntry entry) => Track(
    id: entry.id,
    name: entry.name,
    artists: entry.artists,
    album: entry.album,
    picUrl: entry.picUrl,
    source: MusicSource.fromWireName(entry.source),
  );
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});

  final OverallStats stats;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _StatCard(
          icon: Icons.headphones,
          label: '聆听时长',
          value: _formatDuration(stats.totalListeningTime),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _StatCard(
          icon: Icons.play_arrow_rounded,
          label: '播放次数',
          value: '${stats.totalPlayCount} 次',
        ),
      ),
    ],
  );

  static String _formatDuration(int seconds) {
    if (seconds < 60) return '$seconds 秒';
    if (seconds < 3600) return '${seconds ~/ 60} 分钟';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return minutes == 0 ? '$hours 小时' : '$hours 小时 $minutes 分';
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return MiuixCard(
      insideMargin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CyreneIconBox(icon: icon),
            const SizedBox(height: 12),
            Text(
              label,
              style: theme.textStyles.body2.copyWith(
                color: theme.colors.onSurfaceVariantSummary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textStyles.title4.copyWith(
                color: theme.colors.onSurfaceContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
