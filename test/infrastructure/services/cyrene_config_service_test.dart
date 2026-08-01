import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:cyrene_music_reborn/infrastructure/services/cyrene_config_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解密与 Web Crypto AES-GCM 格式兼容的配置', () async {
    final file = await _encryptCyrene(
      '{"name":"测试音源","url":"https://api.example.test","apiKey":"secret"}',
      trailingZeros: 3,
    );

    final config = await CyreneConfigService.instance.decrypt(file);

    expect(config, isNotNull);
    expect(config!.name, '测试音源');
    expect(config.url, 'https://api.example.test');
    expect(config.apiKey, 'secret');
  });

  test('认证标签或密文被篡改时拒绝解密', () async {
    final file = await _encryptCyrene(
      '{"name":"OmniParse","url":"https://api.example.test","apiKey":"key"}',
    );
    file[17] ^= 0x01;

    expect(await CyreneConfigService.instance.decrypt(file), isNull);
  });

  test('校验魔数、版本和最小长度', () async {
    final service = CyreneConfigService.instance;
    final valid = await _encryptCyrene('{}');
    final invalidMagic = Uint8List.fromList(valid)..[0] = 0;
    final invalidVersion = Uint8List.fromList(valid)..[4] = 2;

    expect(service.validateFormat(valid), isTrue);
    expect(service.validateFormat(invalidMagic), isFalse);
    expect(service.validateFormat(invalidVersion), isFalse);
    expect(service.validateFormat(Uint8List(33)), isFalse);
  });
}

Future<Uint8List> _encryptCyrene(String json, {int trailingZeros = 0}) async {
  const key = 'CyreneMusic2024SecretKey12345678';
  final nonce = Uint8List.fromList([
    0x00,
    0x01,
    0x02,
    0x03,
    0x04,
    0x05,
    0x06,
    0x07,
    0x08,
    0x09,
    0x0A,
    0x0B,
  ]);
  final clearText = Uint8List.fromList([
    ...utf8.encode(json),
    ...List<int>.filled(trailingZeros, 0),
  ]);
  final box = await AesGcm.with256bits().encrypt(
    clearText,
    secretKey: SecretKey(utf8.encode(key)),
    nonce: nonce,
  );

  return Uint8List.fromList([
    0x43,
    0x59,
    0x52,
    0x4E,
    0x01,
    ...nonce,
    ...box.cipherText,
    ...box.mac.bytes,
  ]);
}
