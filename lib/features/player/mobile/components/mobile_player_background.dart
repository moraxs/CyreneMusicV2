import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../compat/player_service.dart';
import '../compat/player_background_service.dart';
import '../compat/lyric_style_service.dart';
import '../compat/color_extraction_service.dart';
import '../../../../domain/models/track.dart';
import '../compat/song_detail.dart';
import '../widgets/video_background_player.dart';
import '../compat/image_utils.dart';
import '../../super_cyrene/super_cyrene_amll_background.dart';

/// 主题色缓存管理器（移动端）
/// 现在使用 ColorExtractionService 的缓存
class _MobileThemeColorCache {
  static final _MobileThemeColorCache _instance =
      _MobileThemeColorCache._internal();
  factory _MobileThemeColorCache() => _instance;
  _MobileThemeColorCache._internal();

  Color? getColor(String imageUrl) {
    final result = ColorExtractionService().getCachedColors(imageUrl);
    return result?.themeColor;
  }
}

/// 移动端播放器背景组件
/// 根据设置显示不同类型的背景（自适应、纯色、图片、视频、动态）
/// 动态模式复用 SuperCyrene 同款 AMLL 专辑纹理背景。
class MobilePlayerBackground extends StatefulWidget {
  final double dragOffset;
  final bool isolateRepaints;

  const MobilePlayerBackground({
    super.key,
    this.dragOffset = 0.0,
    this.isolateRepaints = true,
  });

  @override
  State<MobilePlayerBackground> createState() => _MobilePlayerBackgroundState();
}

class _MobilePlayerBackgroundState extends State<MobilePlayerBackground> {
  bool _isFirstBuild = true;

  // 主题色提取相关
  String? _currentThemeColorImageUrl;
  int _pendingThemeColorExtractionId = 0;
  String? _lastScheduledThemeColorImageUrl;

  @override
  void initState() {
    super.initState();
    PlayerBackgroundService().addListener(_onBackgroundChanged);
    PlayerService().addListener(_onPlayerServiceChanged);
  }

  @override
  void dispose() {
    PlayerBackgroundService().removeListener(_onBackgroundChanged);
    PlayerService().removeListener(_onPlayerServiceChanged);
    super.dispose();
  }

  void _onPlayerServiceChanged() {
    if (!mounted) return;

    final backgroundType = PlayerBackgroundService().backgroundType;

    // 自适应背景需要提取主题色
    if (backgroundType == PlayerBackgroundType.adaptive) {
      _scheduleThemeColorExtraction();
    }
  }

  void _onBackgroundChanged() {
    if (!mounted) return;

    setState(() {});

    final backgroundType = PlayerBackgroundService().backgroundType;
    if (backgroundType == PlayerBackgroundType.adaptive) {
      _scheduleThemeColorExtraction();
    }
  }

  /// 延迟调度主题色提取（带防抖）
  void _scheduleThemeColorExtraction() {
    final backgroundService = PlayerBackgroundService();
    if (backgroundService.backgroundType != PlayerBackgroundType.adaptive) {
      return;
    }

    final song = PlayerService().currentSong;
    final track = PlayerService().currentTrack;
    final imageUrl = song?.pic ?? track?.picUrl ?? '';

    if (imageUrl.isEmpty || imageUrl == _currentThemeColorImageUrl) return;
    if (imageUrl == _lastScheduledThemeColorImageUrl) return;

    _lastScheduledThemeColorImageUrl = imageUrl;

    // 检查缓存
    final cachedColor = _MobileThemeColorCache().getColor(imageUrl);
    if (cachedColor != null) {
      _currentThemeColorImageUrl = imageUrl;
      PlayerService().themeColorNotifier.value = cachedColor;
      return;
    }

    _pendingThemeColorExtractionId++;
    final currentId = _pendingThemeColorExtractionId;

    Future.delayed(const Duration(milliseconds: 200), () {
      if (currentId != _pendingThemeColorExtractionId || !mounted) return;
      _extractThemeColorFromImage(imageUrl);
    });
  }

  /// 从图片中提取主题色（使用 isolate，不阻塞主线程）
  Future<void> _extractThemeColorFromImage(String imageUrl) async {
    // 检查缓存
    final cachedColor = _MobileThemeColorCache().getColor(imageUrl);
    if (cachedColor != null) {
      _currentThemeColorImageUrl = imageUrl;
      PlayerService().themeColorNotifier.value = cachedColor;
      return;
    }

    _currentThemeColorImageUrl = imageUrl;

    try {
      // 使用 ColorExtractionService 在 isolate 中提取颜色
      final result = await ColorExtractionService().extractColorsFromUrl(
        imageUrl,
        sampleSize: 64,
        timeout: const Duration(seconds: 3),
      );

      if (result != null && result.themeColor != null) {
        PlayerService().themeColorNotifier.value = result.themeColor;
        debugPrint('✅ [移动端背景] 主题色提取成功: ${result.themeColor}');
      } else {
        debugPrint('⚠️ [移动端背景] 无法提取主题色，使用默认色');
      }
    } catch (e) {
      debugPrint('⚠️ [移动端背景] 主题色提取失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isFirstBuild) {
      _isFirstBuild = false;
      // 延迟首次颜色提取，让路由动画先完成 (300ms + 100ms 缓冲)
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        final backgroundType = PlayerBackgroundService().backgroundType;
        if (backgroundType == PlayerBackgroundType.adaptive) {
          _scheduleThemeColorExtraction();
        }
      });
    }
    final background = _buildBackground();
    return widget.isolateRepaints
        ? RepaintBoundary(child: background)
        : background;
  }

  /// 构建背景
  Widget _buildBackground() {
    final backgroundService = PlayerBackgroundService();
    final player = PlayerService();
    final song = player.currentSong;
    final track = player.currentTrack;

    // 检查是否为流体云样式（AMLL 样式共用同一套背景表现）
    final currentStyle = LyricStyleService().currentStyle;
    final isFluidCloud =
        currentStyle == LyricStyle.fluidCloud ||
        currentStyle == LyricStyle.amll;

    switch (backgroundService.backgroundType) {
      case PlayerBackgroundType.adaptive:
        // 自适应背景
        // 流体云样式下：封面顶部+向下渐变到主题色+整体模糊
        // 非流体云样式：根据 enableGradient 开关决定
        if (isFluidCloud) {
          return _buildFluidCloudAdaptiveBackground(song, track);
        } else if (backgroundService.enableGradient) {
          return _buildCoverGradientBackground(song, track);
        } else {
          return _buildColorGradientBackground();
        }

      case PlayerBackgroundType.dynamic:
        // 动态背景 - 使用 SuperCyrene 同款 AMLL 专辑纹理背景（旋转/轨道多层，
        // 覆盖原来几乎纯色的 Mesh Gradient，视觉更丰富）。
        return _buildAmllBackground(song, track);

      case PlayerBackgroundType.solidColor:
        // 纯色背景
        return _buildSolidColorBackground(backgroundService);

      case PlayerBackgroundType.image:
        // 图片背景
        return _buildImageBackground(backgroundService);

      case PlayerBackgroundType.video:
        // 视频背景
        return _buildVideoBackground(backgroundService);
    }
  }

  /// 构建 SuperCyrene 同款 AMLL 动态背景。
  ///
  /// 复用 [SuperCyreneAmllBackground]：对专辑封面做一次模糊 + 色彩校正，
  /// 然后以多层旋转/轨道动画合成，替代旧 Mesh Gradient 的近似纯色效果。
  /// 播放状态由 [PlayerService.isPlaying] 驱动动画启停。
  Widget _buildAmllBackground(SongDetail? song, Track? track) {
    final player = PlayerService();
    final imageUrl = song?.pic ?? track?.picUrl;

    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final provider =
            PlayerService().currentCoverImageProvider ??
            _coverProviderFor(imageUrl);
        return SuperCyreneAmllBackground(
          imageProvider: provider,
          isPlaying: PlayerService().isPlaying,
        );
      },
    );
  }

  /// 从封面 URL 构建 ImageProvider（本地 data URI / 文件 / 网络三态兼容）。
  ImageProvider? _coverProviderFor(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return null;
    if (isDataUriImage(imageUrl)) {
      final bytes = decodeDataUriImage(imageUrl);
      if (bytes == null) return null;
      return MemoryImage(bytes);
    }
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return CachedNetworkImageProvider(
        imageUrl,
        headers: getImageHeaders(imageUrl),
      );
    }
    return FileImage(File(imageUrl));
  }

  /// 构建流体云样式下的自适应背景
  /// 封面位于顶部，向下渐变到主题色，整体覆盖一层模糊
  Widget _buildFluidCloudAdaptiveBackground(SongDetail? song, Track? track) {
    // 使用 ListenableBuilder 监听 PlayerService，确保歌曲切换时封面也会更新
    return ListenableBuilder(
      listenable: PlayerService(),
      builder: (context, _) {
        final currentSong = PlayerService().currentSong;
        final currentTrack = PlayerService().currentTrack;
        final imageUrl = currentSong?.pic ?? currentTrack?.picUrl ?? '';

        // 如果图片URL变化，触发主题色提取
        if (imageUrl.isNotEmpty && imageUrl != _currentThemeColorImageUrl) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _scheduleThemeColorExtraction();
          });
        }

        return ValueListenableBuilder<Color?>(
          valueListenable: PlayerService().themeColorNotifier,
          builder: (context, themeColor, child) {
            final color = themeColor ?? Colors.grey[700]!;

            final background = Stack(
              children: [
                // 底层纯主题色背景
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    color: color,
                  ),
                ),

                // 专辑封面层 - 等比例放大至占满宽度，位于顶部，带渐变融合效果
                if (imageUrl.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: Stack(
                        children: [
                          // 封面图片（支持网络 URL 和本地文件）
                          _buildCoverImage(imageUrl),
                          // 封面底部渐变遮罩
                          Positioned.fill(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 500),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.transparent,
                                    color.withValues(alpha: 0.05),
                                    color.withValues(alpha: 0.12),
                                    color.withValues(alpha: 0.25),
                                    color.withValues(alpha: 0.45),
                                    color.withValues(alpha: 0.65),
                                    color.withValues(alpha: 0.85),
                                    color,
                                  ],
                                  stops: const [
                                    0.0,
                                    0.25,
                                    0.35,
                                    0.45,
                                    0.55,
                                    0.65,
                                    0.75,
                                    0.90,
                                    1.0,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 整体模糊层 (始终保持固定模糊度)
                // ✅ 性能优化：限制模糊半径最大值为 30，避免 GPU 过载
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 25.0, sigmaY: 25.0),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.1),
                    ),
                  ),
                ),
              ],
            );
            return widget.isolateRepaints
                ? RepaintBoundary(child: background)
                : background;
          },
        );
      },
    );
  }

  /// 构建封面渐变背景（新样式：移动端顶部封面，向下渐变）
  Widget _buildCoverGradientBackground(SongDetail? song, Track? track) {
    // 使用 ListenableBuilder 监听 PlayerService，确保歌曲切换时封面也会更新
    return ListenableBuilder(
      listenable: PlayerService(),
      builder: (context, _) {
        final currentSong = PlayerService().currentSong;
        final currentTrack = PlayerService().currentTrack;
        final imageUrl = currentSong?.pic ?? currentTrack?.picUrl ?? '';

        // 如果图片URL变化，触发主题色提取
        if (imageUrl.isNotEmpty && imageUrl != _currentThemeColorImageUrl) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _scheduleThemeColorExtraction();
          });
        }

        return ValueListenableBuilder<Color?>(
          valueListenable: PlayerService().themeColorNotifier,
          builder: (context, themeColor, child) {
            // 确保总是有颜色显示，优先使用提取的主题色，回退到深紫色
            final color = themeColor ?? Colors.grey[700]!;

            return Stack(
              children: [
                // 底层纯主题色背景
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    color: color, // 整个背景使用主题色
                  ),
                ),

                // 专辑封面层 - 等比例放大至占满宽度，位于顶部，带渐变融合效果
                if (imageUrl.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: AspectRatio(
                      aspectRatio: 1.0, // 保持正方形比例
                      child: Stack(
                        children: [
                          // 封面图片（支持网络 URL 和本地文件）
                          _buildCoverImage(imageUrl),
                          // 封面底部渐变遮罩 - 提前开始渐变，避免突兀过渡
                          Positioned.fill(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 500),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent, // 顶部完全透明，显示原封面
                                    Colors.transparent, // 上1/4保持透明
                                    color.withValues(alpha: 0.05), // 提前开始轻微融合
                                    color.withValues(alpha: 0.12), // 渐进增加透明度
                                    color.withValues(alpha: 0.25), // 四分之一透明度
                                    color.withValues(alpha: 0.45), // 接近一半透明度
                                    color.withValues(alpha: 0.65), // 较强融合
                                    color.withValues(alpha: 0.85), // 非常强的融合
                                    color, // 最底部完全融入主题色
                                  ],
                                  stops: const [
                                    0.0,
                                    0.25,
                                    0.35,
                                    0.45,
                                    0.55,
                                    0.65,
                                    0.75,
                                    0.90,
                                    1.0,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  /// 构建颜色渐变背景（原有样式）
  Widget _buildColorGradientBackground() {
    return ValueListenableBuilder<Color?>(
      valueListenable: PlayerService().themeColorNotifier,
      builder: (context, themeColor, child) {
        // 使用提取的主题色，回退到深紫色
        final color = themeColor ?? Colors.grey[700]!;

        return Stack(
          children: [
            // 底层纯黑背景，确保不透明
            Container(color: Colors.black),
            // 上层渐变
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    color.withValues(alpha: 0.3),
                    Colors.black,
                    Colors.black,
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 构建封面图片（支持网络 URL、本地文件路径和内嵌 data URI）
  Widget _buildCoverImage(String imageUrl) {
    // 本地音轨的内嵌封面（data:image/...;base64）需解码为字节渲染。
    if (isDataUriImage(imageUrl)) {
      final bytes = decodeDataUriImage(imageUrl);
      if (bytes != null) {
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              Container(color: Colors.grey[900]),
        );
      }
    }

    // 判断是网络 URL 还是本地文件路径
    final isNetwork =
        imageUrl.startsWith('http://') || imageUrl.startsWith('https://');

    if (isNetwork) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        httpHeaders: getImageHeaders(imageUrl),
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.grey[900]),
        errorWidget: (context, url, error) =>
            Container(color: Colors.grey[900]),
      );
    } else {
      // 本地文件
      return Image.file(
        File(imageUrl),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            Container(color: Colors.grey[900]),
      );
    }
  }

  /// 构建纯色背景
  Widget _buildSolidColorBackground(PlayerBackgroundService backgroundService) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            backgroundService.solidColor,
            Colors.grey[900]!,
            Colors.black,
          ],
        ),
      ),
    );
  }

  /// 构建图片背景
  Widget _buildImageBackground(PlayerBackgroundService backgroundService) {
    if (backgroundService.mediaPath != null) {
      final mediaFile = File(backgroundService.mediaPath!);
      if (mediaFile.existsSync()) {
        // 性能优化：RepaintBoundary 隔离重绘区域
        final background = Stack(
          children: [
            // 图片层
            Positioned.fill(
              child: Image.file(
                mediaFile,
                fit: BoxFit.cover,
                // 性能优化：限制解码尺寸，避免大图片阻塞主线程
                cacheWidth: 1920,
                cacheHeight: 1080,
                isAntiAlias: true,
                filterQuality: FilterQuality.medium,
              ),
            ),
            // 模糊层（性能优化：限制模糊程度避免GPU过载，最大 25）
            if (backgroundService.blurAmount > 0)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: backgroundService.blurAmount.clamp(0.0, 25.0),
                    sigmaY: backgroundService.blurAmount.clamp(0.0, 25.0),
                  ),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.3), // 添加半透明遮罩
                  ),
                ),
              )
            else if (backgroundService.blurAmount == 0)
              // 无模糊时也添加浅色遮罩以确保文字可读
              Positioned.fill(
                child: Container(color: Colors.black.withValues(alpha: 0.2)),
              ),
          ],
        );
        return widget.isolateRepaints
            ? RepaintBoundary(child: background)
            : background;
      }
    }

    // 如果没有设置图片，使用默认背景
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.grey[900]!, Colors.black, Colors.black],
        ),
      ),
    );
  }

  /// 构建视频背景
  Widget _buildVideoBackground(PlayerBackgroundService backgroundService) {
    if (backgroundService.mediaPath != null) {
      final mediaFile = File(backgroundService.mediaPath!);
      if (mediaFile.existsSync()) {
        return Stack(
          children: [
            // 视频层
            Positioned.fill(
              child: VideoBackgroundPlayer(
                videoPath: backgroundService.mediaPath!,
                blurAmount: backgroundService.blurAmount,
                opacity: 1.0,
              ),
            ),
            // 半透明遮罩确保文字可读
            if (backgroundService.blurAmount == 0)
              Positioned.fill(
                child: Container(color: Colors.black.withValues(alpha: 0.2)),
              ),
          ],
        );
      }
    }

    // 如果没有设置视频，使用默认背景
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.grey[900]!, Colors.black, Colors.black],
        ),
      ),
    );
  }
}
