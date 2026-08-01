import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/cyrene_config.dart';

/// Cyrene 配置文件服务（对应 Next.js demo/lib/services/cyreneConfigService.ts）。
///
/// 单例。用于解析和解密 `.cyrene` 配置文件。
///
/// 文件使用 AES-256-GCM，布局与 Web 端完全一致：
/// `CYRN + version + nonce + ciphertext + authentication tag`。
class CyreneConfigService {
  CyreneConfigService._();
  static final CyreneConfigService instance = CyreneConfigService._();

  /// 加密密钥（32 字节 = 256 位）。与源码保持一致。
  static const String _encryptionKey = 'CyreneMusic2024SecretKey12345678';

  /// 魔数标识 "CYRN"。
  static final Uint8List _magicNumber = Uint8List.fromList([
    0x43,
    0x59,
    0x52,
    0x4E,
  ]);

  /// 支持的版本。
  static const int _supportedVersion = 1;

  static final AesGcm _cipher = AesGcm.with256bits();

  /// 解密 `.cyrene` 配置文件。
  ///
  /// 文件结构：魔数(4) + 版本(1) + IV(12) + 加密数据 + AuthTag(16)。
  /// 认证失败、格式错误或载荷不是 JSON 对象时返回 `null`。
  Future<CyreneConfig?> decrypt(Uint8List data) async {
    try {
      if (!validateFormat(data)) return null;

      final iv = Uint8List.sublistView(data, 5, 17);
      final authTag = Uint8List.sublistView(data, data.length - 16);
      final encryptedData = Uint8List.sublistView(data, 17, data.length - 16);
      final secretBox = SecretBox(encryptedData, nonce: iv, mac: Mac(authTag));
      final decryptedBytes = await _cipher.decrypt(
        secretBox,
        secretKey: SecretKey(utf8.encode(_encryptionKey)),
      );

      var actualLength = decryptedBytes.length;
      while (actualLength > 0 && decryptedBytes[actualLength - 1] == 0) {
        actualLength--;
      }
      final payload = jsonDecode(
        utf8.decode(decryptedBytes.sublist(0, actualLength)),
      );
      if (payload is! Map) return null;
      return CyreneConfig.fromJson(Map<String, Object?>.from(payload));
    } catch (error) {
      debugPrint('[CyreneConfigService] decrypt failed: $error');
      return null;
    }
  }

  /// 验证文件格式。
  bool validateFormat(Uint8List data) {
    // 最小文件大小: 魔数(4) + 版本(1) + IV(12) + 最小数据(1) + AuthTag(16) = 34 字节。
    if (data.length < 34) {
      return false;
    }

    // 检查魔数。
    for (var i = 0; i < 4; i++) {
      if (data[i] != _magicNumber[i]) {
        return false;
      }
    }

    // 检查版本。
    final version = data[4];
    if (version != _supportedVersion) {
      return false;
    }

    return true;
  }
}
