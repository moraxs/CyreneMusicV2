import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cyrene_music_reborn/infrastructure/cache/song_cache_crypto.dart';
import 'package:cyrene_music_reborn/infrastructure/cache/song_cache_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// 整套缓存方案的地基是「密钥流可以从任意字节位置续算」——本地解密服务靠它
/// 响应 Range 请求。这些用例把该性质连同文件布局一起锁住。
void main() {
  Uint8List sampleBytes(int length) {
    final random = Random(20260905);
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }

  group('SongCacheCrypto', () {
    test('整块加解密可还原', () {
      final plain = utf8.encode('{"name":"歌曲名","artists":"歌手"}');
      final sealed = SongCacheCrypto.seal(plain);
      expect(sealed.length, plain.length + SongCacheCrypto.headerLength);
      expect(SongCacheCrypto.open(sealed), equals(plain));
    });

    test('密文与明文不同（确实加密了）', () {
      final plain = sampleBytes(4096);
      final sealed = SongCacheCrypto.seal(plain);
      final body = Uint8List.sublistView(
        sealed,
        SongCacheCrypto.headerLength,
      );
      expect(body, isNot(equals(plain)));
    });

    test('两次加密用不同 nonce，密文不重复', () {
      final plain = sampleBytes(1024);
      final a = SongCacheCrypto.seal(plain);
      final b = SongCacheCrypto.seal(plain);
      expect(a, isNot(equals(b)));
    });

    test('头部损坏时拒绝解密', () {
      final sealed = SongCacheCrypto.seal(utf8.encode('hello'));
      sealed[0] = 0x00;
      expect(SongCacheCrypto.open(sealed), isNull);
    });

    test('从任意偏移解密都能还原对应片段', () {
      final plain = sampleBytes(70000);
      final sealed = SongCacheCrypto.seal(plain);
      final nonce = SongCacheCrypto.readNonce(sealed)!;
      // 覆盖块内偏移、跨块、块边界三种情况（ChaCha20 块长 64 字节）。
      for (final offset in [0, 1, 63, 64, 65, 4096, 65535, 69999]) {
        final length = min(1000, plain.length - offset);
        final chunk = Uint8List.fromList(
          Uint8List.sublistView(
            sealed,
            SongCacheCrypto.headerLength + offset,
            SongCacheCrypto.headerLength + offset + length,
          ),
        );
        SongCacheCrypto.applyInPlace(
          SongCacheCrypto.newState(
            nonce: nonce,
            offset: offset,
            encrypting: false,
          ),
          chunk,
        );
        expect(
          chunk,
          equals(plain.sublist(offset, offset + length)),
          reason: '偏移 $offset 处解密结果不符',
        );
      }
    });

    test('分块顺序解密与整块解密一致（状态可延续）', () {
      final plain = sampleBytes(20000);
      final sealed = SongCacheCrypto.seal(plain);
      final nonce = SongCacheCrypto.readNonce(sealed)!;
      final state = SongCacheCrypto.newState(nonce: nonce, encrypting: false);
      final output = <int>[];
      for (var offset = 0; offset < plain.length; offset += 3333) {
        final end = min(offset + 3333, plain.length);
        final chunk = Uint8List.fromList(
          Uint8List.sublistView(
            sealed,
            SongCacheCrypto.headerLength + offset,
            SongCacheCrypto.headerLength + end,
          ),
        );
        SongCacheCrypto.applyInPlace(state, chunk);
        output.addAll(chunk);
      }
      expect(output, equals(plain));
    });
  });

  group('SongCacheServer', () {
    late Directory directory;
    late SongCacheServer server;
    final audio = sampleBytes(200000);
    const key = '0123456789abcdef0123456789abcdef';

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('cyrene-cache-test');
      await File('${directory.path}${Platform.pathSeparator}$key.cyca')
          .writeAsBytes(SongCacheCrypto.seal(audio));
      server = SongCacheServer();
    });

    tearDown(() async {
      server.stop();
      await directory.delete(recursive: true);
    });

    Future<(int, List<int>, Map<String, String>)> get_(
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

    test('整段请求返回完整明文', () async {
      final uri = await server.urlFor(directory.path, '$key.mp3');
      expect(uri, isNotNull);
      final (status, bytes, headers) = await get_(uri!);
      expect(status, HttpStatus.ok);
      expect(bytes, equals(audio));
      expect(headers['accept-ranges'], 'bytes');
      expect(headers['content-type'], 'audio/mpeg');
    });

    test('Range 请求返回 206 与对应片段', () async {
      final uri = await server.urlFor(directory.path, '$key.flac');
      final (status, bytes, headers) = await get_(
        uri!,
        range: 'bytes=100000-100999',
      );
      expect(status, HttpStatus.partialContent);
      expect(bytes, equals(audio.sublist(100000, 101000)));
      expect(headers['content-range'], 'bytes 100000-100999/${audio.length}');
      expect(headers['content-type'], 'audio/flac');
    });

    test('开放式 Range（bytes=0-）也回 206，否则播放器认为不可 seek', () async {
      final uri = await server.urlFor(directory.path, '$key.mp3');
      final (status, bytes, _) = await get_(uri!, range: 'bytes=0-');
      expect(status, HttpStatus.partialContent);
      expect(bytes, equals(audio));
    });

    test('末尾 N 字节的 Range 形式', () async {
      final uri = await server.urlFor(directory.path, '$key.mp3');
      final (status, bytes, _) = await get_(uri!, range: 'bytes=-500');
      expect(status, HttpStatus.partialContent);
      expect(bytes, equals(audio.sublist(audio.length - 500)));
    });

    test('越界 Range 返回 416', () async {
      final uri = await server.urlFor(directory.path, '$key.mp3');
      final (status, _, _) = await get_(
        uri!,
        range: 'bytes=${audio.length + 10}-',
      );
      expect(status, HttpStatus.requestedRangeNotSatisfiable);
    });

    test('令牌不符或文件名非法一律拒绝', () async {
      final uri = await server.urlFor(directory.path, '$key.mp3');
      final base = uri!.resolve('.');
      final (forbidden, _, _) = await get_(
        base.resolve('../deadbeef/$key.mp3'),
      );
      expect(forbidden, HttpStatus.forbidden);
      final (traversal, _, _) = await get_(base.resolve('..%2F..%2Fetc.mp3'));
      expect(traversal, HttpStatus.forbidden);
    });

    test('未缓存的 key 返回 404', () async {
      final uri = await server.urlFor(
        directory.path,
        'ffffffffffffffffffffffffffffffff.mp3',
      );
      final (status, _, _) = await get_(uri!);
      expect(status, HttpStatus.notFound);
    });
  });
}
