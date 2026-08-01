import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui'; // 导入 ImageFilter
import 'compat/player_service.dart';
import 'compat/lyric_style_service.dart';
import 'compat/lyric_line.dart';
import 'compat/lyric_parser.dart';
import 'components/mobile_player_fluid_cloud_lyric.dart';
import '../amll/amll_lyric_panel.dart';
import '../../../domain/models/media_url.dart';

/// 移动端全屏滚动歌词页面
class MobileLyricPage extends StatefulWidget {
  const MobileLyricPage({super.key});

  @override
  State<MobileLyricPage> createState() => _MobileLyricPageState();
}

class _MobileLyricPageState extends State<MobileLyricPage> {
  final ScrollController _scrollController = ScrollController();
  List<LyricLine> _lyrics = [];
  int _currentLyricIndex = -1;
  bool _showTranslation = true; // 是否显示译文
  String? _lastTrackId;
  bool _isUserScrolling = false; // 用户是否正在手动滚动
  
  @override
  void initState() {
    super.initState();
    
    // 监听播放器状态
    PlayerService().addListener(_onPlayerStateChanged);
    LyricStyleService().addListener(_onLyricStyleChanged);
    
    // 监听滚动
    _scrollController.addListener(_onScroll);
    
    // 延迟加载歌词
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentTrack = PlayerService().currentTrack;
      _lastTrackId = currentTrack != null 
          ? '${currentTrack.source.name}_${currentTrack.id}' 
          : null;
      _loadLyrics();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    PlayerService().removeListener(_onPlayerStateChanged);
    LyricStyleService().removeListener(_onLyricStyleChanged);
    super.dispose();
  }

  void _onLyricStyleChanged() {
    if (mounted) setState(() {});
  }

  /// 监听滚动
  void _onScroll() {
    // 检测用户是否开始手动滚动
    if (_scrollController.position.isScrollingNotifier.value) {
      _isUserScrolling = true;
      // 3秒后恢复自动滚动
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _isUserScrolling = false;
          });
        }
      });
    }
  }

  /// 播放器状态变化回调
  void _onPlayerStateChanged() {
    if (!mounted) return;
    
    final currentTrack = PlayerService().currentTrack;
    final currentTrackId = currentTrack != null 
        ? '${currentTrack.source.name}_${currentTrack.id}' 
        : null;
    
    // 检测歌曲切换
    if (currentTrackId != _lastTrackId) {
      _lastTrackId = currentTrackId;
      _loadLyrics();
    } else {
      // 只更新歌词高亮
      _updateCurrentLyric();
    }
  }

  /// 加载歌词
  Future<void> _loadLyrics() async {
    final currentSong = PlayerService().currentSong;
    if (currentSong == null) {
      if (mounted) {
        setState(() {
          _lyrics = [];
          _currentLyricIndex = -1;
        });
      }
      return;
    }

    try {
      final lyrics = LyricParser.parseNeteaseLyric(
        currentSong.lyric,
        translation: currentSong.tlyric.isNotEmpty ? currentSong.tlyric : null,
        yrcLyric: currentSong.yrc.isNotEmpty ? currentSong.yrc : null,
        yrcTranslation: currentSong.ytlrc.isNotEmpty ? currentSong.ytlrc : null,
      );
      if (mounted) {
        setState(() {
          _lyrics = lyrics;
          _currentLyricIndex = -1;
        });
        _updateCurrentLyric();
      }
    } catch (e) {
      debugPrint('❌ [MobileLyric] 歌词解析失败: $e');
      if (mounted) {
        setState(() {
          _lyrics = [];
          _currentLyricIndex = -1;
        });
      }
    }
  }

  /// 更新当前歌词
  void _updateCurrentLyric() {
    if (_lyrics.isEmpty) return;
    
    final newIndex = LyricParser.findCurrentLineIndex(
      _lyrics,
      PlayerService().position,
    );

    if (newIndex != _currentLyricIndex && newIndex >= 0 && mounted) {
      setState(() {
        _currentLyricIndex = newIndex;
      });
      
      // 自动滚动到当前歌词（仅当用户未手动滚动时）
      if (!_isUserScrolling && _scrollController.hasClients) {
        _scrollToCurrentLyric();
      }
    }
  }

  /// 滚动到当前歌词
  void _scrollToCurrentLyric() {
    if (_currentLyricIndex < 0 || _currentLyricIndex >= _lyrics.length) {
      return;
    }
    
    // 计算目标位置（让当前歌词居中）
    final screenHeight = MediaQuery.of(context).size.height;
    // 根据屏幕大小和是否显示译文动态调整行高
    final baseHeight = _showTranslation ? 72.0 : 52.0;
    final itemHeight = (screenHeight * 0.08).clamp(baseHeight, baseHeight + 20.0);
    final targetOffset = _currentLyricIndex * itemHeight - screenHeight / 2 + itemHeight / 2;
    
    _scrollController.animateTo(
      targetOffset.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// 判断是否应该显示译文按钮
  bool _shouldShowTranslationButton() {
    if (_lyrics.isEmpty) return false;
    
    // 检查是否有翻译
    final hasTranslation = _lyrics.any((lyric) => 
      lyric.translation != null && lyric.translation!.isNotEmpty
    );
    
    if (!hasTranslation) return false;
    
    // 检查原文是否为中文（检查前5行非空歌词）
    final sampleLyrics = _lyrics
        .where((lyric) => lyric.text.trim().isNotEmpty)
        .take(5)
        .map((lyric) => lyric.text)
        .join('');
    
    if (sampleLyrics.isEmpty) return false;
    
    // 计算中文字符占比
    final chineseCharCount = sampleLyrics.runes.where((rune) {
      return (rune >= 0x4E00 && rune <= 0x9FFF) || // CJK统一汉字
             (rune >= 0x3400 && rune <= 0x4DBF) || // CJK扩展A
             (rune >= 0x20000 && rune <= 0x2A6DF); // CJK扩展B
    }).length;
    
    final chineseRatio = chineseCharCount / sampleLyrics.length;
    
    // 如果中文字符占比小于30%，认为是非中文歌词
    return chineseRatio < 0.3;
  }

  @override
  Widget build(BuildContext context) {
    final player = PlayerService();
    final song = player.currentSong;
    final track = player.currentTrack;
    final picUrl = song?.pic ?? track?.picUrl ?? '';

    // 歌词页面始终使用深色背景，状态栏图标应为浅色
    const lyricOverlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: lyricOverlayStyle,
      child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 背景（模糊的专辑封面）
          if (picUrl.isNotEmpty)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: picUrl,
                httpHeaders: imageHeaders(picUrl),
                fit: BoxFit.cover,
                // 重模糊背景(sigma 50)，小尺寸解码视觉等价
                memCacheWidth: coverDecodeWidth(
                  200,
                  MediaQuery.devicePixelRatioOf(context),
                ),
                imageBuilder: (context, imageProvider) => Container(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: imageProvider,
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ),
          
          // 歌词内容
          SafeArea(
            child: Column(
              children: [
                // 顶部控制栏
                _buildTopBar(context),
                
                // 歌词列表
                Expanded(
                  child: _lyrics.isEmpty
                      ? const Center(
                          child: Text(
                            '暂无歌词',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        )
                      : _buildLyricList(),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  /// 构建歌词列表（支持流体云切换）
  Widget _buildLyricList() {
    final style = LyricStyleService().currentStyle;

    // Apple Music 样式
    if (style == LyricStyle.amll) {
      return AmllLyricPanel(
        lyrics: _lyrics,
        showTranslation: _showTranslation && _shouldShowTranslationButton(),
      );
    }

    // 流体云样式
    if (style == LyricStyle.fluidCloud) {
      return MobilePlayerFluidCloudLyric(
        lyrics: _lyrics,
        currentLyricIndex: _currentLyricIndex,
        showTranslation: _showTranslation && _shouldShowTranslationButton(),
        // 注意：全屏页可能不需要额外的点击回调，或者可以根据需求添加
      );
    }

    // 默认滚动样式
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        vertical: 100,
        horizontal: 24,
      ),
      itemCount: _lyrics.length,
      itemBuilder: (context, index) {
        return _buildLyricItem(_lyrics[index], index);
      },
    );
  }

  /// 构建顶部控制栏
  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
            iconSize: 32,
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            '歌词',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          // 译文开关按钮（仅在有译文时显示）
          _shouldShowTranslationButton()
              ? IconButton(
                  icon: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: _showTranslation 
                          ? Colors.white.withValues(alpha: 0.2) 
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Center(
                      child: Text(
                        '译',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Microsoft YaHei',
                        ),
                      ),
                    ),
                  ),
                  onPressed: () {
                    setState(() {
                      _showTranslation = !_showTranslation;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_showTranslation ? '已显示译文' : '已隐藏译文'),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                )
              : const SizedBox(width: 48), // 占位，保持布局平衡
        ],
      ),
    );
  }

  /// 构建歌词项
  Widget _buildLyricItem(LyricLine lyric, int index) {
    final isCurrent = index == _currentLyricIndex;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据屏幕宽度自适应字体大小
        final screenWidth = MediaQuery.of(context).size.width;
        final currentFontSize = (screenWidth * 0.045).clamp(16.0, 20.0);
        final normalFontSize = (screenWidth * 0.038).clamp(14.0, 16.0);
        final translationCurrentSize = (screenWidth * 0.035).clamp(13.0, 15.0);
        final translationNormalSize = (screenWidth * 0.032).clamp(12.0, 14.0);
        
        return AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            color: isCurrent ? Colors.white : Colors.white.withValues(alpha: 0.5),
            fontSize: isCurrent ? currentFontSize : normalFontSize,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            height: 1.6,
            fontFamily: 'Microsoft YaHei',
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: (screenWidth * 0.02).clamp(6.0, 10.0),
              horizontal: (screenWidth * 0.05).clamp(16.0, 24.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 原文歌词
                Text(
                  lyric.text.isEmpty ? '♪' : lyric.text,
                  textAlign: TextAlign.center,
                ),
                // 翻译歌词
                if (_showTranslation && 
                    lyric.translation != null && 
                    lyric.translation!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      lyric.translation!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isCurrent
                            ? Colors.white.withValues(alpha: 0.8)
                            : Colors.white.withValues(alpha: 0.4),
                        fontSize: isCurrent ? translationCurrentSize : translationNormalSize,
                        fontFamily: 'Microsoft YaHei',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

