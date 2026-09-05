import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// 歌曲缓存的加密容器（音频文件与元数据共用）。
///
/// 密钥为口令 `cyrene2026` 的 SHA-256（32 字节，正好是 ChaCha20 的密钥长度）。
///
/// 选 ChaCha20 而不是 AES 的两个原因：
/// - 纯 Dart 下 ChaCha20 比 AES 快数倍，而缓存播放要一路解密整首歌；
/// - 它是**流密码**，密钥流可以从任意字节位置续算（`keyStreamIndex`）。本地
///   解密服务要响应 Range 请求（拖动进度条 / libmpv 的分段取流）就必须有这种
///   随机访问能力，分组密码的 CBC/GCM 做不到。
///
/// 不带 MAC（[MacAlgorithm.empty]）：缓存要防的是「明文音频裸奔在磁盘上」，
/// 不是篡改；挂上 Poly1305 反而会让分段解密失效（认证需要完整密文）。
///
/// 文件布局：
/// ```
/// 0    magic 'CYCACHE' + 版本(1 字节)   —— 8 字节
/// 8    nonce                            —— 12 字节
/// 20   密文（密钥流从 0 开始，与明文一一对应）
/// ```
/// 于是「明文第 n 字节」= 「文件第 [headerLength] + n 字节」，Range 请求换算
/// 只是一次加减法。
class SongCacheCrypto {
  const SongCacheCrypto._();

  /// 用户约定的固定口令。
  static const String passphrase = 'cyrene2026';

  /// 魔数 'CYCACHE' + 版本号。
  static final Uint8List _magic = Uint8List.fromList([
    ...ascii.encode('CYCACHE'),
    1,
  ]);

  static const int _nonceLength = 12;

  /// 头部长度：魔数(8) + nonce(12)。
  static const int headerLength = 20;

  static final DartChacha20 _cipher = DartChacha20(
    macAlgorithm: MacAlgorithm.empty,
  );

  static final SecretKeyData _key = SecretKeyData(
    const DartSha256().hashSync(utf8.encode(passphrase)).bytes,
  );

  static final Random _random = Random.secure();

  static Uint8List newNonce() {
    final nonce = Uint8List(_nonceLength);
    for (var i = 0; i < _nonceLength; i++) {
      nonce[i] = _random.nextInt(256);
    }
    return nonce;
  }

  static Uint8List buildHeader(Uint8List nonce) {
    final header = Uint8List(headerLength);
    header.setRange(0, _magic.length, _magic);
    header.setRange(_magic.length, headerLength, nonce);
    return header;
  }

  /// 校验头部并取出 nonce；魔数/版本不符返回 null（当作缓存损坏处理）。
  static Uint8List? readNonce(List<int> header) {
    if (header.length < headerLength) return null;
    for (var i = 0; i < _magic.length; i++) {
      if (header[i] != _magic[i]) return null;
    }
    return Uint8List.fromList(header.sublist(_magic.length, headerLength));
  }

  /// 新建一个密钥流状态，[offset] 为明文中的起始字节（Range 请求即用它定位）。
  static DartCipherState newState({
    required List<int> nonce,
    int offset = 0,
    bool encrypting = true,
  }) {
    final state = _cipher.newState();
    state.initializeSync(
      isEncrypting: encrypting,
      secretKey: _key,
      nonce: nonce,
      keyStreamIndex: offset,
    );
    return state;
  }

  /// 就地异或一段数据并推进密钥流。传进来的 buffer 会被直接改写（省一次拷贝，
  /// 调用方给的都是刚从 socket / 文件读出来的独占缓冲区）。
  static void applyInPlace(DartCipherState state, Uint8List chunk) {
    state.convertChunkSync(chunk, possibleBuffer: chunk);
  }

  /// 整块加密（元数据这类小文件用），产出「头部 + 密文」的完整文件内容。
  static Uint8List seal(List<int> plain) {
    final nonce = newNonce();
    final state = newState(nonce: nonce);
    final body = Uint8List.fromList(plain);
    applyInPlace(state, body);
    final out = Uint8List(headerLength + body.length);
    out.setRange(0, headerLength, buildHeader(nonce));
    out.setRange(headerLength, out.length, body);
    return out;
  }

  /// 整块解密；文件损坏（头部不合法）时返回 null。
  static Uint8List? open(Uint8List file) {
    final nonce = readNonce(file);
    if (nonce == null) return null;
    final body = Uint8List.fromList(
      Uint8List.sublistView(file, headerLength),
    );
    applyInPlace(newState(nonce: nonce, encrypting: false), body);
    return body;
  }
}
