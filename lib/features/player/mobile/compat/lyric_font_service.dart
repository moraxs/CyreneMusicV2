import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

/// 预设字体
class PresetFont {
  final String id;
  final String name;
  final String? fontFamily;
  final String description;

  const PresetFont({
    required this.id,
    required this.name,
    this.fontFamily,
    required this.description,
  });
}

/// 歌词字体服务
/// 管理歌词显示的字体设置
class LyricFontService extends ChangeNotifier {
  static final LyricFontService _instance = LyricFontService._internal();
  factory LyricFontService() => _instance;
  LyricFontService._internal();

  // SharedPreferences 键
  static const String _keyFontType = 'lyric_font_type'; // 'preset' 或 'custom'
  static const String _keyPresetFontId = 'lyric_preset_font_id';
  static const String _keyCustomFontPath = 'lyric_custom_font_path';
  static const String _keyCustomFontFamily = 'lyric_custom_font_family';

  // 预设字体列表 (全平台)
  static const List<PresetFont> presetFonts = [
    PresetFont(
      id: 'system',
      name: '系统默认',
      fontFamily: null,
      description: '使用系统默认字体',
    ),
    // === Windows 字体 ===
    PresetFont(
      id: 'microsoft_yahei',
      name: '微软雅黑',
      fontFamily: 'Microsoft YaHei',
      description: 'Windows 系统中文字体',
    ),
    PresetFont(
      id: 'simhei',
      name: '黑体',
      fontFamily: 'SimHei',
      description: 'Windows 经典中文黑体',
    ),
    PresetFont(
      id: 'simsun',
      name: '宋体',
      fontFamily: 'SimSun',
      description: 'Windows 经典中文宋体',
    ),
    PresetFont(
      id: 'kaiti',
      name: '楷体',
      fontFamily: 'KaiTi',
      description: 'Windows 优雅楷书风格',
    ),
    PresetFont(
      id: 'fangsong',
      name: '仿宋',
      fontFamily: 'FangSong',
      description: 'Windows 仿宋体风格',
    ),
    PresetFont(
      id: 'dengxian',
      name: '等线',
      fontFamily: 'DengXian',
      description: 'Windows 10/11 现代字体',
    ),
    // === Android 字体 ===
    PresetFont(
      id: 'noto_sans_sc',
      name: 'Noto Sans SC',
      fontFamily: 'Noto Sans SC',
      description: 'Android 系统中文字体',
    ),
    PresetFont(
      id: 'roboto',
      name: 'Roboto',
      fontFamily: 'Roboto',
      description: 'Android 默认 UI 字体',
    ),
    PresetFont(
      id: 'sans_serif',
      name: 'Sans Serif',
      fontFamily: 'sans-serif',
      description: 'Android 无衬线字体',
    ),
    PresetFont(
      id: 'serif',
      name: 'Serif',
      fontFamily: 'serif',
      description: 'Android 衬线字体',
    ),
    PresetFont(
      id: 'monospace',
      name: 'Monospace',
      fontFamily: 'monospace',
      description: 'Android 等宽字体',
    ),
    // === iOS 字体 ===
    PresetFont(
      id: 'pingfang_sc',
      name: '苹方简体',
      fontFamily: 'PingFang SC',
      description: 'iOS 系统中文字体',
    ),
    PresetFont(
      id: 'sf_pro',
      name: 'SF Pro',
      fontFamily: '.SF Pro Text',
      description: 'iOS 系统 UI 字体',
    ),
    PresetFont(
      id: 'heiti_sc',
      name: '黑体-简',
      fontFamily: 'Heiti SC',
      description: 'iOS 经典中文黑体',
    ),
    PresetFont(
      id: 'songti_sc',
      name: '宋体-简',
      fontFamily: 'Songti SC',
      description: 'iOS 经典中文宋体',
    ),
    PresetFont(
      id: 'stkaiti',
      name: '华文楷体',
      fontFamily: 'STKaiti',
      description: 'iOS 楷书风格',
    ),
    // === 通用字体 ===
    PresetFont(
      id: 'arial',
      name: 'Arial',
      fontFamily: 'Arial',
      description: '跨平台无衬线字体',
    ),
    PresetFont(
      id: 'times_new_roman',
      name: 'Times New Roman',
      fontFamily: 'Times New Roman',
      description: '跨平台衬线字体',
    ),
    PresetFont(
      id: 'georgia',
      name: 'Georgia',
      fontFamily: 'Georgia',
      description: '优雅的衬线字体',
    ),
    PresetFont(
      id: 'consolas',
      name: 'Consolas',
      fontFamily: 'Consolas',
      description: '等宽编程字体',
    ),
  ];

  /// 根据当前平台返回推荐的字体列表
  static List<PresetFont> get platformFonts {
    // 系统默认字体始终在最前
    final List<PresetFont> result = [presetFonts.first];
    
    if (Platform.isWindows) {
      // Windows 平台：Windows 字体 + 通用字体
      result.addAll(presetFonts.where((f) => 
        f.id.startsWith('microsoft') || 
        f.id == 'simhei' || f.id == 'simsun' || 
        f.id == 'kaiti' || f.id == 'fangsong' || 
        f.id == 'dengxian' ||
        f.id == 'arial' || f.id == 'times_new_roman' || 
        f.id == 'georgia' || f.id == 'consolas'
      ));
    } else if (Platform.isAndroid) {
      // Android 平台：Android 字体 + 通用字体
      result.addAll(presetFonts.where((f) => 
        f.id == 'noto_sans_sc' || f.id == 'roboto' ||
        f.id == 'sans_serif' || f.id == 'serif' || f.id == 'monospace' ||
        f.id == 'arial' || f.id == 'georgia'
      ));
    } else if (Platform.isIOS || Platform.isMacOS) {
      // iOS/macOS 平台：iOS 字体 + 通用字体
      result.addAll(presetFonts.where((f) => 
        f.id == 'pingfang_sc' || f.id == 'sf_pro' ||
        f.id == 'heiti_sc' || f.id == 'songti_sc' || f.id == 'stkaiti' ||
        f.id == 'arial' || f.id == 'times_new_roman' || f.id == 'georgia'
      ));
    } else {
      // 其他平台：通用字体
      result.addAll(presetFonts.where((f) => 
        f.id == 'arial' || f.id == 'times_new_roman' || 
        f.id == 'georgia' || f.id == 'consolas'
      ));
    }
    
    return result;
  }

  // 当前设置
  String _fontType = 'preset'; // 'preset' 或 'custom'
  String _presetFontId = 'microsoft_yahei';
  String? _customFontPath;
  String? _customFontFamily;
  bool _isCustomFontLoaded = false;

  /// 获取当前字体类型
  String get fontType => _fontType;

  /// 获取当前预设字体 ID
  String get presetFontId => _presetFontId;

  /// 获取自定义字体路径
  String? get customFontPath => _customFontPath;

  /// 获取自定义字体 family 名称
  String? get customFontFamily => _customFontFamily;

  /// 获取当前使用的字体 family
  String? get currentFontFamily {
    if (_fontType == 'custom' && _customFontFamily != null && _isCustomFontLoaded) {
      return _customFontFamily;
    }
    
    final preset = presetFonts.firstWhere(
      (f) => f.id == _presetFontId,
      orElse: () => presetFonts.first,
    );
    return preset.fontFamily;
  }

  /// 获取当前字体显示名称
  String get currentFontName {
    if (_fontType == 'custom' && _customFontPath != null) {
      final fileName = _customFontPath!.split(Platform.pathSeparator).last;
      return '自定义: $fileName';
    }
    
    final preset = presetFonts.firstWhere(
      (f) => f.id == _presetFontId,
      orElse: () => presetFonts.first,
    );
    return preset.name;
  }

  /// 初始化服务
  Future<void> initialize() async {
    await _loadSettings();
    
    // 如果有自定义字体，尝试加载
    if (_fontType == 'custom' && _customFontPath != null) {
      await _loadCustomFont(_customFontPath!);
    }
  }

  /// 从本地存储加载设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      _fontType = prefs.getString(_keyFontType) ?? 'preset';
      _presetFontId = prefs.getString(_keyPresetFontId) ?? 'microsoft_yahei';
      _customFontPath = prefs.getString(_keyCustomFontPath);
      _customFontFamily = prefs.getString(_keyCustomFontFamily);
      
      debugPrint('✅ [LyricFontService] 加载设置成功: fontType=$_fontType, presetFontId=$_presetFontId');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ [LyricFontService] 加载设置失败: $e');
    }
  }

  /// 保存设置到本地存储
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.setString(_keyFontType, _fontType);
      await prefs.setString(_keyPresetFontId, _presetFontId);
      
      if (_customFontPath != null) {
        await prefs.setString(_keyCustomFontPath, _customFontPath!);
      } else {
        await prefs.remove(_keyCustomFontPath);
      }
      
      if (_customFontFamily != null) {
        await prefs.setString(_keyCustomFontFamily, _customFontFamily!);
      } else {
        await prefs.remove(_keyCustomFontFamily);
      }
      
      debugPrint('✅ [LyricFontService] 保存设置成功');
    } catch (e) {
      debugPrint('❌ [LyricFontService] 保存设置失败: $e');
    }
  }

  /// 设置预设字体
  Future<void> setPresetFont(String fontId) async {
    if (!presetFonts.any((f) => f.id == fontId)) {
      debugPrint('❌ [LyricFontService] 无效的预设字体 ID: $fontId');
      return;
    }
    
    _fontType = 'preset';
    _presetFontId = fontId;
    _isCustomFontLoaded = false;
    
    await _saveSettings();
    notifyListeners();
    
    final font = presetFonts.firstWhere((f) => f.id == fontId);
    debugPrint('✅ [LyricFontService] 已设置预设字体: ${font.name}');
  }

  /// 选择并加载自定义字体
  Future<bool> pickAndLoadCustomFont() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ttf', 'otf', 'ttc'],
        dialogTitle: '选择字体文件',
      );
      
      if (result == null || result.files.isEmpty) {
        debugPrint('⚠️ [LyricFontService] 用户取消选择字体');
        return false;
      }
      
      final filePath = result.files.first.path;
      if (filePath == null) {
        debugPrint('❌ [LyricFontService] 无法获取文件路径');
        return false;
      }
      
      return await loadCustomFont(filePath);
    } catch (e) {
      debugPrint('❌ [LyricFontService] 选择字体文件失败: $e');
      return false;
    }
  }

  /// 加载自定义字体
  Future<bool> loadCustomFont(String fontPath) async {
    try {
      final success = await _loadCustomFont(fontPath);
      
      if (success) {
        _fontType = 'custom';
        _customFontPath = fontPath;
        await _saveSettings();
        notifyListeners();
      }
      
      return success;
    } catch (e) {
      debugPrint('❌ [LyricFontService] 加载自定义字体失败: $e');
      return false;
    }
  }

  /// 内部方法：加载自定义字体
  Future<bool> _loadCustomFont(String fontPath) async {
    try {
      final file = File(fontPath);
      if (!await file.exists()) {
        debugPrint('❌ [LyricFontService] 字体文件不存在: $fontPath');
        return false;
      }
      
      final bytes = await file.readAsBytes();
      final fontData = ByteData.view(bytes.buffer);
      
      // 生成唯一的字体 family 名称
      final fileName = fontPath.split(Platform.pathSeparator).last;
      final fontFamily = 'CustomLyricFont_${fileName.hashCode.abs()}';
      
      // 使用 FontLoader 加载字体
      final fontLoader = FontLoader(fontFamily);
      fontLoader.addFont(Future.value(fontData));
      await fontLoader.load();
      
      _customFontFamily = fontFamily;
      _isCustomFontLoaded = true;
      
      debugPrint('✅ [LyricFontService] 自定义字体加载成功: $fontFamily');
      return true;
    } catch (e) {
      debugPrint('❌ [LyricFontService] 加载自定义字体失败: $e');
      _isCustomFontLoaded = false;
      return false;
    }
  }

  /// 清除自定义字体，恢复预设
  Future<void> clearCustomFont() async {
    _fontType = 'preset';
    _customFontPath = null;
    _customFontFamily = null;
    _isCustomFontLoaded = false;
    
    await _saveSettings();
    notifyListeners();
    
    debugPrint('✅ [LyricFontService] 已清除自定义字体');
  }

  /// 获取预设字体信息
  PresetFont? getPresetFont(String fontId) {
    try {
      return presetFonts.firstWhere((f) => f.id == fontId);
    } catch (e) {
      return null;
    }
  }

  /// 获取当前预设字体信息
  PresetFont get currentPresetFont {
    return presetFonts.firstWhere(
      (f) => f.id == _presetFontId,
      orElse: () => presetFonts.first,
    );
  }
}
