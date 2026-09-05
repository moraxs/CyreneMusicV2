import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cyrene_music_reborn/domain/models/audio_quality.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/infrastructure/cache/song_cache_crypto.dart';
import 'package:cyrene_music_reborn/infrastructure/cache/song_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「边播边缓存」的完整链路：播放器从中转地址取流 → 服务只向源站取一次 →
/// 密文落盘 → 下次命中直接本地解密播。用一个本地 HTTP 服务冒充音源 CDN，
/// 并统计它收到了几次请求，以此确认没有下第二遍。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 测试绑定默认给所有 HttpClient 挂上「一律返回 400」的 mock，本用例要真的
  // 收发字节（缓存中转走的就是真实 HTTP），把它摘掉。
  HttpOverrides.global = null;

  final audio = Uint8List.fromList(
    List.generate(150000, (index) => Random(7).nextInt(256)),
  );

  const track = Track(
    id: '123456',
    name: '测试歌曲',
    artists: '测试歌手',
    album: '测试专辑',
    picUrl: '',
    source: MusicSource.netease,
    lyric: '[00:00.00]第一句',
    duration: Duration(seconds: 213),
  );

  const other = Track(
    id: '654321',
    name: '另一首',
    artists: '',
    album: '',
    picUrl: '',
    source: MusicSource.kugou,
  );

  late Directory directory;
  late HttpServer origin;
  late SongCacheService service;
  String contentType = 'audio/mpeg';
  int status = HttpStatus.ok;
  Uint8List body = audio;
  bool announceLength = true;
  Duration chunkDelay = Duration.zero;
  var originRequests = <String?>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('cyrene-cache-service');
    contentType = 'audio/mpeg';
    status = HttpStatus.ok;
    body = audio;
    announceLength = true;
    chunkDelay = Duration.zero;
    originRequests = [];
    origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin.listen((request) async {
      originRequests.add(request.headers.value(HttpHeaders.rangeHeader));
      final response = request.response;
      response.statusCode = status;
      response.headers.set(HttpHeaders.contentTypeHeader, contentType);
      // dart:io 默认走分块传输（不发 Content-Length），真实 CDN 则会给长度，
      // 两种都要覆盖：给了长度才谈得上 Range/可 seek。
      if (announceLength) response.contentLength = body.length;
      if (chunkDelay == Duration.zero) {
        response.add(body);
      } else {
        for (var offset = 0; offset < body.length; offset += 32768) {
          response.add(
            body.sublist(offset, min(offset + 32768, body.length)),
          );
          await response.flush();
          await Future<void>.delayed(chunkDelay);
        }
      }
      await response.close();
    });
    service = SongCacheService.instance..debugUseDirectory(directory);
    await service.setEnabled(true);
  });

  tearDown(() async {
    await service.clear();
    await service.setEnabled(false);
    await origin.close(force: true);
    try {
      await directory.delete(recursive: true);
    } catch (_) {}
  });

  Uri originUri(String path) =>
      Uri.parse('http://127.0.0.1:${origin.port}/$path');

  Future<(int, List<int>, Map<String, String>)> fetch(
    Uri uri, {
    String? range,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
      final response = await request.close();
      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        headers[name] = values.join(',');
      });
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      return (response.statusCode, bytes, headers);
    } finally {
      client.close();
    }
  }

  /// 逐字节比较，但失败时只报差异位置——直接 equals 两个 15 万元素的数组，
  /// 一旦失败测试输出会有几十万行。
  void expectSameBytes(List<int> actual, List<int> expected) {
    expect(actual, hasLength(expected.length));
    for (var i = 0; i < expected.length; i++) {
      if (actual[i] != expected[i]) {
        fail('第 $i 字节不符: ${actual[i]} != ${expected[i]}');
      }
    }
  }

  /// 模拟一次播放：拿到中转地址后完整读完（播放器就是这么干的）。
  Future<Uri> play(Track item, AudioQuality quality) async {
    final uri = await service.intercept(
      track: item,
      quality: quality,
      remoteUrl: originUri('song.mp3'),
    );
    return uri;
  }

  test('播放即缓存：源站只被请求一次，密文落盘且播放器拿到的是原始音频',
      () async {
    expect(await service.lookup(track, AudioQuality.exHigh), isNull);

    final proxy = await play(track, AudioQuality.exHigh);
    expect(proxy.host, '127.0.0.1');
    expect(proxy.port, isNot(origin.port));

    final (statusCode, played, headers) = await fetch(proxy);
    expect(statusCode, HttpStatus.ok);
    // 播放器拿到的必须是原始音频，一个字节都不能差。
    expectSameBytes(played, audio);
    expect(headers['content-type'], 'audio/mpeg');
    await service.debugSettle();

    // 关键断言：整个过程源站只被请求了一次，没有第二遍下载。
    expect(originRequests, hasLength(1));

    final key = SongCacheService.cacheKey(track, AudioQuality.exHigh);
    final file = File('${directory.path}${Platform.pathSeparator}$key.cyca');
    expect(await file.exists(), isTrue);
    final raw = await file.readAsBytes();
    expect(
      Uint8List.sublistView(raw, SongCacheCrypto.headerLength),
      isNot(equals(audio)),
      reason: '落盘的必须是密文',
    );
    expectSameBytes(SongCacheCrypto.open(raw)!, audio);

    // 再次播放：命中缓存，源站请求数不再增加。
    final hit = await service.lookup(track, AudioQuality.exHigh);
    expect(hit, isNotNull);
    final (_, replayed, _) = await fetch(hit!.uri);
    expectSameBytes(replayed, audio);
    expect(originRequests, hasLength(1));
    expect(hit.lyrics?.lyric, '[00:00.00]第一句');
    expect(hit.duration, const Duration(seconds: 213));

    final stats = await service.refreshStats();
    expect(stats.count, 1);
    expect(stats.bytes, raw.length);
  });

  test('播放中途拖进度条：Range 请求返回正确片段', () async {
    final proxy = await play(track, AudioQuality.exHigh);
    // 先完整播一遍让它落盘。
    await fetch(proxy);
    await service.debugSettle();

    final hit = await service.lookup(track, AudioQuality.exHigh);
    final (statusCode, bytes, headers) = await fetch(
      hit!.uri,
      range: 'bytes=100000-100999',
    );
    expect(statusCode, HttpStatus.partialContent);
    expectSameBytes(bytes, audio.sublist(100000, 101000));
    expect(headers['content-range'], 'bytes 100000-100999/${audio.length}');
  });

  test('播放器边下边读时也能正确取到整首（慢速源站）', () async {
    chunkDelay = const Duration(milliseconds: 5);
    final proxy = await play(track, AudioQuality.exHigh);
    final (statusCode, played, _) = await fetch(proxy);
    expect(statusCode, HttpStatus.ok);
    expectSameBytes(played, audio);
    await service.debugSettle();
    expect(originRequests, hasLength(1));
    expect((await service.refreshStats()).count, 1);
  });

  test('下载还没到那儿就往前拖：另开一条直连补上，字节仍然正确', () async {
    // 源站慢到下载远远追不上（拖的位置要超出已下载 512KB 以上才会走直连），
    // 且它会忽略 Range 直接从头发——中转必须自己把前缀丢掉，否则播放器会
    // 拿到错位的音频。
    final big = Uint8List.fromList(
      List.generate(3000000, (index) => (index * 31 + 7) & 0xFF),
    );
    body = big;
    chunkDelay = const Duration(milliseconds: 20);
    final proxy = await play(track, AudioQuality.exHigh);
    final client = HttpClient();
    final warmup = await (await client.getUrl(proxy)).close();
    await warmup.take(1).toList();
    client.close(force: true);

    final (statusCode, bytes, _) = await fetch(
      proxy,
      range: 'bytes=2500000-2500999',
    );
    expect(statusCode, HttpStatus.partialContent);
    expectSameBytes(bytes, big.sublist(2500000, 2501000));
    // 这是第二条连接，但只发生在超前 seek 时，且带着 Range。
    expect(originRequests.length, greaterThan(1));
    expect(originRequests.last, 'bytes=2500000-2500999');
  });

  test('源站不声明长度（流式音源）时照样能播能缓存', () async {
    announceLength = false;
    final proxy = await play(track, AudioQuality.exHigh);
    final (statusCode, played, headers) = await fetch(proxy);
    expect(statusCode, HttpStatus.ok);
    expectSameBytes(played, audio);
    // 长度未知就不该声称支持 Range，否则播放器会拖出错位的进度。
    expect(headers.containsKey('accept-ranges'), isFalse);
    await service.debugSettle();
    expect((await service.refreshStats()).count, 1);
  });

  test('播放器中途断开（切歌）仍会把这首抓完并落盘', () async {
    chunkDelay = const Duration(milliseconds: 5);
    final proxy = await play(track, AudioQuality.exHigh);
    final client = HttpClient();
    final response = await (await client.getUrl(proxy)).close();
    await response.take(1).toList(); // 只读一点就掐断
    client.close(force: true);

    await service.debugSettle();
    expect((await service.refreshStats()).count, 1);
    final hit = await service.lookup(track, AudioQuality.exHigh);
    final (_, replayed, _) = await fetch(hit!.uri);
    expectSameBytes(replayed, audio);
  });

  test('源站返回错误页时把状态码透给播放器，且不落盘', () async {
    status = HttpStatus.forbidden;
    final proxy = await play(track, AudioQuality.exHigh);
    final (statusCode, _, _) = await fetch(proxy);
    expect(statusCode, HttpStatus.forbidden);
    await service.debugSettle();
    expect((await service.refreshStats()).count, 0);
    expect(await service.lookup(track, AudioQuality.exHigh), isNull);
  });

  test('响应不是音频（JSON 错误体）时不落盘', () async {
    contentType = 'application/json';
    body = Uint8List.fromList(utf8.encode('{"msg":"版权限制"}'));
    final proxy = await play(track, AudioQuality.exHigh);
    await fetch(proxy);
    await service.debugSettle();
    expect((await service.refreshStats()).count, 0);
  });

  test('内容过小时视为无效响应，不留下半截缓存', () async {
    body = Uint8List.fromList(List.filled(1024, 1));
    final proxy = await play(track, AudioQuality.exHigh);
    await fetch(proxy);
    await service.debugSettle();
    expect((await service.refreshStats()).count, 0);
    expect(await service.lookup(track, AudioQuality.exHigh), isNull);
  });

  test('未完成的半截文件不会被当成缓存命中', () async {
    final key = SongCacheService.cacheKey(track, AudioQuality.exHigh);
    // 手工造一个有音频没元数据的残留（等价于下载被掐断）。
    await File('${directory.path}${Platform.pathSeparator}$key.cyca')
        .writeAsBytes(SongCacheCrypto.seal(audio));
    expect(await service.lookup(track, AudioQuality.exHigh), isNull);
    expect((await service.refreshStats()).count, 0);
  });

  test('关闭缓存后直连源站，不中转也不命中', () async {
    await fetch(await play(track, AudioQuality.exHigh));
    await service.debugSettle();
    expect((await service.refreshStats()).count, 1);

    await service.setEnabled(false);
    expect(await service.lookup(track, AudioQuality.exHigh), isNull);
    final direct = await service.intercept(
      track: other,
      quality: AudioQuality.exHigh,
      remoteUrl: originUri('song.mp3'),
    );
    // 原样返回源站地址。
    expect(direct, originUri('song.mp3'));
    expect((await service.refreshStats()).count, 1);
  });

  test('不同音质各存一份', () async {
    for (final quality in [AudioQuality.standard, AudioQuality.lossless]) {
      final proxy = await play(track, quality);
      await fetch(proxy);
      await service.debugSettle();
    }
    expect((await service.refreshStats()).count, 2);
  });

  test('一键清空删掉音频与元数据', () async {
    final proxy = await play(track, AudioQuality.exHigh);
    await fetch(proxy);
    await service.debugSettle();
    expect(await directory.list().isEmpty, isFalse);

    await service.clear();
    expect((await service.refreshStats()).count, 0);
    expect(await directory.list().isEmpty, isTrue);
  });

  test('单曲删除只影响该曲目', () async {
    for (final item in [track, other]) {
      final proxy = await play(item, AudioQuality.exHigh);
      await fetch(proxy);
      await service.debugSettle();
    }
    expect((await service.refreshStats()).count, 2);

    await service.remove(SongCacheService.cacheKey(other, AudioQuality.exHigh));
    final remaining = await service.list();
    expect(remaining, hasLength(1));
    expect(remaining.single.track.id, '123456');
  });

  test('选中的目录本身就叫 CyreneMusicCache 时不再套一层同名子目录', () async {
    final picked = Directory(
      '${directory.path}${Platform.pathSeparator}CyreneMusicCache',
    );
    await picked.create();
    final ok = await service.setLocation(
      SongCacheLocation.custom,
      customPath: picked.path,
    );
    expect(ok, isTrue);
    expect(service.directoryPath, picked.path);

    // 普通目录仍然建子目录，避免把用户选的目录当垃圾场。
    final plain = Directory(
      '${directory.path}${Platform.pathSeparator}某个音乐目录',
    );
    await plain.create();
    await service.setLocation(SongCacheLocation.custom, customPath: plain.path);
    expect(
      service.directoryPath,
      '${plain.path}${Platform.pathSeparator}CyreneMusicCache',
    );
  });

  test('缓存目录被删掉后能自愈，不必重启应用', () async {
    final picked = Directory(
      '${directory.path}${Platform.pathSeparator}CyreneMusicCache',
    );
    await picked.create();
    await service.setLocation(
      SongCacheLocation.custom,
      customPath: picked.path,
    );
    await picked.delete(recursive: true);
    expect(await picked.exists(), isFalse);

    final proxy = await play(track, AudioQuality.exHigh);
    await fetch(proxy);
    await service.debugSettle();
    expect(await picked.exists(), isTrue);
    expect((await service.refreshStats()).count, 1);
  });

  test('容量上限触发时淘汰最久未播放的缓存', () async {
    var proxy = await play(track, AudioQuality.exHigh);
    await fetch(proxy);
    await service.debugSettle();
    // 让两条缓存的访问时间拉开差距，且让第一首成为「最久未播放」的那条。
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    proxy = await play(other, AudioQuality.exHigh);
    await fetch(proxy);
    await service.debugSettle();
    expect((await service.refreshStats()).count, 2);

    await service.setLimitBytes(audio.length + SongCacheCrypto.headerLength + 1);
    final remaining = await service.list();
    expect(remaining, hasLength(1));
    expect(remaining.single.track.id, '654321');
  });
}
