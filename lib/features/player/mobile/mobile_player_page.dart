import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'compat/player_service.dart';
import 'compat/lyric_line.dart';
import 'compat/song_detail.dart';
import 'compat/lyric_parser.dart';
import 'components/mobile_player_background.dart';
import 'components/mobile_player_control_center.dart';
import 'components/mobile_player_fluid_cloud_layout.dart';
import 'components/mobile_player_classic_layout.dart';
import 'components/mobile_player_dialogs.dart';
import 'compat/lyric_style_service.dart';
import '../../../application/audio_sources/audio_source_preferences_controller.dart';
import '../../../application/auth/account_session_controller.dart';
import '../../../application/playback/playback_controller.dart';
import '../../../domain/models/track.dart';

/// 移动端播放器页面（重构版本）
/// 适用于 Android/iOS，现在使用组件化架构
class MobilePlayerPage extends StatefulWidget {
  const MobilePlayerPage({
    super.key,
    required this.playback,
    required this.audioSources,
    required this.account,
  });

  final PlaybackController playback;
  final AudioSourcePreferencesController audioSources;
  final AccountSessionController account;

  @override
  State<MobilePlayerPage> createState() => _MobilePlayerPageState();
}

class _MobilePlayerPageState extends State<MobilePlayerPage> with TickerProviderStateMixin {
  // 歌词相关
  List<LyricLine> _lyrics = [];
  int _currentLyricIndex = -1;
  String? _lastTrackId;
  // 记录上一次处理时的 Track 实例。切歌会先把无歌词的原始 Track 设为
  // currentTrack，音源解析完成后再替换为带歌词的同 id 新实例；用实例一致性
  // 才能捕获到这第二次替换并重载歌词（仅按 id 判断会漏掉，导致「暂无歌词」）。
  Track? _lastTrack;
  
  // 控制中心
  bool _showControlCenter = false;
  AnimationController? _controlCenterAnimationController;
  Animation<double>? _controlCenterFadeAnimation;

  @override
  void initState() {
    super.initState();
    // 兼容层绑定：原版组件全部通过 PlayerService() 等单例访问播放状态。
    PlayerService().bind(
      widget.playback,
      accountController: widget.account,
      audioSourcesController: widget.audioSources,
    );
    _initializeAnimations();
    _setupListeners();
    _initializeData();
    // 初始检查：如果当前已经是沉浸模式，强制横屏
    _checkAndForceOrientation();
  }

  /// 根据当前歌词样式检查并强制设置屏幕方向
  void _checkAndForceOrientation() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    
    // 沉浸模式暂未移植：统一走竖屏流体云渲染，不强制横屏。
    // 恢复系统默认（跟随重力感应或恢复到原本的设置，这里设为所有方向以解除锁定）
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // 恢复状态栏和虚拟按键显示
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  /// 恢复到默认竖屏（用于关闭播放器时）
  void _resetOrientation() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    debugPrint('📱 [MobilePlayerPage] 离开播放页，恢复默认方向');
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // 确保退出时恢复状态栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    _resetOrientation();
    _disposeAnimations();
    _removeListeners();
    super.dispose();
  }

  /// 初始化动画控制器
  void _initializeAnimations() {
    _controlCenterAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _controlCenterFadeAnimation = CurvedAnimation(
      parent: _controlCenterAnimationController!,
      curve: Curves.easeInOut,
    );
  }

  /// 设置监听器
  void _setupListeners() {
    PlayerService().addListener(_onPlayerStateChanged);
    PlayerService().positionNotifier.addListener(_onPositionChanged);
    LyricStyleService().addListener(_onLyricStyleChanged);
  }

  /// 移除监听器
  void _removeListeners() {
    PlayerService().removeListener(_onPlayerStateChanged);
    PlayerService().positionNotifier.removeListener(_onPositionChanged);
    LyricStyleService().removeListener(_onLyricStyleChanged);
  }

  void _onLyricStyleChanged() {
    if (mounted) {
      _checkAndForceOrientation();
      setState(() {});
    }
  }

  /// 释放动画控制器
  void _disposeAnimations() {
    _controlCenterAnimationController?.dispose();
  }

  /// 初始化数据
  void _initializeData() {
    // 延迟加载歌词，让路由动画先完成 (300ms 动画 + 50ms 缓冲)
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final currentTrack = PlayerService().currentTrack;
      _lastTrackId = currentTrack != null
          ? '${currentTrack.source.name}_${currentTrack.id}'
          : null;
      _lastTrack = currentTrack;
      _loadLyrics();
    });
  }

  /// 播放器状态变化回调（与桌面端保持一致的逻辑）
  void _onPlayerStateChanged() {
    if (!mounted) return;

    final currentTrack = PlayerService().currentTrack;
    final currentTrackId = currentTrack != null
        ? '${currentTrack.source.name}_${currentTrack.id}'
        : null;

    // 切歌时 PlaybackController.playTrack 会两阶段发布：先把无歌词的原始
    // Track 设为 currentTrack，音源解析完成后再替换为带 lyrics 的同 id 新
    // 实例。仅按 id 判断会漏掉第二次替换，导致切歌后歌词一直停在「暂无歌词」；
    // 这里额外用实例一致性捕获解析完成的那次替换，在尚未加载到歌词时重载。
    final trackChanged = currentTrackId != _lastTrackId;
    final instanceReplaced = !identical(currentTrack, _lastTrack);

    if (trackChanged) {
      // 歌曲已切换，重新加载歌词
      debugPrint('🎵 [MobilePlayerPage] 检测到歌曲切换，重新加载歌词');
      debugPrint('   上一首ID: $_lastTrackId');
      debugPrint('   当前ID: $currentTrackId');

      _lastTrackId = currentTrackId;
      _lastTrack = currentTrack;
      _lyrics = [];
      _currentLyricIndex = -1;
      _loadLyrics();
      setState(() {}); // 触发重建以更新UI
    } else if (instanceReplaced && _lyrics.isEmpty) {
      // 同一首歌、Track 实例被替换（音源解析完成、歌词就位）：尚未加载到歌词则重载
      _lastTrack = currentTrack;
      debugPrint('🎵 [MobilePlayerPage] 检测到音源解析完成，重新加载歌词');
      _loadLyrics();
      setState(() {});
    } else {
      // 这里的全局通知不再包含进度变化，主要是为了捕获除了切歌以外的状态变更（如暂停/恢复）
      if (mounted) setState(() {});
    }
  }

  /// 进度变化回调（高频，仅由 positionNotifier 触发）
  void _onPositionChanged() {
    if (!mounted) return;
    _updateCurrentLyric();
  }

  /// 加载歌词（异步执行，不阻塞 UI）
  Future<void> _loadLyrics() async {
    final currentTrack = PlayerService().currentTrack;
    if (currentTrack == null) return;

    debugPrint('🔍 [MobilePlayerPage] 开始加载歌词，当前 Track: ${currentTrack.name}');
    debugPrint('   Track ID: ${currentTrack.id} (类型: ${currentTrack.id.runtimeType})');

    // 等待 currentSong 更新（最多等待3秒）
    SongDetail? song;
    final startTime = DateTime.now();
    int attemptCount = 0;

    // 若 currentTrack 已携带歌词（音源解析完成后进入），直接解析，避免轮询。
    // 进入此分支可跳过下方 currentSong 的 id 匹配等待（两者同源，songId 必等于 trackId）。
    if (currentTrack.lyric != null && currentTrack.lyric!.isNotEmpty) {
      song = SongDetail.fromTrack(currentTrack);
    }

    while (song == null && DateTime.now().difference(startTime).inSeconds < 3) {
      song = PlayerService().currentSong;
      attemptCount++;

      // 验证 currentSong 是否匹配 currentTrack
      if (song != null) {
        final songId = song.id.toString();
        final trackId = currentTrack.id.toString();

        if (attemptCount == 1) {
          debugPrint('🔍 [MobilePlayerPage] 找到 currentSong: ${song.name}');
          debugPrint('   Song ID: ${song.id} (类型: ${song.id.runtimeType})');
          debugPrint('   Track ID: ${currentTrack.id} (类型: ${currentTrack.id.runtimeType})');
          debugPrint('   ID 匹配: ${songId == trackId}');
        }

        // 如果 ID 不匹配，说明 currentSong 还没更新
        if (songId != trackId) {
          if (attemptCount <= 3) {
            debugPrint('⚠️ [MobilePlayerPage] ID 不匹配！Song ID: "$songId" vs Track ID: "$trackId"');
          }
          song = null;
          await Future.delayed(const Duration(milliseconds: 100));
        }
      } else {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    // 取解析期间最新的 currentTrack，避免在轮询窗口内切歌后仍解析旧曲。
    // 以 Track.key 为准：key 一致即同一逻辑歌曲，可直接用其（可能已更新的）歌词。
    final latestTrack = PlayerService().currentTrack;
    if (latestTrack != null && latestTrack.key != currentTrack.key) {
      debugPrint('🔄 [MobilePlayerPage] 加载期间切歌，放弃本次解析');
      return;
    }
    // 同一曲若已带上歌词，优先用 Track 自带歌词，避免缓存命中的旧 currentSong。
    final songDetail = (latestTrack != null &&
            latestTrack.lyric != null &&
            latestTrack.lyric!.isNotEmpty)
        ? SongDetail.fromTrack(latestTrack)
        : song;
    if (songDetail == null) {
      debugPrint('❌ [MobilePlayerPage] 等待歌曲详情超时！');
      debugPrint('   尝试次数: $attemptCount');
      debugPrint('   Track: ${currentTrack.name} (ID: ${currentTrack.id})');
      final currentSong = PlayerService().currentSong;
      if (currentSong != null) {
        debugPrint('   CurrentSong 存在但 ID 不匹配: ${currentSong.name} (ID: ${currentSong.id})');
      } else {
        debugPrint('   CurrentSong 为 null');
      }
      return;
    }

    try {
      debugPrint('📝 [MobilePlayerPage] 开始解析歌词');
      debugPrint('   歌曲名: ${songDetail.name}');
      debugPrint('   歌曲ID: ${songDetail.id}');
      debugPrint('   原始歌词长度: ${songDetail.lyric.length} 字符');
      debugPrint('   翻译长度: ${songDetail.tlyric.length} 字符');
      
      // 关键诊断：检查歌词内容
      if (songDetail.lyric.isEmpty) {
        debugPrint('   ❌ 错误：MobilePlayerPage 读取到的 currentSong.lyric 为空！');
        debugPrint('   这说明 PlayerService.currentSong 中的歌词确实是空的');
      } else {
        debugPrint('   ✅ MobilePlayerPage 成功读取到歌词数据');
        debugPrint('   歌词预览: ${songDetail.lyric.substring(0, songDetail.lyric.length > 50 ? 50 : songDetail.lyric.length)}...');
      }
      
      // 使用 Future.microtask 确保异步执行
      await Future.microtask(() {
        // 根据音乐来源选择不同的解析器
        switch (songDetail.source.name) {
          case 'netease':
            _lyrics = LyricParser.parseNeteaseLyric(
              songDetail.lyric,
              translation: songDetail.tlyric.isNotEmpty ? songDetail.tlyric : null,
              yrcLyric: songDetail.yrc.isNotEmpty ? songDetail.yrc : null,
              yrcTranslation: songDetail.ytlrc.isNotEmpty ? songDetail.ytlrc : null,
            );
            break;
          case 'qq':
            _lyrics = LyricParser.parseQQLyric(
              songDetail.lyric,
              translation: songDetail.tlyric.isNotEmpty ? songDetail.tlyric : null,
              qrcLyric: songDetail.qrc.isNotEmpty ? songDetail.qrc : null,
              qrcTranslation: songDetail.qrcTrans.isNotEmpty ? songDetail.qrcTrans : null,
            );
            break;
          case 'kugou':
            _lyrics = LyricParser.parseKugouLyric(
              songDetail.lyric,
              translation: songDetail.tlyric.isNotEmpty ? songDetail.tlyric : null,
            );
            break;
          default:
            // 默认使用网易云/标准 LRC 格式解析（适用于酷我等）
            _lyrics = LyricParser.parseNeteaseLyric(
              songDetail.lyric,
              translation: songDetail.tlyric.isNotEmpty ? songDetail.tlyric : null,
              yrcLyric: songDetail.yrc.isNotEmpty ? songDetail.yrc : null,
              yrcTranslation: songDetail.ytlrc.isNotEmpty ? songDetail.ytlrc : null,
            );
            break;
        }
      });

      if (_lyrics.isEmpty && songDetail.lyric.isNotEmpty) {
        debugPrint('⚠️ [MobilePlayerPage] 歌词解析结果为空，但原始歌词不为空！');
        debugPrint('   原始歌词前100字符: ${songDetail.lyric.substring(0, songDetail.lyric.length > 100 ? 100 : songDetail.lyric.length)}');
      }

      debugPrint('🎵 [MobilePlayerPage] 加载歌词: ${_lyrics.length} 行 (${songDetail.name})');
      
      // 加载歌词后，更新并滚动到当前位置
      if (_lyrics.isNotEmpty && mounted) {
        setState(() {
          _updateCurrentLyric();
        });
      }
    } catch (e) {
      debugPrint('❌ [MobilePlayerPage] 加载歌词失败: $e');
      debugPrint('   Stack trace: ${StackTrace.current}');
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
    }
  }

  /// 强制刷新歌词（用于调试）
  /// 切换控制中心显示状态
  void _toggleControlCenter() {
    setState(() {
      _showControlCenter = !_showControlCenter;
      if (_showControlCenter) {
        _controlCenterAnimationController?.forward();
      } else {
        _controlCenterAnimationController?.reverse();
      }
    });
  }

  /// 构建流体云全屏布局（动态背景模式）
  /// 使用新的 MobilePlayerFluidCloudLayout，不再需要二级歌词页面
  Widget _buildAppleMusicStyleLayout(BuildContext context, BoxConstraints constraints) {
    return MobilePlayerFluidCloudLayout(
      lyrics: _lyrics,
      currentLyricIndex: _currentLyricIndex,
      showTranslation: true,
      onBackPressed: () => Navigator.pop(context),
      onPlaylistPressed: () => MobilePlayerDialogs.showPlaylistBottomSheet(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = PlayerService();
    final song = player.currentSong;
    final track = player.currentTrack;

    // 播放器页面始终使用深色背景，状态栏和导航栏透明，图标为浅色
    const playerOverlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    );

    if (song == null && track == null) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: playerOverlayStyle,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            systemOverlayStyle: playerOverlayStyle,
          ),
          body: const Center(
            child: Text(
              '暂无播放内容',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ),
        ),
      );
    }

    // 构建主要内容
    final lyricStyleService = LyricStyleService();
    // 流体云布局条件：全屏播放器样式设置为流体云（沉浸样式未移植，同样走流体云）
    // AMLL 样式复用流体云的整体布局，只替换歌词面板本身
    final useFluidCloudLayout =
        lyricStyleService.currentStyle == LyricStyle.fluidCloud ||
        lyricStyleService.currentStyle == LyricStyle.immersive ||
        lyricStyleService.currentStyle == LyricStyle.amll;

    // 动态处理状态栏：流体云样式下的横屏隐藏状态栏
    const isImmersive = false;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    if (isImmersive || (useFluidCloudLayout && isLandscape)) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    final scaffoldWidget = AnnotatedRegion<SystemUiOverlayStyle>(
      value: playerOverlayStyle,
      child: Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
            children: [
              // 流体云布局模式：完全接管背景和 Safe Area（手机形态）
              if (useFluidCloudLayout)
                _buildAppleMusicStyleLayout(context, const BoxConstraints())
              else ...[
                // 标准布局模式：原有背景 + Safe Area
                const MobilePlayerBackground(),
                SafeArea(
                  child: MobilePlayerClassicLayout(
                    lyrics: _lyrics,
                    currentLyricIndex: _currentLyricIndex,
                    onBackPressed: () => Navigator.pop(context),
                    onPlaylistPressed: () => MobilePlayerDialogs.showPlaylistBottomSheet(context),
                  ),
                ),
              ],

          // 控制中心面板
          MobilePlayerControlCenter(
            isVisible: _showControlCenter,
            fadeAnimation: _controlCenterFadeAnimation,
            onClose: _toggleControlCenter,
          ),
        ],
      ),
      ),
    );
    
    // Windows 平台：添加圆角边框
    if (Platform.isWindows) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: scaffoldWidget,
      );
    }
    
    return scaffoldWidget;
  }
}
