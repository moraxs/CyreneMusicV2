import 'package:flutter/foundation.dart';

import '../../domain/models/lx_music_config.dart';
import '../core/api_client.dart';

/// LxMusic 音源脚本解析服务（对应 Next.js demo/lib/services/lxMusicSourceService.ts）。
///
/// 单例。负责从洛雪音源 JS 脚本中提取元数据（name/version/author/apiUrl/...）
/// 并构造 [LxMusicConfig]。
///
/// TS 端通过 `fetch` 拉取脚本；Flutter 侧统一走 [ApiClient.instance.apiFetch]。
class LxMusicSourceService {
  LxMusicSourceService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient.instance;

  static final LxMusicSourceService instance = LxMusicSourceService();

  final ApiClient _apiClient;

  /// 解析脚本内容，提取元数据与配置。失败时返回 null。
  LxMusicConfig? parseScript(String scriptContent) {
    try {
      // 提取块注释中的 JSDoc 风格元数据
      final headerMetadata = _parseHeaderMetadata(scriptContent);

      // 提取核心字段（regex 顺序与 Dart 原型保持一致）
      final name =
          headerMetadata['name'] ??
          _extractRegex(scriptContent, [
            RegExp(r'''name\s*:\s*['"]([^'"]+)['"]'''),
            RegExp(r'''['"]name['"]\s*:\s*['"]([^'"]+)['"]'''),
            RegExp(r'''"name"\s*:\s*"([^"]+)"'''),
          ]) ??
          '洛雪音源';

      final version =
          headerMetadata['version'] ??
          _extractRegex(scriptContent, [
            RegExp(r'''version\s*:\s*['"]([^'"]+)['"]'''),
            RegExp(r'''['"]version['"]\s*:\s*['"]([^'"]+)['"]'''),
            RegExp(r'''"version"\s*:\s*"([^"]+)"'''),
          ]) ??
          '1.0.0';

      final author =
          headerMetadata['author'] ??
          _extractRegex(scriptContent, [
            RegExp(r'''author\s*:\s*['"]([^'"]+)['"]'''),
            RegExp(r'''['"]author['"]\s*:\s*['"]([^'"]+)['"]'''),
            RegExp(r'@author\s+(.+)'),
          ]) ??
          '';

      final description =
          headerMetadata['description'] ??
          _extractRegex(scriptContent, [
            RegExp(r'''description\s*:\s*['"]([^'"]+)['"]'''),
            RegExp(r'''['"]description['"]\s*:\s*['"]([^'"]+)['"]'''),
            RegExp(r'@description\s+(.+)'),
          ]) ??
          '';

      final homepage =
          headerMetadata['homepage'] ??
          _extractRegex(scriptContent, [
            RegExp(r'''homepage\s*:\s*['"]([^'"]+)['"]'''),
            RegExp(r'@homepage\s+(.+)'),
          ]) ??
          '';

      final apiUrl = _extractApiUrl(scriptContent);

      final apiKey =
          _extractRegex(scriptContent, [
            RegExp(r'''apiKey\s*[:=]\s*['"]([^'"]+)['"]'''),
            RegExp(r'''api[_-]?key\s*[:=]\s*['"]([^'"]+)['"]'''),
            RegExp(r'''key\s*[:=]\s*['"]([^'"]+)['"]'''),
            RegExp(r'''token\s*[:=]\s*['"]([^'"]+)['"]'''),
            RegExp(r'''['"]key['"]\s*:\s*['"]([^'"]+)['"]'''),
          ]) ??
          '';

      final urlPathTemplate =
          _extractRegex(scriptContent, [
            RegExp(r'''urlPath\s*[:=]\s*['"]([^'"]+)['"]'''),
            RegExp(r'''path\s*[:=]\s*['"]([^'"]+)['"]'''),
            RegExp(r'/url/\{?[a-zA-Z]+\}?/\{?[a-zA-Z]+\}?/\{?[a-zA-Z]+\}?'),
          ]) ??
          '/url/{source}/{songId}/{quality}';

      final id = 'lx_${name}_$version'.replaceAll(RegExp(r'\s+'), '_');

      return LxMusicConfig(
        id: id,
        name: name,
        version: version,
        author: author,
        description: description,
        homepage: homepage,
        apiUrl: apiUrl,
        apiKey: apiKey,
        scriptContent: scriptContent,
        urlPathTemplate: urlPathTemplate,
      );
    } catch (error) {
      debugPrint('[LxMusicSourceService] Failed to parse script: $error');
      return null;
    }
  }

  /// 拉取远程脚本并解析。失败时返回 null。
  Future<LxMusicConfig?> fetchAndParse(String url) async {
    try {
      final response = await _apiClient.apiFetch(
        url,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          '[LxMusicSourceService] HTTP error! status: ${response.statusCode}',
        );
        return null;
      }
      final content = response.body;
      return parseScript(content);
    } catch (error) {
      debugPrint('[LxMusicSourceService] Failed to fetch script: $error');
      return null;
    }
  }

  /// 按顺序尝试一组正则，返回首个匹配结果。
  /// 优先返回第一个捕获组，否则在 pattern 不含捕获组时返回整体匹配。
  String? _extractRegex(String content, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final match = pattern.firstMatch(content);
      if (match == null) continue;
      final group1 = match.group(1);
      if (group1 != null && group1.isNotEmpty) {
        return group1.trim();
      }
      if (!pattern.pattern.contains('(')) {
        final group0 = match.group(0);
        if (group0 != null && group0.isNotEmpty) {
          return group0.trim();
        }
      }
    }
    return null;
  }

  /// 从脚本中提取 API URL，排除 github/jsdelivr 等公共 CDN。
  String _extractApiUrl(String script) {
    final urlPatterns = <RegExp>[
      RegExp(r'''apiUrl\s*[:=]\s*['"]([^'"]+)['"]'''),
      RegExp(r'''api[_-]?url\s*[:=]\s*['"]([^'"]+)['"]'''),
      RegExp(r'''host\s*[:=]\s*['"]([^'"]+)['"]'''),
      RegExp(r'''baseUrl\s*[:=]\s*['"]([^'"]+)['"]'''),
      // 通用 URL 匹配（对应 TS 的 g flag + matchAll）
      RegExp(
        r'''['"]?((?:https?|http)://[a-zA-Z0-9\-._~:/?#\[\]@!$&()*+,;=%]+)['"]?''',
      ),
    ];

    for (var i = 0; i < urlPatterns.length; i++) {
      final pattern = urlPatterns[i];
      final isGlobalPattern = i == urlPatterns.length - 1;
      if (isGlobalPattern) {
        // 通用 URL 匹配：迭代所有匹配
        final matches = pattern.allMatches(script);
        for (final match in matches) {
          final matchedUrl = (match.group(1) ?? match.group(0) ?? '')
              .toString();
          if (matchedUrl.isNotEmpty && _isValidApiUrl(matchedUrl)) {
            final cleaned = _cleanUrl(matchedUrl);
            if (cleaned.isNotEmpty) return cleaned;
          }
        }
      } else {
        final match = pattern.firstMatch(script);
        if (match != null) {
          final matchedUrl = (match.group(1) ?? match.group(0) ?? '')
              .toString();
          if (matchedUrl.isNotEmpty && _isValidApiUrl(matchedUrl)) {
            return _cleanUrl(matchedUrl);
          }
        }
      }
    }
    return '';
  }

  bool _isValidApiUrl(String url) {
    const excludePatterns = [
      'github.com',
      'jsdelivr.net',
      'cdnjs.com',
      'unpkg.com',
      'example.com',
      'localhost',
    ];

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return false;
    }

    return !excludePatterns.any((pattern) => url.contains(pattern));
  }

  String _cleanUrl(String url) {
    var cleaned = url.trim();
    while (cleaned.startsWith("'") || cleaned.startsWith('"')) {
      cleaned = cleaned.substring(1);
    }
    while (cleaned.endsWith("'") || cleaned.endsWith('"')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    return cleaned;
  }

  /// 解析块注释中的 JSDoc 风格元数据（@name / @author / @version / ...）。
  Map<String, String> _parseHeaderMetadata(String script) {
    final metadata = <String, String>{};
    final commentBlockMatch = RegExp(r'/\*[\s\S]*?\*/').firstMatch(script);
    if (commentBlockMatch == null) return metadata;

    final commentContent = commentBlockMatch.group(0) ?? '';
    final patterns = <String, RegExp>{
      'name': RegExp(r'@name\s+(.+)'),
      'author': RegExp(r'@author\s+(.+)'),
      'version': RegExp(r'@version\s+(.+)'),
      'description': RegExp(r'@description\s+(.+)'),
      'homepage': RegExp(r'@homepage\s+(.+)'),
    };

    patterns.forEach((key, pattern) {
      final match = pattern.firstMatch(commentContent);
      if (match != null) {
        var value = (match.group(1) ?? '').trim();
        // 处理 JSDoc 风格行首的 *
        if (value.startsWith('*')) {
          value = value.substring(1).trim();
        }
        if (value.isNotEmpty) metadata[key] = value;
      }
    });

    return metadata;
  }
}
