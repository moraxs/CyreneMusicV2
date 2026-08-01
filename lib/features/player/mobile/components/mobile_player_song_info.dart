import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import '../../../artist/artist_detail_page.dart';
import '../compat/player_service.dart';
import '../compat/player_background_service.dart';
import '../../../../domain/models/track.dart';
import '../compat/song_detail.dart';
import '../compat/toast_utils.dart';
import '../widgets/dynamic_cover_widget.dart';

/// 移动端播放器歌曲信息组件
/// 显示专辑封面、歌曲名称、艺术家等信息
class MobilePlayerSongInfo extends StatelessWidget {
  final bool showCover; // 是否显示封面（渐变模式下可能不显示）

  const MobilePlayerSongInfo({
    super.key,
    required this.showCover,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: PlayerService(),
      builder: (context, child) {
        final player = PlayerService();
        final song = player.currentSong;
        final track = player.currentTrack;
        final backgroundService = PlayerBackgroundService();
        final isGradientMode = backgroundService.enableGradient && 
                              backgroundService.backgroundType == PlayerBackgroundType.adaptive;
        
        return LayoutBuilder(
          builder: (context, constraints) {
            final screenHeight = constraints.maxHeight;
            
            if (isGradientMode) {
              // 渐变模式：封面在背景中，歌曲信息居中
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  _buildSongInfo(context, song, track),
                  const Spacer(),
                ],
              );
            } else {
              // 普通模式：显示封面和歌曲信息
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 封面
                  if (showCover) ...[
                    _buildAlbumCover(song, track),
                    SizedBox(height: screenHeight * 0.04),
                  ],
                  
                  // 歌曲信息
                  _buildSongInfo(context, song, track),
                ],
              );
            }
          },
        );
      },
    );
  }

  /// 构建专辑封面
  Widget _buildAlbumCover(SongDetail? song, Track? track) {
    final picUrl = song?.pic ?? track?.picUrl ?? '';
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据屏幕宽度自适应调整封面大小
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        
        // 动态计算边距：屏幕宽度的 12%
        final horizontalMargin = screenWidth * 0.12;
        
        // 优化封面大小计算：限制为屏幕高度的 28% 或宽度的 65%（取较小值）
        final maxCoverByHeight = screenHeight * 0.28;
        final maxCoverByWidth = screenWidth * 0.65;
        final maxCoverSize = maxCoverByHeight < maxCoverByWidth ? maxCoverByHeight : maxCoverByWidth;
        
        // 计算封面大小，确保 min 不大于 max
        final calculatedSize = screenWidth - horizontalMargin * 2;
        final minCoverSize = 180.0;
        final baseCoverSize = calculatedSize.clamp(minCoverSize, maxCoverSize > minCoverSize ? maxCoverSize : calculatedSize);
        
        // 缩小到原大小的 80%
        final coverSize = baseCoverSize * 0.8;
        
        return Hero(
          tag: 'album_cover',
          child: Center(
            child: Container(
              width: coverSize,
              height: coverSize,
              margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 20,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: picUrl.isNotEmpty
                    ? _buildOptimizedCover(picUrl, coverSize)
                    : Container(
                        color: Colors.grey[900],
                        child: Icon(
                          Icons.music_note,
                          size: coverSize * 0.3,
                          color: Colors.white30,
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建优化的封面图片，支持动态视频封面
  Widget _buildOptimizedCover(String imageUrl, double coverSize) {
    return DynamicCoverWidget(
      imageUrl: imageUrl,
      width: coverSize,
      height: coverSize,
      borderRadius: BorderRadius.circular(12),
    );
  }

  /// 构建歌曲信息
  Widget _buildSongInfo(BuildContext context, SongDetail? song, Track? track) {
    final name = song?.name ?? track?.name ?? '未知歌曲';
    final artistsStr = song?.arName ?? track?.artists ?? '未知艺术家';
    final album = song?.alName ?? track?.album ?? '';

    // 分割歌手（支持多种分隔符：/ , 、）
    final artists = _splitArtists(artistsStr);
    
    return ValueListenableBuilder<Color?>(
      valueListenable: PlayerService().themeColorNotifier,
      builder: (context, themeColor, child) {
        final titleColor = _getAdaptiveLyricColor(themeColor, true);
        final subtitleColor = _getAdaptiveLyricColor(themeColor, false);
        
        return LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = MediaQuery.of(context).size.width;
            final titleFontSize = (screenWidth * 0.055).clamp(20.0, 26.0);
            
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.08),
              child: Column(
                children: [
                  // 歌曲名称
                  Text(
                    name,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SimHei', // 黑体加粗
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: screenWidth * 0.02),
                  
                  // 艺术家（多个可点击）
                  _buildArtistsRow(context, artists, subtitleColor, screenWidth, song),
                  
                  // 专辑（可点击）
                  if (album.isNotEmpty) ...[
                    SizedBox(height: screenWidth * 0.015),
                    InkWell(
                      onTap: () => ToastUtils.info('请在首页搜索栏中搜索专辑'),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.album_outlined,
                              size: 12,
                              color: subtitleColor.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                album,
                                style: TextStyle(
                                  color: subtitleColor.withValues(alpha: 0.6),
                                  fontSize: (screenWidth * 0.032).clamp(12.0, 14.0),
                                  fontFamily: 'Microsoft YaHei', // 微软雅黑
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 构建多个艺术家的可点击行
  Widget _buildArtistsRow(BuildContext context, List<String> artists, Color baseColor, double screenWidth, SongDetail? song) {
    final artistFontSize = (screenWidth * 0.04).clamp(14.0, 17.0);
    
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 0,
      runSpacing: 4,
      children: artists.asMap().entries.map((entry) {
        final index = entry.key;
        final artist = entry.value;
        final isLast = index == artists.length - 1;
        
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => _onArtistTap(context, artist, song),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  artist,
                  style: TextStyle(
                    color: baseColor.withValues(alpha: 0.8),
                    fontSize: artistFontSize,
                    fontFamily: 'Microsoft YaHei', // 微软雅黑
                  ),
                ),
              ),
            ),
            if (!isLast)
              Text(
                ' / ',
                style: TextStyle(
                  color: baseColor.withValues(alpha: 0.6),
                  fontSize: artistFontSize,
                ),
              ),
          ],
        );
      }).toList(),
    );
  }

  Future<void> _onArtistTap(BuildContext context, String artistName, SongDetail? song) async {
    // 新版：统一跳转到应用内歌手详情页（页面内部自行按名字解析歌手）。
    final playback = PlayerService().playbackController;
    if (playback == null) return;
    Navigator.push(
      context,
      CupertinoPageRoute<void>(
        builder: (_) => ArtistDetailPage(playback: playback, artistName: artistName),
      ),
    );
  }

  /// 分割歌手字符串（支持多种分隔符）
  List<String> _splitArtists(String artistsStr) {
    // 支持的分隔符：/ , 、
    final separators = ['/', ',', '、'];
    
    for (final separator in separators) {
      if (artistsStr.contains(separator)) {
        return artistsStr
            .split(separator)
            .map((a) => a.trim())
            .where((a) => a.isNotEmpty)
            .toList();
      }
    }
    
    return [artistsStr];
  }

  /// 根据背景色亮度判断应该使用深色还是浅色文字
  /// 返回 true 表示背景亮，应该用深色文字；返回 false 表示背景暗，应该用浅色文字
  bool _shouldUseDarkText(Color backgroundColor) {
    // 计算颜色的相对亮度 (0.0 - 1.0)
    // 使用 W3C 推荐的计算公式
    final luminance = backgroundColor.computeLuminance();
    
    // 如果亮度大于 0.5，认为是亮色背景，应该用深色文字
    return luminance > 0.5;
  }

  /// 获取自适应的歌词颜色
  Color _getAdaptiveLyricColor(Color? themeColor, bool isCurrent) {
    final color = themeColor ?? Colors.grey[700]!;
    final useDarkText = _shouldUseDarkText(color);
    
    if (useDarkText) {
      // 亮色背景，使用深色文字
      return isCurrent 
          ? Colors.black87 
          : Colors.black54;
    } else {
      // 暗色背景，使用浅色文字
      return isCurrent 
          ? Colors.white 
          : Colors.white.withValues(alpha: 0.45);
    }
  }
}
