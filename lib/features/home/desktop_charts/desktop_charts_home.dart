import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../../domain/models/discovery.dart';
import '../../../domain/models/track.dart';
import '../../../infrastructure/services/discovery_service.dart';
import '../for_you/for_you_artwork.dart';
import '../for_you/for_you_palette.dart';
import '../for_you/for_you_widgets.dart' show ForYouEndNote;
import '../for_you/spotify_home_widgets.dart' show spotifyKindLabel;

part 'chart_explorer.dart';
part 'charts_hero.dart';
part 'charts_picks.dart';
part 'charts_widgets.dart';
part 'spotify_sections.dart';

typedef DesktopChartEntry = ({Toplist toplist, List<Track> tracks});

/// 个性化分区的桌面展示数据：曲目已由首页转换成 [Track]，这里不再解析。
typedef DesktopSpotifySection = ({
  String id,
  String title,
  String description,
  SpotifyPersonalizedKind kind,
  List<SpotifyPlaylistPreview> items,
  List<Track> tracks,
});

typedef _PlayTracks = void Function(Track track, List<Track> queue);

/// 桌面首页「榜单」页签的全部内容。数据、播放和二级页导航仍由 DesktopHomePage 管理。
///
/// 与移动端同一套暖纸色手帐（[ForYouPalette]），但按宽屏重新排版：
/// 随心畅听横幅 + 票根式正在播放 → 左栏榜单 / 右栏 Top 10 的排行榜 →
/// 跨榜抽歌的封面架 → 按内容类型换版式的个性化分区。
///
/// 不订阅播放进度，不请求网络数据；仅随曲目 / 播放状态的结构性通知更新。
/// **横向内容一律不用惰性 ListView / PageView**（Windows 无障碍桥与 Tooltip
/// 同时存在会闪退，见 DesktopHomePage 类文档），放不下的一排改为翻页。
class DesktopChartsHome extends StatefulWidget {
  const DesktopChartsHome({
    super.key,
    required this.entries,
    required this.onPlay,
    required this.onOpenChart,
    required this.onTogglePlayback,
    required this.onOpenPlayer,
    required this.onOpenHistory,
    required this.onRetry,
    this.sections = const [],
    this.onOpenItem,
    this.currentTrack,
    this.isPlaying = false,
    this.recentTracks = const [],
    this.loading = false,
    this.errorMessage,
  });

  final List<DesktopChartEntry> entries;
  final List<DesktopSpotifySection> sections;
  final void Function(Track track, List<Track> queue) onPlay;
  final ValueChanged<Toplist> onOpenChart;
  final ValueChanged<SpotifyPlaylistPreview>? onOpenItem;
  final VoidCallback onTogglePlayback;
  final VoidCallback onOpenPlayer;
  final VoidCallback onOpenHistory;
  final VoidCallback onRetry;
  final Track? currentTrack;
  final bool isPlaying;
  final List<Track> recentTracks;
  final bool loading;
  final String? errorMessage;

  @override
  State<DesktopChartsHome> createState() => _DesktopChartsHomeState();
}

class _DesktopChartsHomeState extends State<DesktopChartsHome> {
  /// 「今天就听这些」的随机种子；「换一批」只是换种子。
  var _pickSeed = 0;
  List<DesktopChartEntry>? _picksSource;
  var _picksSeed = -1;
  List<Track> _picks = const [];

  List<DesktopChartEntry>? _mixSource;
  List<Track> _mix = const [];

  final _explorerKey = GlobalKey();

  /// 交错取各榜歌曲，同平台同 ID 只出现一次。完整结果用于随机播放。
  List<Track> _mixTracks() {
    if (identical(_mixSource, widget.entries)) return _mix;
    final tracks = <Track>[];
    final seen = <String>{};
    final length = widget.entries.fold<int>(
      0,
      (value, entry) => math.max(value, entry.tracks.length),
    );
    for (var i = 0; i < length; i++) {
      for (final entry in widget.entries) {
        if (i >= entry.tracks.length) continue;
        final track = entry.tracks[i];
        if (track.id.isNotEmpty && seen.add(track.key)) tracks.add(track);
      }
    }
    _mixSource = widget.entries;
    return _mix = List.unmodifiable(tracks);
  }

  /// 从各榜单轮流抽歌：跳过前三名（排行榜里已经露出），打乱后一榜抽一首，
  /// 去重后最多 16 首（宽屏两排封面架的上限）。
  List<Track> _chartPicks() {
    if (_picksSeed == _pickSeed && identical(_picksSource, widget.entries)) {
      return _picks;
    }
    final random = math.Random(_pickSeed * 7919 + widget.entries.length);
    final pools = [
      for (final entry in widget.entries)
        (entry.tracks.skip(3).toList()..shuffle(random)),
    ];
    final seen = <String>{};
    final picks = <Track>[];
    for (var round = 0; picks.length < 16; round++) {
      if (pools.every((pool) => round >= pool.length)) break;
      for (final pool in pools) {
        if (round < pool.length && seen.add(pool[round].key)) {
          picks.add(pool[round]);
          if (picks.length == 16) break;
        }
      }
    }
    _picksSource = widget.entries;
    _picksSeed = _pickSeed;
    return _picks = List.unmodifiable(picks);
  }

  void _playOrToggle(Track track, List<Track> queue) {
    if (track.key == widget.currentTrack?.key) {
      widget.onTogglePlayback();
    } else {
      widget.onPlay(track, queue);
    }
  }

  void _shuffleAll(List<Track> mix) {
    final queue = List<Track>.of(mix)..shuffle();
    widget.onPlay(queue.first, queue);
  }

  void _scrollToCharts() {
    final context = _explorerKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final mix = _mixTracks();
    final picks = _chartPicks();
    final playable = entries.where((entry) => entry.tracks.isNotEmpty);
    final lead = playable.firstOrNull;

    final children = <Widget>[];
    if (entries.isEmpty) {
      children.add(
        _ChartsUnavailable(
          loading: widget.loading,
          message: widget.errorMessage,
          onRetry: widget.onRetry,
        ),
      );
    } else {
      children
        ..add(
          _ListeningRow(
            hero: (height) => _MixHero(
              height: height,
              // Spotify 榜单封面千篇一律，扇面用各榜榜首的专辑封面更有辨识度。
              covers: [
                for (final entry in playable.take(4)) entry.tracks.first.picUrl,
              ],
              chartCount: entries.length,
              trackCount: mix.length,
              leadTrack: lead?.tracks.first,
              onShuffle: mix.isEmpty ? null : () => _shuffleAll(mix),
              onBrowse: _scrollToCharts,
            ),
            ticket: (height) => _ListeningTicket(
              height: height,
              currentTrack: widget.currentTrack,
              isPlaying: widget.isPlaying,
              recentTracks: widget.recentTracks,
              mix: mix,
              onPlay: widget.onPlay,
              onToggle: widget.onTogglePlayback,
              onOpenPlayer: widget.onOpenPlayer,
              onOpenHistory: widget.onOpenHistory,
            ),
          ),
        )
        ..add(
          _Heading(
            key: _explorerKey,
            title: '排行榜',
            subtitle: '全球与各地区的播放热度 · ${entries.length} 张榜单',
          ),
        )
        ..add(
          _ChartExplorer(
            entries: entries,
            currentTrack: widget.currentTrack,
            isPlaying: widget.isPlaying,
            onPlay: _playOrToggle,
            onPlayAll: (entry) {
              if (entry.tracks.isEmpty) return;
              widget.onPlay(entry.tracks.first, entry.tracks);
            },
            onOpen: widget.onOpenChart,
          ),
        );
      if (picks.isNotEmpty) {
        children
          ..add(
            _Heading(
              title: '今天就听这些',
              subtitle: '从各个榜单里挑出来的歌，前三名先让一让',
              trailing: _GhostButton(
                label: '换一批',
                icon: Icons.refresh_rounded,
                onPressed: () => setState(() => _pickSeed++),
              ),
            ),
          )
          ..add(
            _PickShelf(
              key: ValueKey('desktop-picks-$_pickSeed'),
              tracks: picks,
              currentTrack: widget.currentTrack,
              isPlaying: widget.isPlaying,
              onPlay: (track) => _playOrToggle(track, picks),
            ),
          );
      }
    }

    // 艺人与专辑有专属版式，其余分区按出现顺序在四种版式间轮换。
    var rotating = 0;
    final onOpenItem = widget.onOpenItem;
    for (final section in widget.sections) {
      final isRotating =
          section.kind != SpotifyPersonalizedKind.track &&
          section.kind != SpotifyPersonalizedKind.artist &&
          section.kind != SpotifyPersonalizedKind.album;
      if (section.items.isEmpty && section.tracks.isEmpty) continue;
      if (section.kind != SpotifyPersonalizedKind.track && onOpenItem == null) {
        continue;
      }
      children.add(
        _SpotifySectionView(
          key: ValueKey('desktop-section-${section.id}'),
          section: section,
          rotation: rotating,
          currentTrack: widget.currentTrack,
          isPlaying: widget.isPlaying,
          onPlay: _playOrToggle,
          onPlayAll: widget.onPlay,
          onOpen: onOpenItem ?? (_) {},
        ),
      );
      if (isRotating) rotating++;
    }
    children.add(const ForYouEndNote());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
