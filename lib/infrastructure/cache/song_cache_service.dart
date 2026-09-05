import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/audio_quality.dart';
import '../../domain/models/lyric_data.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';
import '../../domain/playback/audio_cache.dart';
import 'song_cache_crypto.dart';
import 'song_cache_server.dart';

/// 缓存目录的落点。各平台可选项不同，见 [SongCacheService.availableLocations]。
enum SongCacheLocation {
  /// 应用私有目录（`getApplicationSupportDirectory`）。全平台可用，卸载即清除，
  /// 不需要任何存储权限；iOS 上这是唯一不会被系统随时回收的可写位置。
  internal,

  /// Android 的应用专属外部目录（`/Android/data/<包名>/files`）。容量大、
  /// 文件管理器可见，同样不需要存储权限。
  external,

  /// 用户自选目录（仅桌面端）。移动端受分区存储限制，选了也写不进去。
  custom,
}

/// 缓存用量统计。
@immutable
class SongCacheStats {
  const SongCacheStats({required this.count, required this.bytes});

  static const empty = SongCacheStats(count: 0, bytes: 0);

  final int count;
  final int bytes;
}

/// 缓存管理页里的一条记录。
@immutable
class CachedSongInfo {
  const CachedSongInfo({
    required this.key,
    required this.track,
    required this.quality,
    required this.bytes,
    required this.cachedAt,
  });

  final String key;
  final Track track;
  final AudioQuality quality;
  final int bytes;
  final DateTime cachedAt;
}

/// 歌曲缓存服务。
///
/// 首次播放某首歌时，播放地址会被换成本地服务的回环地址（[intercept]）：服务
/// 向源站开**一条**连接，收到的字节一边转发给播放器、一边加密写进
/// `<key>.cyca`，同时记一份同样加密的元数据 `<key>.cycm`（曲目信息 + 歌词）。
/// 于是一首歌只走一次网络——播放本身就是那次下载，没有额外流量。
///
/// 再次播放时 [lookup] 命中，直接从本地解密流播放：不解析音源、不联网。
///
/// 元数据文件同时充当**完成标记**：只有 `.cycm` 存在才算缓存有效，所以中途被
/// 掐断（切歌、断网、杀进程）留下的半截 `.cyca` 永远不会被当成缓存播出来。
class SongCacheService extends ChangeNotifier implements AudioCache {
  SongCacheService._() {
    _server
      ..onCached = _onCached
      ..onFailed = _onFailed;
  }

  static final SongCacheService instance = SongCacheService._();

  static const _kEnabled = 'song_cache_enabled';
  static const _kLocation = 'song_cache_location';
  static const _kCustomPath = 'song_cache_custom_path';
  static const _kLimitBytes = 'song_cache_limit_bytes';

  /// 缓存目录名。自选目录下建这一层子目录，避免把用户选的目录（可能是「音乐」
  /// 甚至盘符根）直接当垃圾场，一键清空时也只会动我们自己的东西。
  static const _folderName = 'CyreneMusicCache';

  static const _audioExtension = '.cyca';
  static const _metaExtension = '.cycm';

  /// 小于此大小的响应不当作有效音频（多半是错误页或空流）。
  static const _minAudioBytes = 64 * 1024;

  /// 单曲上限，超过即放弃（防御异常响应，正常无损曲目远小于此）。
  static const _maxAudioBytes = 300 * 1024 * 1024;

  /// 默认容量上限 2 GB；0 表示不限制。
  static const int defaultLimitBytes = 2 * 1024 * 1024 * 1024;

  /// 没有元数据（即未完成）的音频文件超过这个年龄就清掉——都是被掐断的
  /// 下载留下的，不清会一直占着空间。
  static const _orphanMaxAge = Duration(hours: 1);

  final SongCacheServer _server = SongCacheServer();

  bool _enabled = false;
  SongCacheLocation _location = SongCacheLocation.internal;
  String _customPath = '';
  int _limitBytes = defaultLimitBytes;
  Directory? _directory;
  SongCacheStats _stats = SongCacheStats.empty;
  Future<void>? _loading;

  /// 已交给播放器、还没落盘完成的曲目（key → 元数据）。
  final Map<String, _PendingCapture> _pending = {};

  bool get enabled => _enabled;
  SongCacheLocation get location => _location;
  int get limitBytes => _limitBytes;

  /// 最近一次统计结果（[refreshStats] 更新）。设置页摘要直接读它，避免每次
  /// 构建都扫目录。
  SongCacheStats get stats => _stats;

  /// 已解析的缓存目录；未初始化或不可写时为 null。
  String? get directoryPath => _directory?.path;

  /// 当前平台可选的存储位置。
  static List<SongCacheLocation> get availableLocations => [
    SongCacheLocation.internal,
    if (Platform.isAndroid) SongCacheLocation.external,
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
      SongCacheLocation.custom,
  ];

  /// 测试用：直接指定缓存目录，跳过 path_provider（测试环境没有插件）。
  @visibleForTesting
  void debugUseDirectory(Directory directory) => _directory = directory;

  /// 测试用：等所有在途缓存落定（成功或失败）。
  @visibleForTesting
  Future<void> debugSettle() async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (_pending.isNotEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> init() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kEnabled) ?? false;
      _location = _locationFromName(prefs.getString(_kLocation));
      _customPath = prefs.getString(_kCustomPath) ?? '';
      _limitBytes = prefs.getInt(_kLimitBytes) ?? defaultLimitBytes;
      notifyListeners();
      if (_enabled) {
        final directory = await _ensureDirectory();
        if (directory != null) unawaited(_server.warmUp(directory.path));
        unawaited(refreshStats());
      }
    } catch (error) {
      debugPrint('[SongCacheService] 读取缓存设置失败: $error');
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) return;
    _enabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, enabled);
    if (enabled) {
      await _ensureDirectory();
      await refreshStats();
    }
  }

  Future<void> setLimitBytes(int bytes) async {
    if (_limitBytes == bytes) return;
    _limitBytes = bytes;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLimitBytes, bytes);
    await _enforceLimit();
  }

  /// 切换缓存目录。[migrate] 为真时把已有缓存搬过去（同盘 rename，跨盘复制）。
  ///
  /// 失败（目录不可写等）返回 false，此时保持原设置不变。
  Future<bool> setLocation(
    SongCacheLocation location, {
    String? customPath,
    bool migrate = true,
  }) async {
    final previous = _directory;
    final previousLocation = _location;
    final previousCustom = _customPath;
    _location = location;
    if (customPath != null) _customPath = customPath;
    _directory = null;
    final next = await _ensureDirectory();
    if (next == null) {
      _location = previousLocation;
      _customPath = previousCustom;
      _directory = previous;
      notifyListeners();
      return false;
    }
    if (migrate && previous != null && !p.equals(previous.path, next.path)) {
      await _migrate(previous, next);
    }
    final prefs = await SharedPreferences.getInstance();
    // 存 _location 而不是入参：自选目录为空等情况下 [_ensureDirectory] 会把它
    // 悄悄回落到内部存储，落盘的应当是真正生效的那个。
    await prefs.setString(_kLocation, _location.name);
    await prefs.setString(_kCustomPath, _customPath);
    notifyListeners();
    await refreshStats();
    return true;
  }

  // ───────────────────────── AudioCache ─────────────────────────

  @override
  Future<CachedAudio?> lookup(Track track, AudioQuality quality) async {
    if (!_enabled) return null;
    final directory = await _ensureDirectory();
    if (directory == null) return null;
    final key = cacheKey(track, quality);
    // 元数据是完成标记：没有它就当没缓存（半截文件会被重新下载覆盖）。
    final meta = await _readMeta(directory, key);
    if (meta == null) return null;
    final file = File(p.join(directory.path, '$key$_audioExtension'));
    if (!await file.exists()) return null;

    final uri = await _server.urlFor(directory.path, '$key.${meta.extension}');
    if (uri == null) return null;

    // 用访问时间做 LRU 依据（见 [_enforceLimit]）。部分文件系统不支持，忽略。
    try {
      await file.setLastAccessed(DateTime.now());
    } catch (_) {}

    return CachedAudio(
      uri: uri,
      lyrics: meta.lyrics,
      duration: meta.track.duration,
    );
  }

  @override
  Future<Uri> intercept({
    required Track track,
    required AudioQuality quality,
    required Uri remoteUrl,
  }) async {
    if (!_enabled) return remoteUrl;
    if (track.source == MusicSource.local) return remoteUrl;
    // 只代理真正的网络音源；本地文件与我们自己的流都原样放行（后者会自我循环）。
    if (remoteUrl.scheme != 'http' && remoteUrl.scheme != 'https') {
      return remoteUrl;
    }
    if (_server.owns(remoteUrl)) return remoteUrl;

    final directory = await _ensureDirectory();
    if (directory == null) return remoteUrl;
    final key = cacheKey(track, quality);
    _pending[key] = _PendingCapture(track: track, quality: quality);
    // 后缀只是给 libmpv 的提示，真实类型以源站 Content-Type 为准（转发时原样
    // 透出），落盘完成后再按真实类型记进元数据。
    final proxy = await _server.proxyUrlFor(
      directory: directory.path,
      key: key,
      extension: _guessExtension(remoteUrl),
      origin: remoteUrl,
      idleTimeout: _idleTimeoutFor(track.source),
      minBytes: _minAudioBytes,
      maxBytes: _maxAudioBytes,
    );
    if (proxy == null) {
      // 本地服务起不来（端口被安全软件拦等）：直连源站，只是这次不缓存。
      _pending.remove(key);
      return remoteUrl;
    }
    return proxy;
  }

  /// 「多久收不到数据就放弃」。Spotify / Apple 这类后端实时转码的流式音源
  /// 按播放速率吐数据，容忍度要高得多。
  static Duration _idleTimeoutFor(MusicSource source) => switch (source) {
    MusicSource.spotify || MusicSource.apple => const Duration(seconds: 180),
    _ => const Duration(seconds: 60),
  };

  static String _guessExtension(Uri url) {
    final path = url.path.toLowerCase();
    for (final extension in const ['flac', 'm4a', 'ogg', 'wav', 'ape', 'mp3']) {
      if (path.endsWith('.$extension')) return extension;
    }
    return 'mp3';
  }

  /// 缓存文件名（32 位十六进制，[SongCacheServer] 按此校验路径）。
  ///
  /// 音质进 key：同一首歌换音质应当各存一份，而不是拿标准音质冒充无损。
  static String cacheKey(Track track, AudioQuality quality) {
    final digest = const DartSha256().hashSync(
      utf8.encode('${track.source.wireName}:${track.id}:${quality.wireName}'),
    );
    final buffer = StringBuffer();
    for (final byte in digest.bytes.take(16)) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// 一首歌完整落盘：补上元数据（完成标记），再按容量上限清理。
  Future<void> _onCached(String key, int bytes, String extension) async {
    final pending = _pending.remove(key);
    final directory = _directory;
    if (pending == null || directory == null) return;
    try {
      await _writeMeta(
        directory,
        key,
        pending,
        extension: extension,
        bytes: bytes,
      );
      debugPrint('[SongCacheService] 已缓存「${pending.track.name}」($bytes 字节)');
      await _enforceLimit();
      await refreshStats();
    } catch (error) {
      debugPrint('[SongCacheService] 写入缓存元数据失败: $error');
    }
  }

  void _onFailed(String key, String error) {
    final pending = _pending.remove(key);
    debugPrint('[SongCacheService] 缓存「${pending?.track.name ?? key}」失败: $error');
  }

  // ───────────────────────── 管理操作 ─────────────────────────

  Future<SongCacheStats> refreshStats() async {
    final directory = _directory ?? await _ensureDirectory();
    if (directory == null) {
      _stats = SongCacheStats.empty;
      notifyListeners();
      return _stats;
    }
    var count = 0;
    var bytes = 0;
    try {
      final now = DateTime.now();
      await for (final entity in directory.list()) {
        if (entity is! File || !entity.path.endsWith(_audioExtension)) continue;
        final key = p.basenameWithoutExtension(entity.path);
        final complete = await File(
          p.join(directory.path, '$key$_metaExtension'),
        ).exists();
        if (!complete) {
          // 没有完成标记：要么正在下（很新），要么是被掐断的残留（清掉）。
          final stat = await entity.stat();
          if (now.difference(stat.modified) > _orphanMaxAge) {
            try {
              await entity.delete();
            } catch (_) {}
          }
          continue;
        }
        count += 1;
        bytes += await entity.length();
      }
    } catch (error) {
      debugPrint('[SongCacheService] 统计缓存失败: $error');
    }
    _stats = SongCacheStats(count: count, bytes: bytes);
    notifyListeners();
    return _stats;
  }

  /// 已缓存曲目列表，按缓存时间倒序。
  Future<List<CachedSongInfo>> list() async {
    final directory = _directory ?? await _ensureDirectory();
    if (directory == null) return const [];
    final items = <CachedSongInfo>[];
    try {
      await for (final entity in directory.list()) {
        if (entity is! File || !entity.path.endsWith(_audioExtension)) continue;
        final key = p.basenameWithoutExtension(entity.path);
        final meta = await _readMeta(directory, key);
        if (meta == null) continue;
        items.add(
          CachedSongInfo(
            key: key,
            track: meta.track,
            quality: meta.quality,
            bytes: await entity.length(),
            cachedAt: meta.cachedAt,
          ),
        );
      }
    } catch (error) {
      debugPrint('[SongCacheService] 读取缓存列表失败: $error');
    }
    items.sort((a, b) => b.cachedAt.compareTo(a.cachedAt));
    return items;
  }

  Future<void> remove(String key) async {
    final directory = _directory ?? await _ensureDirectory();
    if (directory == null) return;
    await _deleteEntry(directory, key);
    await refreshStats();
  }

  /// 一键清空：只删缓存目录内我们自己的文件，不动目录里的其它内容。
  Future<void> clear() async {
    final directory = _directory ?? await _ensureDirectory();
    if (directory == null) return;
    _pending.clear();
    try {
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        if (entity.path.endsWith(_audioExtension) ||
            entity.path.endsWith(_metaExtension)) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (error) {
      debugPrint('[SongCacheService] 清空缓存失败: $error');
    }
    await refreshStats();
  }

  // ───────────────────────── 目录 ─────────────────────────

  /// 解析并创建缓存目录。
  ///
  /// 注意：解析结果**不落盘**（自选目录除外）。iOS 的应用容器路径带随机 UUID，
  /// 版本更新后会变；Android 的私有目录也可能随外部存储挂载点变化。存绝对路径
  /// 等于埋雷，每次启动重新解析才是对的。
  Future<Directory?> _ensureDirectory() async {
    final cached = _directory;
    // 只认句柄是不够的：目录随时可能被用户或清理工具删掉，之后每次写入都会
    // 抛异常且永远不自愈（除非重启）。命中缓存也要确认它还在，不在就补建。
    if (cached != null) {
      if (await cached.exists()) return cached;
      try {
        await cached.create(recursive: true);
        return cached;
      } catch (error) {
        debugPrint('[SongCacheService] 缓存目录已失效，重新解析: $error');
        _directory = null;
      }
    }
    try {
      final Directory directory;
      switch (_location) {
        case SongCacheLocation.custom:
          if (_customPath.isEmpty) {
            _location = SongCacheLocation.internal;
            return _ensureDirectory();
          }
          // 用户很可能直接选中我们上次建好的 CyreneMusicCache 本身，这时不能
          // 再套一层同名子目录——他打开选的那个文件夹会发现空空如也。
          directory = p.basename(_customPath) == _folderName
              ? Directory(_customPath)
              : Directory(p.join(_customPath, _folderName));
        case SongCacheLocation.external:
          // Android 专属：应用外部私有目录，无需存储权限。取不到（未挂载）
          // 时回落到内部目录，不让缓存整体失效。
          final base = Platform.isAndroid
              ? await getExternalStorageDirectory()
              : null;
          directory = Directory(
            p.join(
              (base ?? await getApplicationSupportDirectory()).path,
              _folderName,
            ),
          );
        case SongCacheLocation.internal:
          directory = Directory(
            p.join((await getApplicationSupportDirectory()).path, _folderName),
          );
      }
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      _directory = directory;
      return directory;
    } catch (error) {
      debugPrint('[SongCacheService] 缓存目录不可用: $error');
      return null;
    }
  }

  Future<void> _migrate(Directory from, Directory to) async {
    try {
      await for (final entity in from.list()) {
        if (entity is! File) continue;
        if (!entity.path.endsWith(_audioExtension) &&
            !entity.path.endsWith(_metaExtension)) {
          continue;
        }
        final target = p.join(to.path, p.basename(entity.path));
        try {
          await entity.rename(target);
        } on FileSystemException {
          // 跨盘/跨挂载点 rename 会失败，退化为复制后删除。
          await entity.copy(target);
          await entity.delete();
        }
      }
    } catch (error) {
      debugPrint('[SongCacheService] 迁移缓存失败: $error');
    }
  }

  // ───────────────────────── 元数据 ─────────────────────────

  Future<void> _writeMeta(
    Directory directory,
    String key,
    _PendingCapture pending, {
    required String extension,
    required int bytes,
  }) async {
    // playbackUrl 是限时直链（或本地代理地址），存下来只会误导下次播放。
    final trackJson = pending.track.toJson()..remove('playbackUrl');
    final payload = <String, Object?>{
      'v': 1,
      'track': trackJson,
      'quality': pending.quality.wireName,
      'ext': extension,
      'bytes': bytes,
      'cachedAt': DateTime.now().millisecondsSinceEpoch,
    };
    final file = File(p.join(directory.path, '$key$_metaExtension'));
    await file.writeAsBytes(
      SongCacheCrypto.seal(utf8.encode(jsonEncode(payload))),
      flush: true,
    );
  }

  Future<_CachedMeta?> _readMeta(Directory directory, String key) async {
    try {
      final file = File(p.join(directory.path, '$key$_metaExtension'));
      if (!await file.exists()) return null;
      final plain = SongCacheCrypto.open(await file.readAsBytes());
      if (plain == null) return null;
      final decoded = jsonDecode(utf8.decode(plain));
      if (decoded is! Map) return null;
      final json = Map<String, Object?>.from(decoded);
      final trackJson = json['track'];
      if (trackJson is! Map) return null;
      return _CachedMeta(
        track: Track.fromJson(Map<String, Object?>.from(trackJson)),
        quality: AudioQuality.fromWireName(json['quality']?.toString()),
        extension: json['ext']?.toString() ?? 'mp3',
        cachedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['cachedAt'] as num?)?.toInt() ?? 0,
        ),
      );
    } catch (error) {
      debugPrint('[SongCacheService] 读取缓存元数据失败: $error');
      return null;
    }
  }

  // ───────────────────────── 容量 ─────────────────────────

  /// 超出容量上限时按「最久未播放」逐条淘汰。
  Future<void> _enforceLimit() async {
    if (_limitBytes <= 0) return;
    final directory = _directory;
    if (directory == null) return;
    try {
      final files = <(File, FileStat)>[];
      var total = 0;
      await for (final entity in directory.list()) {
        if (entity is! File || !entity.path.endsWith(_audioExtension)) continue;
        final stat = await entity.stat();
        total += stat.size;
        files.add((entity, stat));
      }
      if (total <= _limitBytes) return;
      files.sort((a, b) => a.$2.accessed.compareTo(b.$2.accessed));
      for (final (file, stat) in files) {
        if (total <= _limitBytes) break;
        await _deleteEntry(directory, p.basenameWithoutExtension(file.path));
        total -= stat.size;
      }
      debugPrint('[SongCacheService] 已按容量上限清理至 $total 字节');
    } catch (error) {
      debugPrint('[SongCacheService] 容量清理失败: $error');
    }
  }

  Future<void> _deleteEntry(Directory directory, String key) async {
    for (final extension in const [_audioExtension, _metaExtension]) {
      try {
        final file = File(p.join(directory.path, '$key$extension'));
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  static SongCacheLocation _locationFromName(String? name) {
    for (final location in SongCacheLocation.values) {
      if (location.name == name) return location;
    }
    return SongCacheLocation.internal;
  }
}

class _PendingCapture {
  const _PendingCapture({required this.track, required this.quality});

  final Track track;
  final AudioQuality quality;
}

class _CachedMeta {
  const _CachedMeta({
    required this.track,
    required this.quality,
    required this.extension,
    required this.cachedAt,
  });

  final Track track;
  final AudioQuality quality;
  final String extension;
  final DateTime cachedAt;

  /// 缓存下来的歌词（随曲目一起落盘），离线播放时不必再请求。
  LyricData? get lyrics {
    final data = LyricData(
      lyric: track.lyric ?? '',
      tlyric: track.tlyric ?? '',
      yrc: track.yrc ?? '',
      ytlrc: track.ytlrc ?? '',
      romaji: track.romaji ?? '',
    );
    return data.isEmpty ? null : data;
  }
}
