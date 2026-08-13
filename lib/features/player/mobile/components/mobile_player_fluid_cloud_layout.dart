import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
// 只取进度指示器：原版文件按逐行移植保留，避免 miuix 全量导入与原版符号撞名。
// 额外取 MiuixIcon / MiuixIcons：底部工具栏的下载/信息/列表按钮改用 miuix 矢量图标。
import 'package:flutter_miuix/miuix.dart'
    show
        MiuixCircularProgressIndicator,
        MiuixProgressIndicatorColors,
        MiuixIcon,
        MiuixIcons;
import '../compat/player_service.dart';
import '../compat/playlist_service.dart';
import '../compat/download_service.dart';
import '../compat/wiki_services.dart';
import '../compat/lyric_line.dart';
import '../compat/lyric_style_service.dart';
import '../../../../domain/models/track.dart';
import '../../../../domain/models/music_source.dart';
import '../../amll/amll_lyric_panel.dart';
import 'mobile_player_fluid_cloud_lyric_panel.dart';
import 'mobile_player_fluid_cloud_song_wiki_panel.dart';
import 'mobile_player_dialogs.dart';
import 'mobile_player_settings_sheet.dart';
import 'dart:async';
import 'mobile_player_background.dart';
import '../compat/auto_collapse_service.dart';
import '../compat/audio_services.dart';
import '../compat/toast_utils.dart';
import '../compat/song_detail.dart';
import '../widgets/dynamic_cover_widget.dart';

/// 移动端流体云播放器布局
/// 参考 HTML 设计：统一在同一页面显示歌曲信息、歌词、控制按钮
/// 歌词样式参考桌面端流体云歌词，显示3行
class MobilePlayerFluidCloudLayout extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int currentLyricIndex;
  final bool showTranslation;
  final VoidCallback onBackPressed;
  final VoidCallback? onPlaylistPressed;

  const MobilePlayerFluidCloudLayout({
    super.key,
    required this.lyrics,
    required this.currentLyricIndex,
    required this.showTranslation,
    required this.onBackPressed,
    this.onPlaylistPressed,
  });

  @override
  State<MobilePlayerFluidCloudLayout> createState() => _MobilePlayerFluidCloudLayoutState();
}

class _MobilePlayerFluidCloudLayoutState extends State<MobilePlayerFluidCloudLayout> with TickerProviderStateMixin {
  // 自动折叠逻辑
  bool _isControlsVisible = true;
  Timer? _collapseTimer;
  bool _wasPlaying = false;
  // 封面模式 (经典模式)
  bool _showCoverMode = true;
  // 歌曲信息面板
  bool _showSongWikiPanel = false;

  // 下滑关闭相关
  double _dragOffset = 0;
  late AnimationController _snapController;
  late Animation<double> _snapAnimation;

  
  @override
  void initState() {
    super.initState();
    _wasPlaying = PlayerService().isPlaying;
    // 监听播放状态变化以控制计时器
    PlayerService().addListener(_onPlayerStateChanged);
    // 监听设置变化
    AutoCollapseService().addListener(_onSettingsChanged);
    
    // 初始化时如果正在播放且开启了折叠，启动计时器
    if (_wasPlaying && AutoCollapseService().isAutoCollapseEnabled) {
      _resetCollapseTimer();
    }

    // 初始化下滑回弹动画
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _snapController.addListener(() {
      setState(() {
        _dragOffset = _snapAnimation.value;
      });
    });
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    PlayerService().removeListener(_onPlayerStateChanged);
    AutoCollapseService().removeListener(_onSettingsChanged);
    _snapController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
    // 如果设置关闭，确保控件显示
    if (!AutoCollapseService().isAutoCollapseEnabled) {
      _showControls(autoHide: false);
    } else {
      // 开启时，如果正在播放，重置计时器
      if (PlayerService().isPlaying && _isControlsVisible) {
        _resetCollapseTimer();
      }
    }
  }

  void _onPlayerStateChanged() {
    // 仅在播放状态改变时处理
    final isPlaying = PlayerService().isPlaying;
    if (isPlaying != _wasPlaying) {
      _wasPlaying = isPlaying;
      
      // Trigger rebuild for cover animation
      if (mounted) setState(() {});

      if (AutoCollapseService().isAutoCollapseEnabled) {
        if (isPlaying) {
          // 开始播放，如果控件可见，启动计时器
          if (_isControlsVisible) {
            _resetCollapseTimer();
          }
        } else {
          // 暂停时始终显示
          _showControls(autoHide: false);
        }
      }
    }
  }

  /// 显示控制栏
  /// [autoHide] 是否在显示后自动启动隐藏倒计时
  void _showControls({bool autoHide = true}) {
    if (!_isControlsVisible) {
      setState(() => _isControlsVisible = true);
    }
    
    if (autoHide && AutoCollapseService().isAutoCollapseEnabled && PlayerService().isPlaying) {
      _resetCollapseTimer();
    } else {
      _collapseTimer?.cancel();
    }
  }

  void _resetCollapseTimer() {
    _collapseTimer?.cancel();
    if (AutoCollapseService().isAutoCollapseEnabled && PlayerService().isPlaying) {
      _collapseTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() => _isControlsVisible = false);
        }
      });
    }
  }

  /// 切换控制栏可见性
  void _toggleControls() {
    if (AutoCollapseService().isAutoCollapseEnabled) {
      if (_isControlsVisible) {
        // 如果当前可见，手动点击则隐藏（可选，或只是忽略）
        setState(() => _isControlsVisible = false);
      } else {
        // 如果当前隐藏，点击则显示
        _showControls();
      }
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
      if (_dragOffset < 0) _dragOffset = 0; // 不允许向上拖动
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dragOffset > 150 || (details.primaryVelocity ?? 0) > 800) {
      // 下滑超过阈值或速度足够快，关闭播放器
      widget.onBackPressed();
    } else {
      // 回弹
      _snapAnimation = Tween<double>(
        begin: _dragOffset,
        end: 0,
      ).animate(CurvedAnimation(
        parent: _snapController,
        curve: Curves.easeOutCubic,
      ));
      _snapController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = PlayerService();
    final song = player.currentSong;
    final track = player.currentTrack;
    final imageUrl = song?.pic ?? track?.picUrl ?? '';

    // 检测屏幕方向
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;

    // 不再这里提前返回，统一在下方的 Stack 中处理
    // if (isLandscape) {
    //   // 横屏模式：左右分栏布局
    //   return _buildLandscapeLayout(context, player, song, track, imageUrl);
    // }

    // 竖屏模式：使用 Stack + AnimatedPositioned 实现丝滑切换
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final safePadding = MediaQuery.of(context).padding;
    final topBarHeight = 50.0;
    
    // --- 封面模式参数计算 ---
    // 预留底部高度 (标题+歌词+进度条+控制栏+底部导航+间距)
    const reservedBottomHeight = 350.0;
    
    // 封面起始 Y 坐标 (绝对坐标)
    // 保证在 TopBar 下方，且距离顶部有一定比例
    // Modified: Reduced buffer and ideal top ratio to move cover up
    final minCoverTop = safePadding.top + topBarHeight + 10;
    final idealCoverTop = screenHeight * 0.10;
    final bigCoverTop = idealCoverTop < minCoverTop ? minCoverTop : idealCoverTop;
    
    // 计算可用高度
    final availableHeight = screenHeight - bigCoverTop - reservedBottomHeight;
    // 封面尺寸：宽度限制(屏幕-64)，高度限制(可用高度)
    final bigCoverSize = (screenWidth - 64).clamp(100.0, availableHeight < 100 ? 100.0 : availableHeight);
    
    // --- 歌词模式参数 ---
    final smallCoverSize = 56.0;
    final smallCoverTop = safePadding.top + 24.0;
    final smallCoverLeft = 16.0;

    // Animation Logic: Shrink by 10% when paused in Cover Mode
    final bool isPlaying = player.isPlaying;
    final effectiveBigSize = isPlaying ? bigCoverSize : bigCoverSize * 0.9;
    
    final targetSize = _showCoverMode ? effectiveBigSize : smallCoverSize;
    // When shrinking, keep centered relative to the original bigCover box
    final targetTop = _showCoverMode 
        ? bigCoverTop + (bigCoverSize - effectiveBigSize) / 2 
        : smallCoverTop;
    final targetLeft = _showCoverMode 
        ? (screenWidth - effectiveBigSize) / 2 
        : smallCoverLeft;

    return GestureDetector(
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: ClipRRect(
          // 仅在向下拖动时显示圆角，全屏状态无圆角
          borderRadius: _dragOffset > 0
              ? const BorderRadius.vertical(top: Radius.circular(32))
              : BorderRadius.zero,
          child: Stack(
            children: [
              // 0. 背景层 (现在作为布局的一部分，以便同步平移)
              MobilePlayerBackground(dragOffset: _dragOffset),

              // 1. 歌词模式布局或横屏布局 (底层)
              if (isLandscape)
                _buildLandscapeLayout(context, player, song, track, imageUrl)
              else
                SafeArea(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: _showCoverMode ? 0.0 : 1.0,
                    curve: Curves.easeInOut,
                    child: IgnorePointer(
                      ignoring: _showCoverMode,
                      child: GestureDetector(
                        onTap: _toggleControls, // 支持点击空白收起控制栏
                        behavior: HitTestBehavior.translucent,
                        child: Column(
                          children: [
                            // 顶部歌曲信息 (仅在歌词模式渲染内容)
                            if (!_showCoverMode)
                              _buildSongInfoSection(context, song, track, imageUrl, isGhost: true),
                                
                            // 中间区域：歌词或歌曲信息面板
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 400),
                                transitionBuilder: (Widget child, Animation<double> animation) {
                                  return FadeTransition(opacity: animation, child: child);
                                },
                                child: _showSongWikiPanel
                                    ? const MobilePlayerFluidCloudSongWikiPanel(key: ValueKey('wiki'))
                                    : _buildLyricsSection(),
                              ),
                            ),
                      
                            // 底部控制 (上一首、播放、下一首等)
                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              alignment: Alignment.topCenter,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 300),
                                opacity: _isControlsVisible ? 1.0 : 0.0,
                                child: _isControlsVisible
                                    ? Padding(
                                        padding: const EdgeInsets.only(top: 0), 
                                        child: _buildControlsSection(player),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                            
                            if (!_isControlsVisible)
                               const SizedBox(height: 16),
                            
                            // 留给底部导航的空间
                            const SizedBox(height: 64),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // 2. 封面模式布局 (仅在竖屏存在)
              if (!isLandscape)
                SafeArea(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: _showCoverMode ? 1.0 : 0.0,
                    curve: Curves.easeInOut,
                    child: IgnorePointer(
                      ignoring: !_showCoverMode,
                      child: _buildCoverModeLayout(
                        context, 
                        player, 
                        song, 
                        track, 
                        imageUrl, 
                        coverSize: bigCoverSize,
                        topSpacing: bigCoverTop - safePadding.top - topBarHeight, // 传递准确的间距
                        isGhost: true,
                      ),
                    ),
                  ),
                ),

              // 3. 浮动封面 (顶层，负责动画，仅在竖屏启用)
              if (!isLandscape)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.fastLinearToSlowEaseIn,
                  top: targetTop,
                  left: targetLeft,
                  width: targetSize,
                  height: targetSize,
                  child: GestureDetector(
                    onTap: () {
                      // 点击切换模式
                      setState(() => _showCoverMode = !_showCoverMode);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.fastLinearToSlowEaseIn,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_showCoverMode ? 16 : 8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: _showCoverMode ? 0.4 : 0.3),
                            blurRadius: _showCoverMode ? 40 : 10,
                            offset: Offset(0, _showCoverMode ? 20 : 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: imageUrl.isNotEmpty
                          ? _buildCoverImage(imageUrl)
                          : Container(
                              color: Colors.grey[900],
                              child: Icon(
                                Icons.music_note, 
                                color: Colors.white54,
                                size: _showCoverMode ? 120 : 30,
                              ),
                            ),
                    ),
                  ),
                ),

            // 4. 顶层拖动条 (小白条)
            Positioned(
              top: safePadding.top + 10,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 36,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2.25),
                  ),
                ),
              ),
            ),

            // 5. 固定底部导航 (始终在屏幕底部固定位置，仅在竖屏显示)
            if (!isLandscape)
              Positioned(
                left: 0,
                right: 0,
                bottom: safePadding.bottom + 8,
                child: _buildBottomNavigation(context, track),
              ),
          ],
          ),
        ),
      ),
    );
  }

  /// 构建封面模式布局 (大封面 + 控制器，无歌词)
  Widget _buildCoverModeLayout(
    BuildContext context,
    PlayerService player,
    dynamic song,
    dynamic track,
    String imageUrl, {
    required double coverSize,
    required double topSpacing,
    bool isGhost = false,
  }) {
    return Column(
      key: const ValueKey('CoverModeLayout'),
      children: [
          // 顶部栏
          SizedBox(
            height: 50, // 与 topBarHeight 一致
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end, 
                children: [
                   IconButton(
                    icon: Icon(
                      Icons.more_horiz,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                    onPressed: () {
                      MobilePlayerSettingsSheet.show(context, currentTrack: track);
                    },
                  ),
                ],
              ),
            ),
          ),
          
          // 精确控制封面位置，使其与 AnimatedPositioned 重合
          SizedBox(height: topSpacing > 0 ? topSpacing : 0),
          
          // 大封面占位
          GestureDetector(
            onTap: () {
               if (!isGhost) setState(() => _showCoverMode = false);
            },
            child: Container(
              width: coverSize,
              height: coverSize,
              color: Colors.transparent, 
            ),
          ),
          
          // 剩余空间分配给控件
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Spacer(),
                
                // 歌曲信息 (标题和歌手) - 左对齐
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song?.name ?? track?.name ?? '未知歌曲',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              song?.arName ?? track?.artists ?? '未知艺术家',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (track != null) _FavoriteButton(track: track),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),

                // 控制区
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildControlsSection(player, isCoverMode: true), 
                ),
                
                const SizedBox(height: 30),

                // 留给底部导航的空间 (底部导航现在在 Stack 中固定位置)
                const SizedBox(height: 64),
              ],
            ),
          ),
        ],
      );
  }
  

  /// 横屏模式布局 - 参考图片设计
  /// 左侧：专辑封面 + 进度条 (统一水平线)
  /// 右侧：歌曲信息 + 歌词 + 控制按钮 (统一水平线)
  Widget _buildLandscapeLayout(
    BuildContext context,
    PlayerService player,
    dynamic song,
    dynamic track,
    String imageUrl,
  ) {
    final name = song?.name ?? track?.name ?? '未知歌曲';
    final artist = song?.arName ?? track?.artists ?? '未知艺术家';
    
    final screenHeight = MediaQuery.of(context).size.height;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom; // 底部安全区
    
    // 封面大小
    final coverSize = (screenHeight - safeAreaBottom - 60) * 0.65;
    final progressBarWidth = coverSize + 48; // 进度条比封面略宽

    // 底部对齐的高度 (控制栏高度)
    const bottomControlsHeight = 60.0;
    // 底部留白
    const bottomPadding = 24.0; 

    return Stack(
      children: [
        // 右上角更多按钮
        Positioned(
          top: 8,
          right: 16,
          child: IconButton(
            icon: Icon(
              Icons.more_horiz,
              color: Colors.white.withValues(alpha: 0.8),
            ),
            iconSize: 24,
            onPressed: () {
              MobilePlayerSettingsSheet.show(context, currentTrack: track);
            },
          ),
        ),

        // 主布局
        Padding(
          padding: const EdgeInsets.only(bottom: bottomPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end, // 底部对齐，保证进度条和控制栏在同一水平线
            children: [
              // 1. 左侧面板: 封面 + 进度条
              Expanded(
                flex: 4, 
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end, // 底部对齐
                  children: [
                    const Spacer(),
                    // 封面
                     Container(
                      width: coverSize,
                      height: coverSize,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: imageUrl.isNotEmpty
                          ? _buildCoverImage(imageUrl)
                          : Container(
                              color: Colors.grey[900],
                              child: const Icon(
                                Icons.music_note,
                                size: 80,
                                color: Colors.white54,
                              ),
                            ),
                    ),
                    
                    const Spacer(), // 封面和进度条之间的弹簧

                    // 底部进度条 (高度与右侧控制栏对齐容器)
                    SizedBox(
                      height: bottomControlsHeight,
                      child: Center(
                        child: _buildLandscapeProgressBar(player, progressBarWidth),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. 右侧面板: 信息 + 歌词 + 控制按钮
              Expanded(
                flex: 6,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 24, 32, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 顶部信息
                      _buildLandscapeTitleSection(name, artist),
                      const SizedBox(height: 16),
                      
                      // 歌词
                      Expanded(
                        child: _buildLandscapeLyricsSection(),
                      ),
                      
                      const SizedBox(height: 12),

                      // 底部控制必须有固定高度，以便与左侧对齐
                      SizedBox(
                        height: bottomControlsHeight,
                        child: _buildLandscapeBottomControls(context, player, track),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 横屏标题区域
  Widget _buildLandscapeTitleSection(String name, String artist) {
    return Row(
      children: [
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: name,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
                const TextSpan(text: '  '),
                TextSpan(
                  text: artist,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.7),
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
  
  /// 横屏进度条 (用于左侧)
  Widget _buildLandscapeProgressBar(PlayerService player, double width) {
    return ValueListenableBuilder<List<Map<String, int>>?>(
      valueListenable: player.chorusTimesNotifier,
      builder: (context, chorusTimes, child) {
        return AnimatedBuilder(
          animation: player.positionNotifier,
          builder: (context, _) {
            final position = player.positionNotifier.value.inMilliseconds.toDouble();
            final durationMs = player.duration.inMilliseconds.toDouble();
            final progress = (durationMs > 0) ? (position / durationMs).clamp(0.0, 1.0) : 0.0;

            return SizedBox(
              width: width,
              height: 24, // 增加点击热区
              child: _AppleMusicSlider(
                value: progress,
                onChanged: (v) {
                  final pos = Duration(milliseconds: (v * durationMs).round());
                  player.seek(pos);
                },
                durationMs: durationMs,
                activeColor: Colors.white,
                inactiveColor: const Color(0x1FFFFFFF),
                chorusTimes: chorusTimes,
              ),
            );
          },
        );
      },
    );
  }

  /// 横屏底部控制区 (仅控制按钮 + 时间)
  Widget _buildLandscapeBottomControls(BuildContext context, PlayerService player, Track? track) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center, // 垂直居中
      children: [
         // 时间 - 字体加大
         AnimatedBuilder(
           animation: player.positionNotifier,
           builder: (context, _) => Text(
             '${_formatDurationCompact(player.positionNotifier.value)}/${_formatDurationCompact(player.duration)}',
             style: TextStyle(
               color: Colors.white.withValues(alpha: 0.6),
               fontSize: 16, // 加大字体
               fontWeight: FontWeight.bold,
               fontFamily: 'Consolas',
               letterSpacing: 0.5,
             ),
           ),
         ),

         const SizedBox(width: 12),
         _buildQualityButton(context),

         // 控制按钮行 - 居中且使用 iOS 粗图标
         Expanded(
           child: Center(
             child: AnimatedBuilder(
               animation: player, // 只有播放/暂停等状态改变才需要重建按钮区域
               builder: (context, _) {
                 return Row(
                   mainAxisSize: MainAxisSize.min,
                   children: [
                     // 上一首
                     IconButton(
                       icon: const Icon(CupertinoIcons.backward_fill), // iOS 风格粗图标
                       color: Colors.white,
                       iconSize: 36, // 图标加大
                       onPressed: player.hasPrevious ? player.playPrevious : null,
                     ),
                     const SizedBox(width: 16),
                     
                     // 播放/暂停
                     IconButton(
                       icon: Icon(
                         player.isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                         color: Colors.white,
                       ),
                       iconSize: 56, // 加大图标尺寸，保持醒目
                       padding: EdgeInsets.zero,
                       onPressed: player.togglePlayPause,
                     ),
                     const SizedBox(width: 16),
                     
                     // 下一首
                     IconButton(
                       icon: const Icon(CupertinoIcons.forward_fill), // iOS 风格粗图标
                       color: Colors.white,
                       iconSize: 36, // 图标加大
                       onPressed: player.hasNext ? player.playNext : null,
                     ),
                   ],
                 );
               },
             ),
           ),
         ),
         
         // 喜欢按钮
         if (track != null) _FavoriteButton(track: track),
      ],
    );
  }

  /// 横屏模式歌词区域
  Widget _buildLandscapeLyricsSection() {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: const [0.0, 0.08, 0.92, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: _buildLyricPanel(visibleLineCount: 3),
    );
  }

  /// 格式化时间（紧凑格式：00:01）
  String _formatDurationCompact(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// 构建歌曲信息区域（参考 HTML section#song-info）
  Widget _buildSongInfoSection(BuildContext context, dynamic song, dynamic track, String imageUrl, {bool isGhost = false}) {
    final name = song?.name ?? track?.name ?? '未知歌曲';
    final artists = song?.arName ?? track?.artists ?? '未知艺术家';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Row(
        children: [
          // 专辑封面占位 (实际封面由顶层 Stack 处理)
          GestureDetector(
            onTap: () {
               if (!isGhost) setState(() => _showCoverMode = true);
            },
            child: Container(
              width: 56,
              height: 56,
              color: Colors.transparent, // 占位透明
            ),
          ),
          const SizedBox(width: 12),

          // 歌曲标题和歌手
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontFamily: 'Microsoft YaHei',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  artists,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.7),
                    fontFamily: 'Microsoft YaHei',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // 右侧操作按钮
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 收藏按钮
              if (track != null)
                _FavoriteButton(track: track),
              // 更多选项 - 弹出设置侧边栏
              IconButton(
                icon: Icon(
                  Icons.more_vert,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
                onPressed: () {
                  MobilePlayerSettingsSheet.show(context, currentTrack: track);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建歌词区域 - 复用桌面端流体云歌词组件，通过遮罩限制只显示3行
  Widget _buildLyricsSection() {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        // 上下渐变遮罩
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.black,
            Colors.transparent,
            Colors.transparent,
          ],
          stops: const [
            0.0,    // 顶部完全透明
            0.15,   // 开始可见
            0.5,    // 中心
            0.85,   // 依然可见
            0.95,   // 开始渐变
            1.0,    // 底部完全透明
          ],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      // 当控制栏隐藏时显示更多行数，否则显示 5 行。
      // 可见行数决定了字号与行高的计算。
      child: _buildLyricPanel(
        visibleLineCount: _isControlsVisible ? 5 : 8,
      ),
    );
  }

  /// 按当前歌词样式选择歌词面板实现。
  Widget _buildLyricPanel({required int visibleLineCount}) {
    if (LyricStyleService().currentStyle == LyricStyle.amll) {
      return AmllLyricPanel(
        lyrics: widget.lyrics,
        showTranslation: widget.showTranslation,
        visibleLineCount: visibleLineCount,
      );
    }
    return MobilePlayerFluidCloudLyricsPanel(
      lyrics: widget.lyrics,
      currentLyricIndex: widget.currentLyricIndex,
      showTranslation: widget.showTranslation,
      visibleLineCount: visibleLineCount,
    );
  }

  /// 构建控制区域（进度条 + 播放按钮）
  Widget _buildControlsSection(PlayerService player, {bool isCoverMode = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // 进度条
          Column(
            children: [
            // 进度条 - Apple Music 风格
            ValueListenableBuilder<List<Map<String, int>>?>(
              valueListenable: player.chorusTimesNotifier,
              builder: (context, chorusTimes, child) {
                return AnimatedBuilder(
                  animation: player.positionNotifier,
                  builder: (context, _) {
                    final position = player.positionNotifier.value.inMilliseconds.toDouble();
                    final durationMs = player.duration.inMilliseconds.toDouble();
                    final value = (durationMs > 0) ? (position / durationMs).clamp(0.0, 1.0) : 0.0;
                    
                    return SizedBox(
                       height: 24, // 增加点击热区
                       child: _AppleMusicSlider(
                          value: value,
                          onChanged: (v) {
                            final pos = Duration(milliseconds: (v * durationMs).round());
                            player.seek(pos);
                          },
                          durationMs: durationMs,
                          activeColor: Colors.white,
                          inactiveColor: const Color(0x1FFFFFFF),
                          chorusTimes: chorusTimes,
                        ),
                    );
                  },
                );
              },
            ),
              
              const SizedBox(height: 8),

              // 时间显示
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AnimatedBuilder(
                      animation: player.positionNotifier,
                      builder: (context, _) => Text(
                        _formatDuration(player.positionNotifier.value),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13, 
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Consolas',
                        ),
                      ),
                    ),
                    
                    // --- 核心：音质切换按钮 ---
                    _buildQualityButton(context),

                    AnimatedBuilder(
                      animation: player,
                      builder: (context, _) => Text(
                        _formatDuration(player.duration),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13, 
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Consolas',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 40),

          // 播放控制按钮 (iOS 风格)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 上一首
              IconButton(
                icon: const Icon(CupertinoIcons.backward_fill),
                color: Colors.white.withValues(alpha: 0.9),
                iconSize: 42, 
                onPressed: player.hasPrevious ? player.playPrevious : null,
              ),
              
              // 播放/暂停（大图标，无圆形背景）
              AnimatedBuilder(
                animation: player,
                builder: (context, _) {
                  return IconButton(
                    icon: Icon(
                      player.isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                      color: Colors.white,
                    ),
                    iconSize: 72, 
                    padding: EdgeInsets.zero,
                    onPressed: player.togglePlayPause,
                  );
                },
              ),
              
              // 下一首
              IconButton(
                icon: const Icon(CupertinoIcons.forward_fill),
                color: Colors.white.withValues(alpha: 0.9),
                iconSize: 42, 
                onPressed: player.hasNext ? player.playNext : null,
              ),
            ],
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  /// 构建底部导航（参考 HTML footer#bottom-nav）
  Widget _buildBottomNavigation(BuildContext context, Track? track) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 1. 歌词模式切换按钮 (最左侧)
          IconButton(
            icon: Icon(
              CupertinoIcons.quote_bubble,
              color: !_showCoverMode ? Colors.white : Colors.white.withValues(alpha: 0.4),
            ),
            iconSize: 24,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              setState(() => _showCoverMode = !_showCoverMode);
            },
          ),
          
          // 2. 下载按钮
          _buildNavButton(
            icon: track != null
                ? _DownloadButton(track: track)
                : MiuixIcon(
                    vector: MiuixIcons.extended.byName('download')!,
                    size: 24,
                    tint: Colors.white.withValues(alpha: 0.3),
                  ),
            visible: !_showCoverMode && track != null,
            placeholder: true,
          ),
          
          // 3. 歌曲信息按钮 (仅网易云歌曲显示)
          _buildNavButton(
            icon: IconButton(
              icon: MiuixIcon(
                vector: _showSongWikiPanel
                    ? MiuixIcons.extended.byName('notes')!
                    : MiuixIcons.extended.byName('info')!,
                size: 22,
                tint: _showSongWikiPanel
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.7),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                setState(() => _showSongWikiPanel = !_showSongWikiPanel);
              },
            ),
            visible: !_showCoverMode && track != null && track.source == MusicSource.netease,
            placeholder: true,
          ),

          // 4. 播放列表按钮
          IconButton(
            icon: MiuixIcon(
              vector: MiuixIcons.extended.byName('playlist')!,
              size: 26,
              tint: Colors.white.withValues(alpha: 0.8),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: widget.onPlaylistPressed,
          ),
        ],
      ),
    );
  }

  /// 构建底部导航按钮（支持条件显示和占位）
  Widget _buildNavButton({
    required Widget icon,
    required bool visible,
    bool placeholder = false,
  }) {
    if (visible) {
      return icon;
    }
    // 占位符保持间距一致
    return placeholder ? const SizedBox(width: 24) : const SizedBox.shrink();
  }



  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 构建音质选择按钮
  Widget _buildQualityButton(BuildContext context) {
    return ListenableBuilder(
      listenable: AudioQualityService(),
      builder: (context, _) {
        final qualityService = AudioQualityService();
        final label = qualityService.getShortLabel();
        
        return GestureDetector(
          onTap: () => _showQualitySelectionSheet(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        );
      },
    );
  }

  /// 显示音质选择底部菜单
  void _showQualitySelectionSheet(BuildContext context) {
    final qualityService = AudioQualityService();
    final sourceService = AudioSourceService();
    final supportedQualities = sourceService.activeSource != null
        ? qualityService.getSupportedQualities(sourceService.sourceType)
        : [AudioQuality.standard, AudioQuality.exhigh, AudioQuality.lossless];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.grey[900]?.withValues(alpha: 0.95),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  '选择播放音质',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ...supportedQualities.map((quality) {
                final isSelected = qualityService.currentQuality == quality;
                return ListTile(
                  title: Text(
                    qualityService.getQualityName(quality),
                    style: TextStyle(
                      color: isSelected ? Colors.blueAccent : Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    qualityService.getQualityDescription(quality),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                  trailing: isSelected 
                      ? const Icon(Icons.check, color: Colors.blueAccent) 
                      : null,
                  onTap: () {
                    qualityService.setQuality(quality);
                    Navigator.pop(context);
                    ToastUtils.success('音质已设置为 ${qualityService.getQualityName(quality)}，将在下次切换歌曲时生效');
                  },
                );
              }),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建封面图片（支持网络 URL、本地文件路径及动态视频封面）
  Widget _buildCoverImage(String imageUrl) {
    return DynamicCoverWidget(
      imageUrl: imageUrl,
      width: double.infinity,
      height: double.infinity,
    );
  }
}

/// 收藏按钮组件
class _FavoriteButton extends StatefulWidget {
  final Track track;

  const _FavoriteButton({required this.track});

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  bool _isInPlaylist = false;
  bool _isLoading = true;
  List<String> _playlistNames = [];
  List<int> _playlistIds = [];

  @override
  void initState() {
    super.initState();
    _checkIfInPlaylist();
  }

  @override
  void didUpdateWidget(_FavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id ||
        oldWidget.track.source != widget.track.source) {
      _checkIfInPlaylist();
    }
  }

  Future<void> _checkIfInPlaylist() async {
    setState(() => _isLoading = true);

    final playlistService = PlaylistService();
    final result = await playlistService.isTrackInAnyPlaylist(widget.track);

    if (mounted) {
      setState(() {
        _isInPlaylist = result.inPlaylist;
        _playlistNames = result.playlistNames;
        _playlistIds = result.playlistIds;
        _isLoading = false;
      });
    }
  }

  Future<void> _removeFromPlaylists() async {
    if (_playlistIds.isEmpty) return;
    
    final playlistService = PlaylistService();
    
    for (final playlistId in _playlistIds) {
      await playlistService.removeTrackFromPlaylist(
        playlistId,
        widget.track.id.toString(),
        widget.track.source.name,
      );
    }
    
    // 刷新状态
    _checkIfInPlaylist();
  }

  void _showManageOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                '已收藏到: ${_playlistNames.join(", ")}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
              title: const Text('从所有歌单移除', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                await _removeFromPlaylists();
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add, color: Colors.white70),
              title: const Text('添加到其他歌单', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                MobilePlayerDialogs.showAddToPlaylist(context, widget.track);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: MiuixCircularProgressIndicator(
            size: 20,
            strokeWidth: 2,
            colors: MiuixProgressIndicatorColors(
              foregroundColor: Colors.white54,
              disabledForegroundColor: Colors.white54,
              backgroundColor: Colors.transparent,
            ),
          ),
        ),
      );
    }

    final tooltip = _isInPlaylist
        ? '已收藏到: ${_playlistNames.join(", ")}'
        : '添加到歌单';

    return IconButton(
      icon: Icon(
        _isInPlaylist ? Icons.favorite : Icons.favorite_border,
        color: _isInPlaylist ? Colors.redAccent : Colors.white.withValues(alpha: 0.8),
      ),
      onPressed: () {
        if (_isInPlaylist) {
          _showManageOptions(context);
        } else {
          MobilePlayerDialogs.showAddToPlaylist(context, widget.track);
        }
      },
      tooltip: tooltip,
    );
  }
}

/// 下载按钮组件
class _DownloadButton extends StatefulWidget {
  final Track track;

  const _DownloadButton({required this.track});

  @override
  State<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<_DownloadButton> {
  bool _isDownloaded = false;
  bool _isDownloading = false;
  bool _isLoading = true;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _checkDownloadStatus();
    DownloadService().addListener(_onDownloadChanged);
  }

  @override
  void dispose() {
    DownloadService().removeListener(_onDownloadChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(_DownloadButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id ||
        oldWidget.track.source != widget.track.source) {
      _checkDownloadStatus();
    }
  }

  void _onDownloadChanged() {
    if (!mounted) return;
    
    final downloadService = DownloadService();
    final trackId = '${widget.track.source.name}_${widget.track.id}';
    final tasks = downloadService.downloadTasks;
    final task = tasks[trackId];
    
    if (task != null) {
      setState(() {
        _isDownloading = !task.isCompleted && !task.isFailed;
        _progress = task.progress;
        if (task.isCompleted) {
          _isDownloaded = true;
          _isDownloading = false;
        }
      });
    }
  }

  Future<void> _checkDownloadStatus() async {
    setState(() => _isLoading = true);
    
    final isDownloaded = await DownloadService().isDownloaded(widget.track);
    
    if (mounted) {
      setState(() {
        _isDownloaded = isDownloaded;
        _isLoading = false;
      });
    }
  }

  Future<void> _startDownload() async {
    if (_isDownloading || _isDownloaded) return;
    
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
    });
    
    try {
      // 获取歌曲详情
      final songDetail = PlayerService().currentSong;
      if (songDetail == null) {
        // 如果当前没有歌曲详情，尝试获取
        final detail = await MusicService().fetchSongDetail(
          songId: widget.track.id.toString(),
          source: widget.track.source,
        );
        
        if (detail == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('获取歌曲信息失败')),
            );
            setState(() => _isDownloading = false);
          }
          return;
        }
        
        final success = await DownloadService().downloadSong(
          widget.track,
          detail,
          onProgress: (progress) {
            if (mounted) {
              setState(() => _progress = progress);
            }
          },
        );
        
        if (mounted) {
          if (success) {
            setState(() {
              _isDownloaded = true;
              _isDownloading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${widget.track.name} 下载完成')),
            );
          } else {
            setState(() => _isDownloading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('下载失败')),
            );
          }
        }
      } else {
        final success = await DownloadService().downloadSong(
          widget.track,
          songDetail,
          onProgress: (progress) {
            if (mounted) {
              setState(() => _progress = progress);
            }
          },
        );
        
        if (mounted) {
          if (success) {
            setState(() {
              _isDownloaded = true;
              _isDownloading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${widget.track.name} 下载完成')),
            );
          } else {
            setState(() => _isDownloading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('下载失败或文件已存在')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: MiuixCircularProgressIndicator(
            size: 24,
            strokeWidth: 2,
            colors: MiuixProgressIndicatorColors(
              foregroundColor: Colors.white54,
              disabledForegroundColor: Colors.white54,
              backgroundColor: Colors.transparent,
            ),
          ),
        ),
      );
    }

    if (_isDownloading) {
      return SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            MiuixCircularProgressIndicator(
              progress: _progress,
              size: 48,
              strokeWidth: 2,
              colors: const MiuixProgressIndicatorColors(
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
            Text(
              '${(_progress * 100).toInt()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
    }

    return IconButton(
      icon: MiuixIcon(
        vector: _isDownloaded
            ? MiuixIcons.basic.check
            : MiuixIcons.extended.byName('download')!,
        size: 24,
        tint: _isDownloaded ? Colors.green : Colors.white.withValues(alpha: 0.8),
      ),
      onPressed: _isDownloaded ? null : _startDownload,
      tooltip: _isDownloaded ? '已下载' : '下载',
    );
  }
}

/// Apple Music 风格的 Slider 组件
/// 1. 默认显示微弱滑块
/// 2. 交互时激活轨道变亮
/// 3. 使用圆形滑块，触摸拖动时放大
class _AppleMusicSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final Color activeColor;
  final Color inactiveColor;
  final List<Map<String, int>>? chorusTimes;
  final double? durationMs;

  const _AppleMusicSlider({
    required this.value,
    required this.onChanged,
    required this.activeColor,
    required this.inactiveColor,
    this.chorusTimes,
    this.durationMs,
  }) : min = 0.0,
       max = 1.0;

  @override
  State<_AppleMusicSlider> createState() => _AppleMusicSliderState();
}

class _AppleMusicSliderState extends State<_AppleMusicSlider> with SingleTickerProviderStateMixin {
  double? _dragValue; // 保存拖动过程中的临时进度
  
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    // 动画用于控制圆点大小和透明度
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // 未交互时，由于圆点完全隐藏，我们使用稍微不同的颜色方案
        // 交互时，已播放轨道变得明显更亮，背景轨道也略微变亮
        final currentActiveColor = Color.lerp(
          widget.activeColor.withValues(alpha: 0.55), // 未交互时较淡
          widget.activeColor.withValues(alpha: 0.9),  // 交互时较亮
          _animation.value
        ) ?? widget.activeColor;
        
        final currentInactiveColor = Color.lerp(
          widget.inactiveColor, // 未交互时使用传入极低透明度
          Colors.white.withValues(alpha: 0.25), // 交互时背景轨道显得更清晰一点
          _animation.value
        ) ?? widget.inactiveColor;

        return SliderTheme(
          data: SliderThemeData(
            trackHeight: 6, 
            trackShape: _ChorusSliderTrackShape(
              chorusTimes: widget.chorusTimes,
              durationMs: widget.durationMs ?? widget.max,
            ),
            thumbShape: _AppleMusicThumbShape(
              scale: _animation.value, // 完全跟随动画，未交互时为 0 (隐藏)
              opacity: _animation.value,
            ),
            overlayShape: SliderComponentShape.noOverlay,
            activeTrackColor: currentActiveColor,
            inactiveTrackColor: currentInactiveColor,
          ),
          child: Slider(
            value: _dragValue ?? widget.value,
            onChanged: (v) {
              setState(() {
                _dragValue = v; // 立即更新本地值以确保拖动流畅
              });
              if (widget.onChanged != null) widget.onChanged!(v);
            },
            onChangeStart: (_) {
              setState(() {
                _dragValue = widget.value;
              });
              _controller.forward();
            },
            onChangeEnd: (_) {
              setState(() {
                _dragValue = null; // 释放拖动，恢复跟随外部进度
              });
              _controller.reverse();
            },
            min: widget.min,
            max: widget.max,
          ),
        );
      }
    );
  }
}

/// 自定义轨道，支持渲染副歌高亮区间
class _ChorusSliderTrackShape extends RoundedRectSliderTrackShape {
  final List<Map<String, int>>? chorusTimes;
  final double durationMs;

  const _ChorusSliderTrackShape({
    this.chorusTimes,
    required this.durationMs,
  });

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2.0,
  }) {
    // 1. 绘制原始的背景轨和已播放轨
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );

    if (durationMs <= 0 || chorusTimes == null || chorusTimes!.isEmpty) return;

    // 2. 在上方绘制副歌高亮区间
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    
    final Paint chorusPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
      
    final double trackWidth = trackRect.width;

    for (final chorus in chorusTimes!) {
      final startTimeMs = chorus['startTime']?.toDouble() ?? 0.0;
      final endTimeMs = chorus['endTime']?.toDouble() ?? 0.0;
      if (startTimeMs >= endTimeMs) continue;

      final startFraction = (startTimeMs / durationMs).clamp(0.0, 1.0);
      final endFraction = (endTimeMs / durationMs).clamp(0.0, 1.0);
      
      final startX = trackRect.left + startFraction * trackWidth;
      final endX = trackRect.left + endFraction * trackWidth;
      
      final chorusRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(startX, trackRect.top, endX, trackRect.bottom),
        const Radius.circular(3.0),
      );

      context.canvas.drawRRect(chorusRect, chorusPaint);
    }
  }
}

/// 自定义圆形滑块，支持缩放和透明度动画
class _AppleMusicThumbShape extends SliderComponentShape {
  final double scale;
  final double opacity;
  final double maxRadius;

  const _AppleMusicThumbShape({
    required this.scale,
    this.opacity = 1.0,
  }) : maxRadius = 6.0;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(maxRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    if (scale <= 0.01) return; // 隐藏不绘制

    final Canvas canvas = context.canvas;
    
    // 绘制阴影
    final path = Path()
      ..addOval(Rect.fromCircle(center: center, radius: maxRadius * scale));
    
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.3 * opacity), 3.0, true);

    // 绘制白色圆点
    final Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(center, maxRadius * scale, paint);
  }
}