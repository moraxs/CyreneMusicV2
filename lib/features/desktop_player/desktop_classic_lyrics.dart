import 'package:flutter/material.dart';

import '../../../application/playback/playback_controller.dart';
import '../../../domain/models/music_source.dart';
import '../../../domain/models/track.dart';
import '../player/mobile/compat/lyric_line.dart';
import '../player/mobile/compat/lyric_parser.dart';
import '../player/mobile/components/mobile_player_fluid_cloud_lyric.dart';

/// 桌面歌词覆盖层的「经典」样式：复用经典播放器的流体云歌词组件。
///
/// 与 [SuperCyreneClassicLyrics]（「默认」主题，逐行逐字 + article 布局）区分：
/// 本组件把经典播放器的 [MobilePlayerFluidCloudLyric] 搬到桌面覆盖层，视觉上
/// 是流体云弹性布局（较小字号、波浪延迟、弹性间距），不带封面/背景/控制区外壳。
///
/// 子窗口是独立引擎、无 [PlayerService] 单例，因此向组件注入：
/// - [PlaybackController.positionListenable] 作为播放时钟；
/// - seek 走 [DesktopPlayerCommands] 回传主窗口（经典播放器拖拽 seek 在桌面
///   覆盖层不开放，但组件需要该回调占位）。
///
/// 歌词解析与 [SuperCyreneClassicLyrics._adaptTrack] 同源：按 track.source 分派
/// 到对应的 [LyricParser] 解析器，译文 / 逐字数据一并传入。
class DesktopClassicLyrics extends StatefulWidget {
  const DesktopClassicLyrics({
    super.key,
    required this.playback,
    required this.track,
  });

  final PlaybackController playback;
  final Track track;

  @override
  State<DesktopClassicLyrics> createState() => _DesktopClassicLyricsState();
}

class _DesktopClassicLyricsState extends State<DesktopClassicLyrics> {
  List<LyricLine> _lyrics = const [];
  int _currentIndex = -1;

  @override
  void initState() {
    super.initState();
    _adaptTrack();
    widget.playback.positionListenable.addListener(_onPosition);
  }

  @override
  void didUpdateWidget(covariant DesktopClassicLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playback != widget.playback) {
      oldWidget.playback.positionListenable.removeListener(_onPosition);
      widget.playback.positionListenable.addListener(_onPosition);
    }
    if (_signature(oldWidget.track) != _signature(widget.track)) {
      _adaptTrack();
    }
  }

  @override
  void dispose() {
    widget.playback.positionListenable.removeListener(_onPosition);
    super.dispose();
  }

  String _signature(Track track) =>
      '${track.key}|${track.lyric?.length}|${track.yrc?.length}'
      '|${track.tlyric?.length}|${track.ytlrc?.length}';

  void _adaptTrack() {
    final lyric = widget.track.lyric;
    _lyrics = (lyric == null || lyric.isEmpty)
        ? const <LyricLine>[]
        : switch (widget.track.source) {
            MusicSource.qq => LyricParser.parseQQLyric(
                lyric,
                translation: widget.track.tlyric,
                qrcLyric: widget.track.yrc,
                qrcTranslation: widget.track.ytlrc,
              ),
            MusicSource.kugou => LyricParser.parseKugouLyric(
                lyric,
                translation: widget.track.tlyric,
              ),
            _ => LyricParser.parseNeteaseLyric(
                lyric,
                translation: widget.track.tlyric,
                yrcLyric: widget.track.yrc,
                yrcTranslation: widget.track.ytlrc,
              ),
          };
    _currentIndex = -1;
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPosition());
  }

  void _onPosition() {
    if (!mounted || _lyrics.isEmpty) return;
    final pos = widget.playback.positionListenable.value;
    final index = LyricParser.findCurrentLineIndex(_lyrics, pos);
    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_lyrics.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .3),
            fontSize: 14,
            letterSpacing: 2.8,
          ),
        ),
      );
    }
    return MobilePlayerFluidCloudLyric(
      lyrics: _lyrics,
      currentLyricIndex: _currentIndex,
      showTranslation: true,
      positionListenable: widget.playback.positionListenable,
      // 桌面覆盖层不开放拖拽 seek；占位空回调即可（组件仅在拖拽定位时调用）。
      onSeek: (_) {},
    );
  }
}
