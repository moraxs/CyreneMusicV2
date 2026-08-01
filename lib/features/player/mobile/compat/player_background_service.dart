import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 播放器背景类型
enum PlayerBackgroundType {
  adaptive,  // 自适应（基于封面提取颜色）
  solidColor, // 纯色背景
  image,      // 图片背景
  video,      // 视频背景
  dynamic,   // 动态背景（流体云专用，基于封面提取3个颜色的动态渐变）
}

/// 播放器背景设置服务
class PlayerBackgroundService extends ChangeNotifier {
  static final PlayerBackgroundService _instance = PlayerBackgroundService._internal();
  factory PlayerBackgroundService() => _instance;
  PlayerBackgroundService._internal();

  // SharedPreferences 键名
  static const String _keyBackgroundType = 'player_background_type';
  static const String _keySolidColor = 'player_background_solid_color';
  static const String _keyMediaPath = 'player_background_media_path';
  static const String _keyImagePath = 'player_background_image_path'; // 兼容旧版本
  static const String _keyBlurAmount = 'player_background_blur_amount';
  static const String _keyEnableGradient = 'player_background_enable_gradient';

  // 当前设置
  PlayerBackgroundType _backgroundType = PlayerBackgroundType.adaptive;
  Color _solidColor = Colors.grey[900]!;
  String? _mediaPath; // 图片或视频路径
  double _blurAmount = 10.0; // 默认模糊程度（sigma值）
  bool _enableGradient = false; // 是否启用封面渐变效果

  // Getters
  PlayerBackgroundType get backgroundType => _backgroundType;
  Color get solidColor => _solidColor;
  String? get mediaPath => _mediaPath;
  String? get imagePath => _mediaPath; // 兼容旧代码
  double get blurAmount => _blurAmount;
  bool get enableGradient => _enableGradient;
  bool get isAdaptive => _backgroundType == PlayerBackgroundType.adaptive;
  bool get isSolidColor => _backgroundType == PlayerBackgroundType.solidColor;
  bool get isImage => _backgroundType == PlayerBackgroundType.image;
  bool get isVideo => _backgroundType == PlayerBackgroundType.video;
  bool get isDynamic => _backgroundType == PlayerBackgroundType.dynamic;

  /// 初始化服务
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 读取背景类型
    final savedTypeIndex = prefs.getInt(_keyBackgroundType);
    if (savedTypeIndex != null && savedTypeIndex < PlayerBackgroundType.values.length) {
      // 用户已设置过，使用用户设置
      _backgroundType = PlayerBackgroundType.values[savedTypeIndex];
    } else {
      // 用户未设置过，使用平台默认值
      // 桌面端默认使用动态背景，移动端默认使用自适应
      _backgroundType = Platform.isWindows || Platform.isMacOS || Platform.isLinux
          ? PlayerBackgroundType.dynamic
          : PlayerBackgroundType.adaptive;
    }
    
    // 读取纯色
    final colorValue = prefs.getInt(_keySolidColor);
    if (colorValue != null) {
      _solidColor = Color(colorValue);
    }
    
    // 读取媒体路径（优先读取新键名，向后兼容旧键名）
    _mediaPath = prefs.getString(_keyMediaPath) ?? prefs.getString(_keyImagePath);
    
    // 根据文件扩展名自动检测类型（如果是从旧版本迁移）
    if (_mediaPath != null && _backgroundType == PlayerBackgroundType.image) {
      _detectAndUpdateMediaType();
    }
    
    // 读取模糊程度
    _blurAmount = prefs.getDouble(_keyBlurAmount) ?? 10.0;
    
    // 读取渐变开关
    _enableGradient = prefs.getBool(_keyEnableGradient) ?? false;
    
    notifyListeners();
    debugPrint('🎨 [PlayerBackground] 已初始化: $_backgroundType, 模糊: $_blurAmount, 渐变: $_enableGradient');
  }
  
  /// 根据文件扩展名检测并更新媒体类型
  void _detectAndUpdateMediaType() {
    if (_mediaPath == null) return;
    
    final ext = _mediaPath!.toLowerCase().split('.').last;
    if (ext == 'mp4' || ext == 'mov' || ext == 'avi' || ext == 'mkv' || ext == 'webm' || ext == 'm4v') {
      _backgroundType = PlayerBackgroundType.video;
    }
  }

  /// 设置背景类型
  Future<void> setBackgroundType(PlayerBackgroundType type) async {
    if (_backgroundType == type) return;
    
    _backgroundType = type;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyBackgroundType, type.index);
    
    notifyListeners();
    debugPrint('🎨 [PlayerBackground] 背景类型已更改: $type');
  }

  /// 设置纯色背景
  Future<void> setSolidColor(Color color) async {
    if (_solidColor == color) return;
    
    _solidColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySolidColor, color.toARGB32());
    
    notifyListeners();
    debugPrint('🎨 [PlayerBackground] 纯色已更改: ${color.toARGB32().toRadixString(16)}');
  }

  /// 设置媒体背景（图片或视频）
  Future<void> setMediaBackground(String mediaPath) async {
    // 验证文件是否存在
    final file = File(mediaPath);
    if (!await file.exists()) {
      debugPrint('❌ [PlayerBackground] 媒体文件不存在: $mediaPath');
      return;
    }
    
    _mediaPath = mediaPath;
    
    // 自动检测媒体类型
    final ext = mediaPath.toLowerCase().split('.').last;
    if (['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v'].contains(ext)) {
      _backgroundType = PlayerBackgroundType.video;
    } else {
      _backgroundType = PlayerBackgroundType.image;
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMediaPath, mediaPath);
    await prefs.setInt(_keyBackgroundType, _backgroundType.index);
    
    notifyListeners();
    debugPrint('🎨 [PlayerBackground] 媒体背景已设置: $mediaPath (类型: $_backgroundType)');
  }
  
  /// 设置图片背景（兼容旧代码）
  Future<void> setImageBackground(String imagePath) async {
    await setMediaBackground(imagePath);
  }

  /// 设置模糊程度
  Future<void> setBlurAmount(double amount) async {
    if (_blurAmount == amount) return;
    
    _blurAmount = amount.clamp(0.0, 50.0); // 限制范围 0-50
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyBlurAmount, _blurAmount);
    
    notifyListeners();
    debugPrint('🎨 [PlayerBackground] 模糊程度已更改: $_blurAmount');
  }

  /// 清除媒体背景
  Future<void> clearMediaBackground() async {
    _mediaPath = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyMediaPath);
    await prefs.remove(_keyImagePath); // 同时清除旧键名
    
    notifyListeners();
    debugPrint('🎨 [PlayerBackground] 媒体背景已清除');
  }
  
  /// 清除图片背景（兼容旧代码）
  Future<void> clearImageBackground() async {
    await clearMediaBackground();
  }

  /// 获取背景类型的显示名称
  String getBackgroundTypeName() {
    switch (_backgroundType) {
      case PlayerBackgroundType.adaptive:
        return '自适应';
      case PlayerBackgroundType.solidColor:
        return '纯色背景';
      case PlayerBackgroundType.image:
        return '图片背景';
      case PlayerBackgroundType.video:
        return '视频背景';
      case PlayerBackgroundType.dynamic:
        return '动态背景';
    }
  }

  /// 设置渐变开关
  Future<void> setEnableGradient(bool enabled) async {
    if (_enableGradient == enabled) return;
    
    _enableGradient = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableGradient, enabled);
    
    notifyListeners();
    debugPrint('🎨 [PlayerBackground] 渐变开关已更改: $enabled');
  }

  /// 获取背景类型的描述
  String getBackgroundTypeDescription() {
    switch (_backgroundType) {
      case PlayerBackgroundType.adaptive:
        return '基于专辑封面提取颜色';
      case PlayerBackgroundType.solidColor:
        return '使用自定义纯色';
      case PlayerBackgroundType.image:
        return _mediaPath != null ? '自定义图片' : '未设置图片';
      case PlayerBackgroundType.video:
        return _mediaPath != null ? '自定义视频' : '未设置视频';
      case PlayerBackgroundType.dynamic:
        return '基于封面的动态渐变效果';
    }
  }
  
  /// 检查文件是否为支持的图片格式
  bool isImageFile(String path) {
    final ext = path.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext);
  }
  
  /// 检查文件是否为支持的视频格式
  bool isVideoFile(String path) {
    final ext = path.toLowerCase().split('.').last;
    return ['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v'].contains(ext);
  }
  
  /// 获取媒体文件（如果存在）
  File? getMediaFile() {
    if (_mediaPath == null || _mediaPath!.isEmpty) return null;
    final file = File(_mediaPath!);
    return file.existsSync() ? file : null;
  }
}

