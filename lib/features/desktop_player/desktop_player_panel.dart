import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_svg/flutter_svg.dart';

import '../../application/playback/playback_controller.dart';
import '../../application/stores/fullscreen_settings_store.dart';
import '../../domain/models/media_url.dart';
import '../../domain/models/track.dart';
import '../../domain/playback/repeat_mode.dart';
import '../player/super_cyrene/super_cyrene_song_gallery.dart';
import 'desktop_player_bridge.dart';
import 'desktop_player_playback.dart';

/// 桌面歌词的控制面板（左上角）。
///
/// 与 SuperCyrene 左下角控制面板（super_cyrene_control_panel.dart）保持一致：
/// 封面 → 歌名/歌手·专辑 → 歌词样式 → 进度条 → 传输键 → 底部行（队列 / 收藏 /
/// 循环 … 音量）。「歌曲列表」同样打开展览馆（[DesktopSongGallery]）。
///
/// 唯一与 SuperCyrene 不同的是「收藏」：覆盖层被钉在 z-order 底层，弹「选择
/// 歌单」模态会被任何窗口盖住，因此语义固定为加入/移出默认歌单。
///
/// 关键约束：桌面覆盖层默认整窗鼠标穿透（见 workerw_handler.cpp 与
/// desktop_lyrics_window.cpp 的 WM_NCHITTEST），面板必须把自己的屏幕矩形经
/// [DesktopPlayerCommands.setHitRects] 上报，否则完全点不动。面板的高度随
/// 展开状态变化，**不能**用写死的常量推算——这里改用 GlobalKey 读实际渲染
/// 尺寸后再上报（见 [_syncHitRects]）；展览馆打开时则整屏可交互。
class DesktopPlayerPanel extends StatefulWidget {
  const DesktopPlayerPanel({
    super.key,
    required this.playback,
    required this.source,
    this.galleryOpen,
    this.editMode,
  });

  /// 显示层控制器（进度 / 播放态 / 当前曲目）。所有写操作都要回传主窗口。
  final PlaybackController playback;

  /// 跨窗口同步来的附加状态（收藏态、队列）。
  final DesktopPlayerPlayback source;

  /// 展览馆开合状态的对外镜像，由 [DesktopPlayerView] 持有。
  ///
  /// 展览馆的背景是 DWM 壁纸亚克力——那是**原生窗口效果，位于整个 Flutter
  /// 图层之下**，Flutter 画的歌词必然浮在它上面，看起来就是「歌词穿透了模糊
  /// 层」。歌词是面板的兄弟节点，管不到，因此把开合状态抬到共同父节点，由
  /// 视图在展览馆开启时把歌词层 Offstage 掉。
  final ValueNotifier<bool>? galleryOpen;

  /// 歌词编辑模式的对外镜像，同样由视图持有：视图据此挂上拖拽层与取景框。
  final ValueNotifier<bool>? editMode;

  @override
  State<DesktopPlayerPanel> createState() => _DesktopPlayerPanelState();
}

class _DesktopPlayerPanelState extends State<DesktopPlayerPanel> {
  static const double _launcherSize = 48;
  static const double _panelWidth = 256;
  static const double _margin = 24;

  final GlobalKey _bodyKey = GlobalKey();

  bool _open = false;
  bool _galleryOpen = false;

  /// 歌词编辑模式。为真时整屏可交互（要能拖歌词），面板内容换成变换控件。
  bool _editMode = false;

  /// 原生亚克力不可用（Win10 1809 以下）时置位：展览馆改画一层暗蒙版，
  /// 至少保证卡片文字在亮色壁纸上读得出来。
  bool _acrylicFallback = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncHitRects();
      // 新面板必然是展览馆关闭的状态，把镜像同步下去。放在这里而不是
      // dispose：面板销毁时视图往往也在销毁，那时 notifier 已被 dispose，
      // 再写会抛「used after dispose」。
      if (mounted) {
        widget.galleryOpen?.value = false;
        widget.editMode?.value = false;
      }
    });
  }

  @override
  void dispose() {
    // 面板消失后恢复整窗穿透，否则左上角会残留一块点不透的死区。
    DesktopPlayerCommands.setHitRects(const []);
    // 展览馆开着时被销毁的话，亚克力会留在窗口上把整个桌面糊住。
    if (_galleryOpen) {
      DesktopPlayerCommands.setWallpaperAcrylic(enabled: false);
    }
    super.dispose();
  }

  /// 把当前可交互区域上报给原生命中测试。
  ///
  /// 报的是**窗口客户区内**的物理像素坐标；原生侧再叠加窗口原点换算成屏幕
  /// 坐标（见 desktop_lyrics_window.cpp 的 PointInHitRects）。这样 Dart 侧不
  /// 需要知道覆盖层被摆在屏幕的哪个位置。
  ///
  /// 尺寸从 [_bodyKey] 的 RenderBox 实测，不用常量推算：面板高度会随歌词样式
  /// 展开、曲目信息换行变化，写死的常量必然对不上，表现为面板下半截点不动
  /// （矩形太小）或歌词区域莫名挡住鼠标（矩形太大）。
  ///
  /// 展览馆打开，或歌词编辑模式时，改报整个客户区：两者都需要全屏可交互
  /// （展览馆是拖拽卡片场，编辑模式是要拖歌词），只报面板那一小块的话
  /// 拖不动。
  void _syncHitRects() {
    if (!mounted) return;
    final dpr = View.of(context).devicePixelRatio;
    if (_galleryOpen || _editMode) {
      final size = MediaQuery.sizeOf(context);
      DesktopPlayerCommands.setHitRects([
        0,
        0,
        (size.width * dpr).ceil(),
        (size.height * dpr).ceil(),
      ]);
      return;
    }
    final box = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;
    DesktopPlayerCommands.setHitRects([
      (origin.dx * dpr).floor(),
      (origin.dy * dpr).floor(),
      ((origin.dx + size.width) * dpr).ceil(),
      ((origin.dy + size.height) * dpr).ceil(),
    ]);
  }

  /// 布局可能变化时重新上报。展开/收起、展览馆开合、歌词样式切换后都要调。
  void _scheduleHitRectSync() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncHitRects());

  void _toggle() {
    setState(() => _open = !_open);
    _scheduleHitRectSync();
  }

  void _openGallery() {
    setState(() => _galleryOpen = true);
    widget.galleryOpen?.value = true;
    _scheduleHitRectSync();
    // 展览馆的背景不画封面，改由 DWM 实时模糊真实桌面壁纸（Flutter 侧
    // 模糊不到透明窗口背后的东西）。失败（Win10 1809 以下无此 API）时
    // 回退到不模糊的暗色蒙版。
    DesktopPlayerCommands.setWallpaperAcrylic(enabled: true).then((ok) {
      if (mounted && !ok) setState(() => _acrylicFallback = true);
    });
  }

  void _closeGallery() {
    if (!mounted) return;
    setState(() {
      _galleryOpen = false;
      _acrylicFallback = false;
    });
    widget.galleryOpen?.value = false;
    _scheduleHitRectSync();
    // 必须还原：亚克力会给整个覆盖层铺一层不透明底，不关掉的话退出展览馆后
    // 整个桌面都会被糊住。
    DesktopPlayerCommands.setWallpaperAcrylic(enabled: false);
  }

  void _enterEditMode() {
    if (_editMode) return;
    setState(() => _editMode = true);
    widget.editMode?.value = true;
    _scheduleHitRectSync();
  }

  /// 退出编辑模式。公开给面板上的「完成」按钮。
  void _exitEditMode() {
    if (!_editMode) return;
    setState(() => _editMode = false);
    widget.editMode?.value = false;
    _scheduleHitRectSync();
  }

  @override
  Widget build(BuildContext context) {
    // 展览馆是全屏层，盖在歌词与面板之上。所有写操作回传主窗口执行——本地
    // controller 只是显示层，直接调它不会发声（见 DesktopPlayerPlayback）。
    if (_galleryOpen) {
      return Positioned.fill(
        child: SuperCyreneSongGallery(
          playback: widget.playback,
          // 背景交给 DWM 的壁纸亚克力（见 _openGallery）：这里画任何底色都会
          // 把模糊后的壁纸糊死。亚克力不可用时退化为一层暗蒙版。
          backdrop: _acrylicFallback
              ? const ColoredBox(color: Color(0x99101014))
              : const SizedBox.shrink(),
          onClose: _closeGallery,
          onPlayTrack: (track) =>
              DesktopPlayerCommands.send('playTrack', track.key),
          onRemoveTrack: (track) =>
              DesktopPlayerCommands.send('removeFromQueue', track.key),
          onClearQueue: () async {
            await DesktopPlayerCommands.send('clearQueue');
            _closeGallery();
          },
        ),
      );
    }
    // 面板全展开约 620px 高，在 768p 这类屏幕上会顶出屏幕。用屏幕高度封顶。
    final maxHeight = MediaQuery.sizeOf(context).height - _margin * 2;
    return Positioned(
      left: _margin,
      top: _margin,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            key: _bodyKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Launcher(open: _open, onTap: _toggle),
              if (_open) ...[
                const SizedBox(height: 8),
                _Panel(
                  playback: widget.playback,
                  source: widget.source,
                  editMode: _editMode,
                  onEnterEditMode: _enterEditMode,
                  onExitEditMode: _exitEditMode,
                  onOpenGallery: _openGallery,
                  onClose: _toggle,
                  onLayoutChanged: _scheduleHitRectSync,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Launcher extends StatefulWidget {
  const _Launcher({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovering || widget.open;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: _DesktopPlayerPanelState._launcherSize,
          height: _DesktopPlayerPanelState._launcherSize,
          decoration: BoxDecoration(
            color: widget.open
                ? Colors.white.withValues(alpha: .12)
                : active
                ? Colors.white.withValues(alpha: .08)
                : Colors.black.withValues(alpha: .18),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: active ? .30 : .15),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x59000000),
                blurRadius: 40,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Icon(
                widget.open ? Icons.close_rounded : Icons.music_note_rounded,
                size: 20,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.playback,
    required this.source,
    required this.editMode,
    required this.onEnterEditMode,
    required this.onExitEditMode,
    required this.onOpenGallery,
    required this.onClose,
    required this.onLayoutChanged,
  });

  final PlaybackController playback;
  final DesktopPlayerPlayback source;
  final bool editMode;
  final VoidCallback onEnterEditMode;
  final VoidCallback onExitEditMode;
  final VoidCallback onOpenGallery;
  final VoidCallback onClose;
  final VoidCallback onLayoutChanged;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
      child: Container(
        width: _DesktopPlayerPanelState._panelWidth,
        decoration: BoxDecoration(
          // 底色比 SuperCyrene 稍重：那边背后是自家的 AMLL 背景，这里背后是
          // 用户任意壁纸，太透会让白色文字读不出来。
          color: Colors.black.withValues(alpha: .34),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .10)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x73000000),
              blurRadius: 70,
              offset: Offset(0, 20),
            ),
          ],
        ),
        child: AnimatedBuilder(
          animation: playback,
          builder: (context, _) {
            // 编辑模式下整块换成变换控件，不重复画封面/进度/传输键。
            if (editMode) {
              return _TransformEditor(onExit: onExitEditMode);
            }
            final track = playback.state.currentTrack;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Artwork(track: track, onClose: onClose),
                _SongInfo(track: track),
                _LyricsStyleRow(onChanged: onLayoutChanged),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: _PanelProgress(playback: playback),
                ),
                _Transport(playback: playback),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: .05),
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          _SmallButton(
                            icon: Icons.queue_music_rounded,
                            onTap: onOpenGallery,
                          ),
                          const SizedBox(width: 4),
                          _FavoriteButton(source: source),
                          const SizedBox(width: 4),
                          _RepeatButton(playback: playback),
                        ],
                      ),
                      Row(
                        children: [
                          // 「默认」样式不参与变换，没有编辑按钮。
                          if (_lyricStyle != 'default') ...[
                            _SmallButton(
                              icon: Icons.open_with_rounded,
                              onTap: onEnterEditMode,
                            ),
                            const SizedBox(width: 6),
                          ],
                          _VolumeControl(playback: playback),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  /// 当前歌词样式（与 desktop_player_view 的 switch 判定一致）。
  String get _lyricStyle {
    final settings = FullscreenSettingsStore.instance;
    return settings.superCyrenePlayerEnabled
        ? settings.superCyreneLyricsTheme
        : 'classic';
  }
}

/// 歌词变换编辑面板：缩放 + X/Y/Z 三轴旋转滑块 + 重置/完成。
///
/// 位置靠直接拖拽歌词（见 desktop_player_view 的拖拽层），这里不提供位置滑块。
class _TransformEditor extends StatefulWidget {
  const _TransformEditor({required this.onExit});

  final VoidCallback onExit;

  @override
  State<_TransformEditor> createState() => _TransformEditorState();
}

class _TransformEditorState extends State<_TransformEditor> {
  @override
  Widget build(BuildContext context) {
    final settings = FullscreenSettingsStore.instance;
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: .05)),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '歌词编辑',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '拖动歌词调整位置，下方滑块调整大小与旋转',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .45),
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 12),
              _TransformSlider(
                label: '缩放',
                value: settings.desktopLyricScale,
                min: FullscreenSettingsStore.minDesktopLyricScale,
                max: FullscreenSettingsStore.maxDesktopLyricScale,
                display: (v) => '${v.toStringAsFixed(2)}x',
                onChanged: (v) => settings.setDesktopLyricScale(v),
              ),
              const SizedBox(height: 8),
              _TransformSlider(
                label: 'X 轴',
                value: settings.desktopLyricRotX,
                min: -FullscreenSettingsStore.maxDesktopLyricRotation,
                max: FullscreenSettingsStore.maxDesktopLyricRotation,
                display: (v) => '${(v * 180 / math.pi).round()}°',
                onChanged: (v) => settings.setDesktopLyricRotX(v),
              ),
              const SizedBox(height: 8),
              _TransformSlider(
                label: 'Y 轴',
                value: settings.desktopLyricRotY,
                min: -FullscreenSettingsStore.maxDesktopLyricRotation,
                max: FullscreenSettingsStore.maxDesktopLyricRotation,
                display: (v) => '${(v * 180 / math.pi).round()}°',
                onChanged: (v) => settings.setDesktopLyricRotY(v),
              ),
              const SizedBox(height: 8),
              _TransformSlider(
                label: 'Z 轴',
                value: settings.desktopLyricRotZ,
                min: -FullscreenSettingsStore.maxDesktopLyricRotation,
                max: FullscreenSettingsStore.maxDesktopLyricRotation,
                display: (v) => '${(v * 180 / math.pi).round()}°',
                onChanged: (v) => settings.setDesktopLyricRotZ(v),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _SmallButton(
                    icon: Icons.restart_alt_rounded,
                    onTap: settings.resetDesktopLyricTransform,
                  ),
                  _RoundChipButton(
                    label: '完成',
                    onTap: widget.onExit,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 编辑面板里的一行滑块：标签在左，滑块在中间，实时数值在右。
class _TransformSlider extends StatelessWidget {
  const _TransformSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double) display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .70),
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                activeTrackColor: Colors.white.withValues(alpha: .60),
                inactiveTrackColor: Colors.white.withValues(alpha: .15),
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              display(value),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .70),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      );
}

/// 编辑面板的「完成」胶囊按钮。
class _RoundChipButton extends StatelessWidget {
  const _RoundChipButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .92),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
}

/// 封面区（256×256，与 SuperCyrene 一致）。
///
/// 覆盖层是独立引擎、没有 PlayerService 单例，因此不能用
/// `PlayerService().currentCoverImageProvider`，直接按项目约定用
/// CachedNetworkImage + 网易 UA 头（见 media_url.dart 的 imageHeaders）。
class _Artwork extends StatelessWidget {
  const _Artwork({required this.track, required this.onClose});

  final Track? track;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    const size = _DesktopPlayerPanelState._panelWidth;
    final url = track?.picUrl;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: Colors.white.withValues(alpha: .05),
            child: url == null || url.isEmpty
                ? Icon(
                    Icons.music_note_rounded,
                    size: 48,
                    color: Colors.white.withValues(alpha: .15),
                  )
                : CachedNetworkImage(
                    imageUrl: url,
                    httpHeaders: imageHeaders(url),
                    fit: BoxFit.cover,
                    memCacheWidth: coverDecodeWidth(
                      size,
                      MediaQuery.devicePixelRatioOf(context),
                    ),
                    errorWidget: (_, _, _) => Icon(
                      Icons.music_note_rounded,
                      size: 48,
                      color: Colors.white.withValues(alpha: .15),
                    ),
                  ),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 64,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xB3000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: _RoundHoverButton(
              size: 28,
              icon: Icons.close_rounded,
              iconSize: 14,
              onTap: onClose,
            ),
          ),
        ],
      ),
    );
  }
}

class _SongInfo extends StatelessWidget {
  const _SongInfo({required this.track});

  final Track? track;

  @override
  Widget build(BuildContext context) {
    final album = track?.album ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            track?.name ?? '未在播放',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: -.15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            track == null
                ? '选择一首歌曲开始播放'
                : '${track!.artists}${album.isEmpty ? '' : ' · $album'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .40),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// 歌词样式选择。
///
/// 与 SuperCyrene 的「歌词」下拉同构，但多一档「经典」：桌面歌词只是一个歌词
/// 渲染层，没有「哪个播放器」的概念，用户看到的就是四种样式。选择写回
/// FullscreenSettingsStore，与全屏播放器共用同一份偏好——superCyrene 关 →
/// 经典，开 → 取它的歌词主题。
///
/// **不用 PopupMenuButton**：它的菜单是挂在 Overlay 上的独立浮层，会渲染到面板
/// 矩形之外，而覆盖层只有上报过的矩形才接收鼠标——菜单会画出来但点不动。改为
/// 在面板内就地向下展开选项列表，整块仍在同一个上报矩形内。
class _LyricsStyleRow extends StatefulWidget {
  const _LyricsStyleRow({required this.onChanged});

  /// 展开/收起后面板高度变化，需要重报命中区域。
  final VoidCallback onChanged;

  @override
  State<_LyricsStyleRow> createState() => _LyricsStyleRowState();
}

class _LyricsStyleRowState extends State<_LyricsStyleRow> {
  static const _options = <({String id, String label})>[
    (id: 'classic', label: '经典'),
    (id: 'default', label: '默认'),
    (id: 'chat', label: '对话'),
    (id: 'pixel', label: '像素'),
    (id: 'sonnet', label: '构象'),
  ];

  bool _expanded = false;

  void _select(String id) {
    final settings = FullscreenSettingsStore.instance;
    if (id == 'classic') {
      settings.setSuperCyrenePlayerEnabled(false);
    } else {
      settings.setSuperCyrenePlayerEnabled(true);
      settings.setSuperCyreneLyricsTheme(id);
    }
    setState(() => _expanded = false);
    widget.onChanged();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final settings = FullscreenSettingsStore.instance;
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        final current = settings.superCyrenePlayerEnabled
            ? settings.superCyreneLyricsTheme
            : 'classic';
        final label = _options
            .firstWhere(
              (option) => option.id == current,
              orElse: () => _options[1],
            )
            .label;
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          padding: const EdgeInsets.only(left: 8, right: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .035),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: .08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 34,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '歌词',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .35),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.4,
                      ),
                    ),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: _toggle,
                        child: Container(
                          width: 112,
                          height: 28,
                          padding: const EdgeInsets.symmetric(horizontal: 9),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .20),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .10),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                label,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .80),
                                  fontSize: 11,
                                ),
                              ),
                              AnimatedRotation(
                                turns: _expanded ? .5 : 0,
                                duration: const Duration(milliseconds: 180),
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 14,
                                  color: Colors.white.withValues(alpha: .45),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_expanded)
                Padding(
                  padding: const EdgeInsets.only(right: 4, bottom: 6),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final option in _options)
                        _StyleChip(
                          label: option.label,
                          selected: option.id == current,
                          onTap: () => _select(option.id),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StyleChip extends StatelessWidget {
  const _StyleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: .90)
              : Colors.white.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.black87 : Colors.white70,
          ),
        ),
      ),
    ),
  );
}

/// 进度条。拖拽/点击 seek 经命令回传主窗口执行（本地 controller 不接音频）。
class _PanelProgress extends StatefulWidget {
  const _PanelProgress({required this.playback});

  final PlaybackController playback;

  @override
  State<_PanelProgress> createState() => _PanelProgressState();
}

class _PanelProgressState extends State<_PanelProgress> {
  double? _scrub;

  String _time(double seconds) {
    if (!seconds.isFinite || seconds <= 0) return '0:00';
    final value = seconds.floor();
    return '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';
  }

  void _update(Offset local, double width, double duration) {
    if (duration <= 0 || width <= 0) return;
    setState(() => _scrub = (local.dx / width).clamp(0, 1) * duration);
  }

  void _seek(double seconds) =>
      DesktopPlayerCommands.send('seek', (seconds * 1000).round());

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Duration>(
    valueListenable: widget.playback.positionListenable,
    builder: (context, position, _) {
      final duration = widget.playback.state.duration.inMilliseconds / 1000;
      final current = _scrub ?? position.inMilliseconds / 1000;
      final fraction = duration <= 0
          ? 0.0
          : (current / duration).clamp(0.0, 1.0);
      return Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              _time(current),
              textAlign: TextAlign.right,
              style: _timeStyle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (event) =>
                      _update(event.localPosition, constraints.maxWidth, duration),
                  onHorizontalDragUpdate: (event) =>
                      _update(event.localPosition, constraints.maxWidth, duration),
                  onHorizontalDragEnd: (_) {
                    final seek = _scrub;
                    setState(() => _scrub = null);
                    if (seek != null) _seek(seek);
                  },
                  onTapUp: (event) => _seek(
                    (event.localPosition.dx / constraints.maxWidth).clamp(0, 1) *
                        duration,
                  ),
                  child: SizedBox(
                    height: 30,
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: SizedBox(
                          height: 6,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ColoredBox(
                                color: Colors.white.withValues(alpha: .15),
                              ),
                              FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: fraction,
                                child: ColoredBox(
                                  color: Colors.white.withValues(alpha: .75),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 32, child: Text(_time(duration), style: _timeStyle)),
        ],
      );
    },
  );

  static final _timeStyle = TextStyle(
    color: Colors.white.withValues(alpha: .45),
    fontSize: 9,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// 播放控制。
///
/// 桌面窗口是独立引擎，这里的操作要经跨窗口通道回传给主窗口执行——
/// 本地的 PlaybackController 只是显示层，调它的 play/pause 不会发声。
class _Transport extends StatelessWidget {
  const _Transport({required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RoundHoverButton(
          size: 36,
          icon: Icons.skip_previous_rounded,
          iconSize: 20,
          baseColor: Colors.transparent,
          iconColor: Colors.white.withValues(alpha: .55),
          onTap: () => DesktopPlayerCommands.send('previous'),
        ),
        const SizedBox(width: 12),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => DesktopPlayerCommands.send('togglePlay'),
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Color(0x1AFFFFFF), blurRadius: 16),
                ],
              ),
              child: Icon(
                playback.state.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 25,
                color: Colors.black,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _RoundHoverButton(
          size: 36,
          icon: Icons.skip_next_rounded,
          iconSize: 20,
          baseColor: Colors.transparent,
          iconColor: Colors.white.withValues(alpha: .55),
          onTap: () => DesktopPlayerCommands.send('next'),
        ),
      ],
    ),
  );
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.icon, required this.onTap, this.color});

  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => _RoundHoverButton(
    size: 28,
    icon: icon,
    iconSize: 15,
    baseColor: Colors.transparent,
    iconColor: color ?? Colors.white.withValues(alpha: .35),
    onTap: onTap,
  );
}

/// 收藏（爱心）。
///
/// 覆盖层里不弹「选择歌单」模态（会被钉底的窗口盖住，且要临时把整屏变成命中
/// 区域），因此语义固定为「加入/移出默认歌单」，由主窗口执行（见
/// DesktopPlayerStateSender._toggleFavorite）。未登录时置灰不可点。
class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.source});

  final DesktopPlayerPlayback source;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: source.favoriteAvailable,
    builder: (context, available, _) => ValueListenableBuilder<bool>(
      valueListenable: source.favorite,
      builder: (context, favorite, _) => Opacity(
        opacity: available ? 1 : .4,
        child: _SmallButton(
          icon: favorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          color: favorite
              ? const Color(0xFFF87171)
              : Colors.white.withValues(alpha: .35),
          onTap: () {
            if (!available) return;
            DesktopPlayerCommands.send('toggleFavorite');
          },
        ),
      ),
    ),
  );
}

class _RepeatButton extends StatelessWidget {
  const _RepeatButton({required this.playback});

  final PlaybackController playback;

  RepeatMode _next(RepeatMode mode) => switch (mode) {
    RepeatMode.all => RepeatMode.one,
    RepeatMode.one => RepeatMode.shuffle,
    RepeatMode.shuffle || RepeatMode.off => RepeatMode.all,
  };

  @override
  Widget build(BuildContext context) {
    final mode = playback.state.repeatMode;
    final active = mode != RepeatMode.off;
    final asset = switch (mode) {
      RepeatMode.one => 'assets/icons/MaterialSymbolsRepeatOneRounded.svg',
      RepeatMode.shuffle => 'assets/icons/BxShuffle.svg',
      _ => 'assets/icons/LucideRepeat.svg',
    };
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () =>
            DesktopPlayerCommands.send('setRepeatMode', _next(mode).name),
        child: SizedBox.square(
          dimension: 28,
          child: Center(
            child: SvgPicture.asset(
              asset,
              width: 15,
              height: 15,
              colorFilter: ColorFilter.mode(
                active
                    ? const Color(0xB37DD3FC)
                    : Colors.white.withValues(alpha: .35),
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VolumeControl extends StatelessWidget {
  const _VolumeControl({required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    final volume = playback.state.volume;
    return Row(
      children: [
        _SmallButton(
          icon: volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          color: Colors.white.withValues(alpha: .35),
          onTap: () =>
              DesktopPlayerCommands.send('setVolume', volume > 0 ? 0.0 : 0.8),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 64,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: Colors.white.withValues(alpha: .60),
              inactiveTrackColor: Colors.white.withValues(alpha: .15),
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: volume,
              // 拖动时本地立即跟随（乐观更新），同时把值回传主窗口；主窗口
              // 改完再推回来，signature 未变会走 setVolume 分支收敛。
              onChanged: (value) {
                playback.setVolume(value);
                DesktopPlayerCommands.send('setVolume', value);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _RoundHoverButton extends StatefulWidget {
  const _RoundHoverButton({
    required this.size,
    required this.icon,
    required this.iconSize,
    required this.onTap,
    this.baseColor = const Color(0x66000000),
    this.iconColor = const Color(0x80FFFFFF),
  });

  final double size;
  final IconData icon;
  final double iconSize;
  final VoidCallback onTap;
  final Color baseColor;
  final Color iconColor;

  @override
  State<_RoundHoverButton> createState() => _RoundHoverButtonState();
}

class _RoundHoverButtonState extends State<_RoundHoverButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: _hovered
              ? Colors.white.withValues(alpha: .10)
              : widget.baseColor,
          shape: BoxShape.circle,
        ),
        child: Icon(
          widget.icon,
          size: widget.iconSize,
          color: _hovered ? Colors.white : widget.iconColor,
        ),
      ),
    ),
  );
}
