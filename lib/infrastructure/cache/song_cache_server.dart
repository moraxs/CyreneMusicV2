import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'song_cache_crypto.dart';

/// 本地音频服务：既是缓存的解密出口，也是首次播放时的「边播边缓存」中转。
///
/// 播放器拿到的永远是本服务的回环地址，两种情形：
/// - **已缓存**：从磁盘读加密文件，边解密边吐给播放器，支持 Range（拖进度条）；
/// - **未缓存**：向源站开**一条**连接，收到的字节一边加密落盘、一边转发给
///   播放器。所以一首歌只从网络下载一次——播放本身就是那次下载。
///
/// 为什么不是「播放器直连源站 + 后台再下一遍」：那样每首新歌都要走两遍流量，
/// 而且 Spotify 这类后端实时转码的一次性 stream 地址根本经不起开第二条连接。
///
/// 整个服务跑在**后台 isolate** 里：解密、加密、落盘都不占 UI isolate 的 CPU，
/// 播放器又会以最快速度把整首歌拉完，放主 isolate 上必然掉帧。
///
/// 只绑定 127.0.0.1，且路径里带一枚随机令牌——同机其它进程即便猜到端口也拿
/// 不到音频。
class SongCacheServer {
  SongCacheServer();

  Isolate? _isolate;
  ReceivePort? _events;
  SendPort? _commands;
  Uri? _base;
  String? _directory;
  Future<Uri?>? _starting;

  /// 一首歌完整落盘时回调（主 isolate 据此写元数据、做容量清理）。
  void Function(String key, int bytes, String extension)? onCached;

  /// 缓存失败时回调（播放不受影响，只是这首没存下来）。
  void Function(String key, String error)? onFailed;

  bool get isRunning => _base != null;

  /// [uri] 是否就是本服务发出去的地址。用来挡住「把自己的流当成音源再缓存
  /// 一遍」这种自我循环。
  bool owns(Uri uri) {
    final base = _base;
    return base != null && uri.host == base.host && uri.port == base.port;
  }

  /// 预热：提前把 isolate 起好，别把这几十毫秒摊到第一次播放的解析路径上。
  Future<void> warmUp(String directory) => _ensureStarted(directory);

  /// 已缓存曲目的播放地址。
  Future<Uri?> urlFor(String directory, String fileName) async {
    final base = await _ensureStarted(directory);
    return base?.resolve(fileName);
  }

  /// 登记源地址并返回代理地址：播放器从这个地址取流，服务只向源站取一次，
  /// 边转发边加密落盘。服务起不来时返回 null（调用方直连源站，只是不缓存）。
  Future<Uri?> proxyUrlFor({
    required String directory,
    required String key,
    required String extension,
    required Uri origin,
    required Duration idleTimeout,
    required int minBytes,
    required int maxBytes,
  }) async {
    final base = await _ensureStarted(directory);
    if (base == null) return null;
    _commands?.send({
      't': 'origin',
      'key': key,
      'url': origin.toString(),
      'idleMs': idleTimeout.inMilliseconds,
      'min': minBytes,
      'max': maxBytes,
    });
    return base.resolve('$key.$extension');
  }

  Future<Uri?> _ensureStarted(String directory) {
    if (_directory == directory) {
      if (_base != null) return Future<Uri?>.value(_base);
      final starting = _starting;
      if (starting != null) return starting;
    }
    // 目录变了：旧 isolate 指向旧目录，重来。
    stop();
    _directory = directory;
    return _starting = _spawn(directory);
  }

  Future<Uri?> _spawn(String directory) async {
    final events = ReceivePort();
    final ready = Completer<Uri?>();
    events.listen((message) {
      if (message is! List || message.isEmpty) return;
      switch (message[0]) {
        case 'ready':
          _base = Uri.parse('http://127.0.0.1:${message[1]}/${message[2]}/');
          _commands = message[3] as SendPort;
          if (!ready.isCompleted) ready.complete(_base);
        case 'cached':
          onCached?.call(
            message[1] as String,
            message[2] as int,
            message[3] as String,
          );
        case 'failed':
          onFailed?.call(message[1] as String, message[2] as String);
        default:
          if (!ready.isCompleted) ready.complete(null);
      }
    });
    try {
      _isolate = await Isolate.spawn(
        _serverEntryPoint,
        [events.sendPort, directory],
        debugName: 'song-cache-server',
      );
    } catch (error) {
      debugPrint('[SongCacheServer] 启动失败: $error');
      events.close();
      _starting = null;
      _directory = null;
      return null;
    }
    _events = events;
    // isolate 起来后只做绑端口 + 生成令牌，正常是毫秒级；给 5 秒已经很宽，
    // 超时就直连音源，不能让播放在这儿干等。
    final base = await ready.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => null,
    );
    _starting = null;
    if (base == null) {
      debugPrint('[SongCacheServer] 未能就绪，本次播放直连音源');
      stop();
      return null;
    }
    debugPrint('[SongCacheServer] 已启动: $base');
    return base;
  }

  void stop() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _events?.close();
    _events = null;
    _commands = null;
    _base = null;
    _directory = null;
    _starting = null;
  }
}

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

/// 起点比已下载位置超前这么多时，另开一条直连转发，不干等下载追上。
const _seekAheadTolerance = 512 * 1024;

/// isolate 入口：绑定回环端口，回传 `[ready, 端口, 令牌, 指令端口]`。
Future<void> _serverEntryPoint(List<Object> args) async {
  final events = args[0] as SendPort;
  final directory = args[1] as String;
  final HttpServer server;
  try {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  } catch (error) {
    debugPrint('[SongCacheServer] 端口绑定失败: $error');
    Isolate.exit(events, ['bind-failed']);
  }
  server.autoCompress = false;
  final random = Random.secure();
  final token = List.generate(
    16,
    (_) => '0123456789abcdef'[random.nextInt(16)],
  ).join();
  final host = _ServerHost(
    directory: directory,
    token: token,
    events: events,
  );
  final commands = ReceivePort();
  commands.listen(host.onCommand);
  events.send(['ready', server.port, token, commands.sendPort]);

  await for (final request in server) {
    unawaited(host.handle(request));
  }
}

/// 待抓取的源地址。
class _Origin {
  const _Origin({
    required this.url,
    required this.idleTimeout,
    required this.minBytes,
    required this.maxBytes,
  });

  final Uri url;

  /// 多久收不到数据就放弃（流式音源按播放速率吐数据，容忍度要高）。
  final Duration idleTimeout;
  final int minBytes;
  final int maxBytes;
}

class _ServerHost {
  _ServerHost({
    required this.directory,
    required this.token,
    required this.events,
  });

  final String directory;
  final String token;
  final SendPort events;

  final Map<String, _Origin> _origins = {};
  final Map<String, _Pump> _pumps = {};

  void onCommand(Object? message) {
    if (message is! Map || message['t'] != 'origin') return;
    final key = message['key'] as String;
    _origins[key] = _Origin(
      url: Uri.parse(message['url'] as String),
      idleTimeout: Duration(milliseconds: message['idleMs'] as int),
      minBytes: message['min'] as int,
      maxBytes: message['max'] as int,
    );
    while (_origins.length > 32) {
      _origins.remove(_origins.keys.first);
    }
  }

  String _pathFor(String key, String extension) =>
      '$directory${Platform.pathSeparator}$key.$extension';

  Future<void> handle(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      // 形如 /<token>/<key>.<ext>：令牌不符或文件名不是 32 位十六进制 key
      // 一律拒绝（后者同时挡掉 `..` 之类的路径穿越）。
      if (segments.length != 2 || segments[0] != token) {
        response.statusCode = HttpStatus.forbidden;
        await response.close();
        return;
      }
      final name = segments[1];
      final dot = name.lastIndexOf('.');
      final key = dot < 0 ? name : name.substring(0, dot);
      if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(key)) {
        response.statusCode = HttpStatus.forbidden;
        await response.close();
        return;
      }

      // 下面这段查表与建 pump 之间**不能有 await**：播放器可能同时开好几条
      // 连接（探测格式、seek），一旦中间让出事件循环，就会各起一条下载同时
      // 往一个文件里写。
      final file = File(_pathFor(key, 'cyca'));
      final running = _pumps[key];
      if (running != null && running.error == null) {
        await _serveFromPump(request, running);
        return;
      }
      final origin = _origins[key];
      if (origin != null) {
        // 登记了源地址就说明这首还没缓存好（缓存命中时上层根本不会登记），
        // 直接开抓；已有的半截文件会被覆盖重写。
        _prunePumps();
        final pump = _Pump(key: key, file: file, origin: origin, events: events);
        _pumps[key] = pump;
        unawaited(pump.start());
        await _serveFromPump(request, pump);
        return;
      }
      if (await file.exists()) {
        await _serveFromFile(request, file, name);
        return;
      }
      response.statusCode = HttpStatus.notFound;
      await response.close();
    } catch (error) {
      // 播放器切歌 / seek 时会直接掐断连接，这里的异常绝大多数是这种正常中断。
      debugPrint('[SongCacheServer] 请求处理中断: $error');
      try {
        await response.close();
      } catch (_) {}
    }
  }

  /// 已完成的 pump 留着只为占位，攒多了就清掉；连同源地址一起删，
  /// 后续请求会走「元数据存在 → 直接读磁盘」那条路。
  void _prunePumps() {
    if (_pumps.length <= 8) return;
    for (final entry in _pumps.entries.toList()) {
      if (_pumps.length <= 8) break;
      if (!entry.value.done) continue;
      _pumps.remove(entry.key);
      if (entry.value.error == null) _origins.remove(entry.key);
    }
  }

  Future<void> _serveFromFile(
    HttpRequest request,
    File file,
    String name,
  ) async {
    final response = request.response;
    final raf = await file.open();
    try {
      final nonce = SongCacheCrypto.readNonce(
        await raf.read(SongCacheCrypto.headerLength),
      );
      final total = await file.length() - SongCacheCrypto.headerLength;
      if (nonce == null || total <= 0) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      final range = _parseRange(rangeHeader, total);
      if (range == null) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
        await response.close();
        return;
      }
      final (start, end) = range;
      _writeHeaders(
        response,
        rangeHeader: rangeHeader,
        contentType: _contentTypeFor(name),
        start: start,
        end: end,
        total: total,
      );
      if (request.method == 'HEAD') {
        await response.close();
        return;
      }
      await response.addStream(_read(raf, nonce, start, end));
      await response.close();
    } finally {
      await raf.close();
    }
  }

  Future<void> _serveFromPump(HttpRequest request, _Pump pump) async {
    final response = request.response;
    await pump.headersReady;
    if (pump.error != null) {
      // 源站直接失败：把状态码原样透出去，播放器会照常回退到下一个候选，
      // 与直连音源失败时的行为一致。
      response.statusCode = pump.statusCode ?? HttpStatus.badGateway;
      await response.close();
      return;
    }

    final total = pump.contentLength;
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    int start;
    int end;
    if (total != null) {
      final range = _parseRange(rangeHeader, total);
      if (range == null) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
        await response.close();
        return;
      }
      (start, end) = range;
    } else {
      // 源站没给长度（分块传输的流式音源）：无法支持 Range，整段转发。
      start = 0;
      end = 1 << 40;
    }
    _writeHeaders(
      response,
      rangeHeader: total == null ? null : rangeHeader,
      contentType: pump.contentType,
      start: start,
      end: end,
      total: total,
    );
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }

    // 往前拖得太远：干等下载追上会让进度条卡住，另开一条直连转发这一段
    // （不写缓存，后台那条 pump 继续把整首歌抓完）。
    if (total != null && start > pump.written + _seekAheadTolerance) {
      await _passThrough(response, pump.origin, start, end);
      return;
    }

    final raf = await pump.file.open();
    try {
      await response.addStream(_read(raf, pump.nonce!, start, end, pump: pump));
      await response.close();
    } finally {
      await raf.close();
    }
  }

  /// 超前 seek 的直连转发。源站若忽略 Range 直接从头发（返回 200），
  /// 就自己把前缀丢掉，保证客户端拿到的确实是它要的那一段。
  Future<void> _passThrough(
    HttpResponse response,
    _Origin origin,
    int start,
    int end,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(origin.url);
      request.followRedirects = true;
      request.headers
        ..set(HttpHeaders.userAgentHeader, _userAgent)
        ..set(HttpHeaders.acceptHeader, '*/*')
        ..set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
      final upstream = await request.close();
      var skip = upstream.statusCode == HttpStatus.partialContent ? 0 : start;
      var remaining = end - start + 1;
      await for (final chunk in upstream.timeout(origin.idleTimeout)) {
        var data = chunk;
        if (skip > 0) {
          if (data.length <= skip) {
            skip -= data.length;
            continue;
          }
          data = data.sublist(skip);
          skip = 0;
        }
        if (data.length > remaining) data = data.sublist(0, remaining);
        response.add(data);
        remaining -= data.length;
        if (remaining <= 0) break;
      }
      await response.close();
    } finally {
      client.close(force: true);
    }
  }

  void _writeHeaders(
    HttpResponse response, {
    required String? rangeHeader,
    required String contentType,
    required int start,
    required int end,
    required int? total,
  }) {
    response.headers.set(HttpHeaders.contentTypeHeader, contentType);
    if (total == null) {
      // 长度未知 → 分块传输，且不声明可 seek。
      response.statusCode = HttpStatus.ok;
      return;
    }
    // 只要对方带了 Range 就回 206（哪怕正好是整段）。ffmpeg 的 http 协议按
    // 「请求 Range 是否得到 206」判断这条流可不可 seek，图省事回 200 会让它
    // 把缓存流当成不可定位的直播流，进度条就拖不动了。
    response.statusCode = rangeHeader == null
        ? HttpStatus.ok
        : HttpStatus.partialContent;
    response.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..contentLength = end - start + 1;
    if (response.statusCode == HttpStatus.partialContent) {
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$total',
      );
    }
  }
}

/// 一次「取流 + 落盘」。
///
/// 客户端不直接从这里拿字节，而是从它正在写的文件里读已落盘的部分（见
/// [_read]）：读端慢不会拖住下载，一首歌多个连接（播放器探测格式时会关掉
/// 重开）也能共用同一次下载，且内存占用与文件大小无关。
class _Pump {
  _Pump({
    required this.key,
    required this.file,
    required this.origin,
    required this.events,
  });

  final String key;
  final File file;
  final _Origin origin;
  final SendPort events;

  final Completer<void> _headers = Completer<void>();
  Completer<void> _progress = Completer<void>();

  /// 已落盘（且已 flush，读端可见）的明文字节数。
  int written = 0;
  Uint8List? nonce;
  int? contentLength;
  String contentType = 'audio/mpeg';
  int? statusCode;
  bool done = false;
  String? error;

  Future<void> get headersReady => _headers.future;
  Future<void> get progress => _progress.future;

  void _notify() {
    final pending = _progress;
    _progress = Completer<void>();
    if (!pending.isCompleted) pending.complete();
  }

  void _releaseHeaders() {
    if (!_headers.isCompleted) _headers.complete();
  }

  Future<void> start() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    IOSink? sink;
    try {
      final request = await client.getUrl(origin.url);
      request.followRedirects = true;
      request.headers
        ..set(HttpHeaders.userAgentHeader, _userAgent)
        ..set(HttpHeaders.acceptHeader, '*/*');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      statusCode = response.statusCode;
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final mime = response.headers.contentType?.mimeType ?? '';
      if (_looksLikeErrorPayload(mime)) {
        throw HttpException('响应不是音频：$mime');
      }
      if (mime.isNotEmpty) contentType = mime;
      final length = response.contentLength;
      contentLength = length > 0 ? length : null;
      if (contentLength != null && contentLength! > origin.maxBytes) {
        throw HttpException('响应过大：$contentLength 字节');
      }

      final iv = SongCacheCrypto.newNonce();
      final state = SongCacheCrypto.newState(nonce: iv);
      sink = file.openWrite();
      sink.add(SongCacheCrypto.buildHeader(iv));
      await sink.flush();
      nonce = iv;
      // 头部就绪：等着响应的客户端可以开始发状态行和 header 了。
      _releaseHeaders();

      await for (final chunk in response.timeout(origin.idleTimeout)) {
        final bytes = chunk is Uint8List
            ? chunk
            : Uint8List.fromList(chunk);
        SongCacheCrypto.applyInPlace(state, bytes);
        sink.add(bytes);
        // 每块都 flush：读端是另开的句柄，看不到还留在缓冲里的字节。
        await sink.flush();
        written += bytes.length;
        if (written > origin.maxBytes) throw const HttpException('响应过大');
        _notify();
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (written < origin.minBytes) {
        throw HttpException('内容过小（$written 字节），不像有效音频');
      }
      final declared = contentLength;
      if (declared != null && written != declared) {
        throw HttpException('传输不完整：$written/$declared 字节');
      }
      done = true;
      _notify();
      events.send([
        'cached',
        key,
        written,
        _extensionFor(contentType, origin.url),
      ]);
    } catch (error) {
      this.error = '$error';
      done = true;
      try {
        await sink?.close();
      } catch (_) {}
      // 半截文件不能留：没有元数据它不会被当成缓存，但会白占空间。
      // Windows 上若还有读句柄会删不掉，交给服务侧的孤儿清理兜底。
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      _releaseHeaders();
      _notify();
      events.send(['failed', key, '$error']);
    } finally {
      client.close(force: true);
    }
  }
}

/// 从加密文件里读 [start,end] 区间的明文。
///
/// 带 [pump] 时是「边下边读」：读到已落盘的末尾就等下一块，直到下载结束。
Stream<List<int>> _read(
  RandomAccessFile raf,
  Uint8List nonce,
  int start,
  int end, {
  _Pump? pump,
}) async* {
  const chunkSize = 64 * 1024;
  final state = SongCacheCrypto.newState(
    nonce: nonce,
    offset: start,
    encrypting: false,
  );
  var position = start;
  while (position <= end) {
    // 先拿等待句柄再判断进度，否则「判断完 → 新块到达 → 才开始等」会漏掉
    // 这次通知；再加个超时兜底，任何情况下都不会永久挂住。
    final waiting = pump?.progress;
    final available = pump == null ? end - position + 1 : pump.written - position;
    if (available <= 0) {
      if (pump == null || pump.done) break;
      await waiting!.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );
      continue;
    }
    final want = min(chunkSize, min(available, end - position + 1));
    await raf.setPosition(SongCacheCrypto.headerLength + position);
    final chunk = await raf.read(want);
    if (chunk.isEmpty) {
      if (pump == null || pump.done) break;
      await waiting!.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );
      continue;
    }
    SongCacheCrypto.applyInPlace(state, chunk);
    yield chunk;
    position += chunk.length;
  }
}

/// 解析 `Range: bytes=start-end`，返回闭区间；无该头时返回整段，越界返回 null。
(int, int)? _parseRange(String? header, int total) {
  if (header == null || !header.startsWith('bytes=')) return (0, total - 1);
  final spec = header.substring(6).split(',').first.trim();
  final dash = spec.indexOf('-');
  if (dash < 0) return null;
  final startText = spec.substring(0, dash);
  final endText = spec.substring(dash + 1);
  int start;
  int end;
  if (startText.isEmpty) {
    // `bytes=-N`：末尾 N 字节。
    final suffix = int.tryParse(endText);
    if (suffix == null || suffix <= 0) return null;
    start = max(0, total - suffix);
    end = total - 1;
  } else {
    final parsedStart = int.tryParse(startText);
    if (parsedStart == null) return null;
    start = parsedStart;
    end = endText.isEmpty ? total - 1 : (int.tryParse(endText) ?? total - 1);
  }
  if (start < 0 || start >= total || end < start) return null;
  return (start, min(end, total - 1));
}

bool _looksLikeErrorPayload(String contentType) {
  final value = contentType.toLowerCase();
  return value.contains('json') ||
      value.contains('html') ||
      value.contains('xml') ||
      value.startsWith('text/');
}

/// 交给播放器的地址会带上这个后缀，libmpv 据此挑解复用器。
String _extensionFor(String contentType, Uri url) {
  final value = contentType.toLowerCase();
  if (value.contains('flac')) return 'flac';
  if (value.contains('mp4') || value.contains('m4a') || value.contains('aac')) {
    return 'm4a';
  }
  if (value.contains('ogg') || value.contains('opus')) return 'ogg';
  if (value.contains('wav')) return 'wav';
  if (value.contains('mpeg') || value.contains('mp3')) return 'mp3';
  final path = url.path.toLowerCase();
  for (final extension in const ['flac', 'm4a', 'ogg', 'wav', 'ape', 'mp3']) {
    if (path.endsWith('.$extension')) return extension;
  }
  return 'mp3';
}

String _contentTypeFor(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'flac' => 'audio/flac',
    'm4a' || 'mp4' || 'aac' => 'audio/mp4',
    'ogg' || 'opus' => 'audio/ogg',
    'wav' => 'audio/wav',
    'ape' => 'audio/x-ape',
    _ => 'audio/mpeg',
  };
}
