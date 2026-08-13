import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/models/local_track.dart';

/// 纯 Dart 实现的音频元数据读取器（无第三方依赖）。
///
/// 支持格式：
/// - **FLAC**：STREAMINFO（时长）+ VORBIS_COMMENT（标签 / 歌词）
/// - **MP3**：ID3v2（标题 / 艺术家 / 专辑 / 歌词）+ 帧头估算时长
/// - **M4A / MP4**：ISOBMFF mvhd（时长）+ ilist（标签）
/// - **WAV**：RIFF fmt + data（时长）
/// - **OGG / Vorbis**：识别头 + Vorbis Comment（标签 / 歌词）+ 末页 granule（时长）
/// - **APE**：APEv2 标签 + MAC 头（时长）
///
/// 不支持的格式或解析失败时返回仅含文件名的 [LocalTrackMetadata]，不抛异常。
class AudioMetadataReader {
  AudioMetadataReader._();

  /// 支持的音频文件扩展名（小写、不含点）。
  static const supportedExtensions = <String>{
    'flac',
    'mp3',
    'm4a',
    'mp4',
    'wav',
    'ogg',
    'ape',
    'aac',
    'wma',
  };

  /// 判断文件路径是否为支持的音频格式。
  static bool isSupported(String filePath) {
    final ext = _extension(filePath);
    return supportedExtensions.contains(ext);
  }

  /// 从音频文件中读取元数据。
  ///
  /// 解析失败时仍返回一个包含文件名的 [LocalTrackMetadata]，duration 为 0。
  static Future<LocalTrackMetadata> read(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return _fallback(filePath);
    }

    final ext = _extension(filePath);
    try {
      final bytes = await file.readAsBytes();
      switch (ext) {
        case 'flac':
          return _parseFlac(filePath, bytes);
        case 'mp3':
          return _parseMp3(filePath, bytes);
        case 'm4a':
        case 'mp4':
        case 'aac':
          return _parseMp4(filePath, bytes);
        case 'wav':
          return _parseWav(filePath, bytes);
        case 'ogg':
          return _parseOgg(filePath, bytes);
        case 'ape':
          return _parseApe(filePath, bytes);
        default:
          return _fallback(filePath);
      }
    } catch (e) {
      return _fallback(filePath);
    }
  }

  // ---------------------------------------------------------------------------
  // FLAC
  // ---------------------------------------------------------------------------

  static LocalTrackMetadata _parseFlac(String path, Uint8List bytes) {
    if (bytes.length < 4 ||
        bytes[0] != 0x66 ||
        bytes[1] != 0x4C ||
        bytes[2] != 0x61 ||
        bytes[3] != 0x43) {
      return _fallback(path);
    }

    double duration = 0;
    String title = '';
    String artist = '';
    String album = '';
    String? lyric;
    String? coverDataUrl;

    int offset = 4;
    while (offset + 4 <= bytes.length) {
      final header = bytes[offset];
      final isLast = (header & 0x80) != 0;
      final blockType = header & 0x7F;
      final blockLength = _readUint24(bytes, offset + 1);

      if (offset + 4 + blockLength > bytes.length) break;

      final blockData = bytes.sublist(offset + 4, offset + 4 + blockLength);

      if (blockType == 0) {
        // STREAMINFO
        // bytes 0-15: min/max block & frame sizes
        // bytes 16-19: sample rate (20 bits) | channels (3 bits) | bps (5 bits)
        //   + total samples (36 bits)
        if (blockLength >= 18) {
          final sampleRate =
              (blockData[10] << 12) | (blockData[11] << 4) | (blockData[12] >> 4);
          final totalSamples =
              ((blockData[13] & 0x0F) << 32) |
              (blockData[14] << 24) |
              (blockData[15] << 16) |
              (blockData[16] << 8) |
              blockData[17];
          if (sampleRate > 0) {
            duration = totalSamples / sampleRate;
          }
        }
      } else if (blockType == 4) {
        // VORBIS_COMMENT
        final comments = _parseVorbisComment(blockData);
        title = comments['TITLE'] ?? title;
        artist = comments['ARTIST'] ?? artist;
        album = comments['ALBUM'] ?? album;
        lyric = comments['LYRICS'] ??
            comments['UNSYNCEDLYRICS'] ??
            comments['SYNCEDLYRICS'];
        coverDataUrl ??=
            _coverFromVorbisComments(comments);
      } else if (blockType == 6) {
        // PICTURE（内嵌封面）
        coverDataUrl ??= _parseFlacPictureBlock(blockData);
      }

      if (isLast) break;
      offset += 4 + blockLength;
    }

    return LocalTrackMetadata(
      filePath: path,
      name: title.isNotEmpty ? title : _baseName(path),
      artists: artist,
      album: album,
      duration: duration,
      coverDataUrl: coverDataUrl,
      lyric: lyric,
    );
  }

  // ---------------------------------------------------------------------------
  // MP3 (ID3v2 + MPEG 帧头)
  // ---------------------------------------------------------------------------

  static LocalTrackMetadata _parseMp3(String path, Uint8List bytes) {
    String title = '';
    String artist = '';
    String album = '';
    String? lyric;
    String? coverDataUrl;

    int audioStart = 0;

    // ID3v2
    if (bytes.length >= 10 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33) {
      final majorVersion = bytes[3];
      final tagSize = _syncsafeInt(bytes, 6);
      final tagEnd = 10 + tagSize;
      audioStart = tagEnd;

      final parsed = _parseId3v2Frames(
        bytes.sublist(10, tagEnd.clamp(0, bytes.length)),
        majorVersion,
      );
      title = parsed.text['TIT2'] ?? '';
      artist = parsed.text['TPE1'] ?? '';
      album = parsed.text['TALB'] ?? '';
      lyric = parsed.text['USLT'];
      coverDataUrl = parsed.coverDataUrl;
    }

    // 时长：遍历 MPEG 帧头估算
    final duration = _estimateMp3Duration(bytes, audioStart);

    return LocalTrackMetadata(
      filePath: path,
      name: title.isNotEmpty ? title : _baseName(path),
      artists: artist,
      album: album,
      duration: duration,
      coverDataUrl: coverDataUrl,
      lyric: lyric,
    );
  }

  static ({Map<String, String> text, String? coverDataUrl})
      _parseId3v2Frames(
    Uint8List tagData,
    int version,
  ) {
    final result = <String, String>{};
    String? coverDataUrl;
    int offset = 0;

    while (offset + 10 <= tagData.length) {
      String frameId;
      int frameSize;

      if (version >= 3) {
        // ID3v2.3/2.4: 4-byte frame ID, 4-byte size
        frameId = latin1.decode(tagData.sublist(offset, offset + 4),
            allowInvalid: true);
        if (version == 4) {
          frameSize = _syncsafeInt(tagData, offset + 4);
        } else {
          frameSize = _readUint32BE(tagData, offset + 4);
        }
        offset += 10; // 4 id + 4 size + 2 flags
      } else {
        // ID3v2.2: 3-byte frame ID, 3-byte size
        frameId = latin1.decode(tagData.sublist(offset, offset + 3),
            allowInvalid: true);
        frameSize =
            (tagData[offset + 3] << 16) |
            (tagData[offset + 4] << 8) |
            tagData[offset + 5];
        offset += 6; // 3 id + 3 size
      }

      // 帧ID全为零表示 padding
      if (frameId.codeUnits.every((c) => c == 0)) break;
      if (frameSize <= 0 || offset + frameSize > tagData.length) break;

      final frameData = tagData.sublist(offset, offset + frameSize);

      // 内嵌封面帧（ID3v2.2: PIC；ID3v2.3/2.4: APIC）
      if (frameId == 'APIC' || frameId == 'PIC') {
        coverDataUrl ??= _parseApicFrame(frameData, version);
      } else {
        // 映射 ID3v2.2 帧ID 到 2.3/2.4
        final normalizedId = _normalizeFrameId(frameId);
        final value = _parseId3v2FrameValue(frameData, normalizedId);
        if (value != null && value.isNotEmpty) {
          if (normalizedId == 'USLT') {
            result['USLT'] = value;
          } else {
            result[normalizedId] ??= value;
          }
        }
      }

      offset += frameSize;
    }

    return (text: result, coverDataUrl: coverDataUrl);
  }

  static String _normalizeFrameId(String id) {
    // ID3v2.2 → 2.3/2.4 映射
    const v22map = {
      'TT2': 'TIT2',
      'TP1': 'TPE1',
      'TAL': 'TALB',
      'ULT': 'USLT',
    };
    return v22map[id] ?? id;
  }

  static String? _parseId3v2FrameValue(Uint8List data, String frameId) {
    if (data.isEmpty) return null;

    if (frameId == 'USLT') {
      return _parseUsltFrame(data);
    }

    // 文本帧（T***）
    if (frameId.startsWith('T')) {
      return _decodeId3v2Text(data);
    }

    return null;
  }

  static String? _decodeId3v2Text(Uint8List data) {
    if (data.isEmpty) return null;
    final encoding = data[0];
    final textBytes = data.sublist(1);

    switch (encoding) {
      case 0x00: // ISO-8859-1
        return latin1.decode(textBytes, allowInvalid: true).trim();
      case 0x01: // UTF-16 with BOM
        return _decodeUtf16(textBytes);
      case 0x02: // UTF-16BE without BOM
        if (textBytes.length < 2) return null;
        return _decodeUtf16be(textBytes);
      case 0x03: // UTF-8
        return utf8.decode(textBytes, allowMalformed: true).trim();
      default:
        return utf8.decode(textBytes, allowMalformed: true).trim();
    }
  }

  static String? _parseUsltFrame(Uint8List data) {
    if (data.length < 5) return null;
    final encoding = data[0];
    // bytes 1-3: language (e.g. 'eng')
    // byte 4+: content descriptor (null-terminated) then lyrics text
    int offset = 4; // skip encoding + 3-byte language

    // skip content descriptor (null-terminated string in the frame's encoding)
    if (encoding == 0x01 || encoding == 0x02) {
      // UTF-16: null terminator is 0x00 0x00
      while (offset + 1 < data.length &&
          !(data[offset] == 0 && data[offset + 1] == 0)) {
        offset += 2;
      }
      offset += 2; // skip null terminator
    } else {
      // single-byte encoding
      while (offset < data.length && data[offset] != 0) {
        offset++;
      }
      offset++; // skip null terminator
    }

    if (offset >= data.length) return null;

    final lyricsBytes = data.sublist(offset);
    switch (encoding) {
      case 0x00:
        return latin1.decode(lyricsBytes, allowInvalid: true);
      case 0x01:
        return _decodeUtf16(lyricsBytes);
      case 0x02:
        return _decodeUtf16be(lyricsBytes);
      case 0x03:
        return utf8.decode(lyricsBytes, allowMalformed: true);
      default:
        return utf8.decode(lyricsBytes, allowMalformed: true);
    }
  }

  /// 解析 ID3v2 APIC（v2.3/2.4）或 PIC（v2.2）封面帧，返回 data URL。
  static String? _parseApicFrame(Uint8List data, int version) {
    if (data.length < 4) return null;
    final encoding = data[0];
    int offset = 1;
    String mime;

    if (version == 2) {
      // v2.2 PIC: 3 字节图片格式（JPG/PNG）
      if (data.length < 5) return null;
      final fmt = latin1.decode(data.sublist(1, 4), allowInvalid: true);
      mime = fmt.toLowerCase() == 'png'
          ? 'image/png'
          : fmt.toLowerCase() == 'jpg' || fmt.toLowerCase() == 'jpeg'
              ? 'image/jpeg'
              : 'image/$fmt';
      offset = 4;
    } else {
      // v2.3/2.4 APIC: null 结尾的 MIME 字符串
      while (offset < data.length && data[offset] != 0) {
        offset++;
      }
      if (offset >= data.length) return null;
      mime = latin1.decode(data.sublist(1, offset), allowInvalid: true);
      offset++; // 跳过 null
    }

    offset++; // 跳过 picture type 字节
    if (offset >= data.length) return null;

    // 跳过描述字符串（按帧编码区分定界符）
    offset = _skipId3v2String(data, offset, encoding);
    if (offset >= data.length) return null;

    final image = data.sublist(offset);
    final resolvedMime = mime.isNotEmpty ? mime : _sniffImageMime(image);
    if (resolvedMime == null) return null;
    return _pictureToDataUrl(image, resolvedMime);
  }

  /// 跳过 ID3v2 帧内 null 结尾的字符串（兼容单字节 / UTF-16 编码）。
  static int _skipId3v2String(Uint8List data, int offset, int encoding) {
    if (encoding == 0x01 || encoding == 0x02) {
      // UTF-16：以 2 字节 0x00 0x00 结尾，按 2 字节步进
      while (offset + 1 < data.length &&
          !(data[offset] == 0 && data[offset + 1] == 0)) {
        offset += 2;
      }
      offset += 2;
    } else {
      while (offset < data.length && data[offset] != 0) {
        offset++;
      }
      offset++;
    }
    return offset;
  }

  /// 通过扫描 MPEG 帧头估算 MP3 总时长。
  static double _estimateMp3Duration(Uint8List bytes, int startOffset) {
    final bitrates = [
      // MPEG 1, Layer 3
      [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0],
      // MPEG 2/2.5, Layer 3
      [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0],
    ];
    final sampleRates = [
      // MPEG 1
      [44100, 48000, 32000, 0],
      // MPEG 2
      [22050, 24000, 16000, 0],
      // MPEG 2.5
      [11025, 12000, 8000, 0],
    ];

    int offset = startOffset;
    double totalDuration = 0;
    int framesScanned = 0;
    const maxFrames = 100000; // 安全上限

    while (offset + 4 <= bytes.length && framesScanned < maxFrames) {
      // 寻找帧同步（11 位全 1）
      if (bytes[offset] != 0xFF || (bytes[offset + 1] & 0xE0) != 0xE0) {
        offset++;
        continue;
      }

      final versionBits = (bytes[offset + 1] >> 3) & 0x03; // 00=2.5, 01=reserved, 10=2, 11=1
      final layerBits = (bytes[offset + 1] >> 1) & 0x03; // 01=Layer3, 10=Layer2, 11=Layer1
      final bitrateIndex = (bytes[offset + 2] >> 4) & 0x0F;
      final sampleRateIndex = (bytes[offset + 2] >> 2) & 0x03;
      final padding = (bytes[offset + 2] >> 1) & 0x01;

      // 只处理 Layer 3
      if (layerBits != 0x01) {
        offset++;
        continue;
      }

      int versionIndex;
      switch (versionBits) {
        case 0x03:
          versionIndex = 0; // MPEG 1
          break;
        case 0x02:
          versionIndex = 1; // MPEG 2
          break;
        case 0x00:
          versionIndex = 1; // MPEG 2.5 (same bitrate table as MPEG 2)
          break;
        default:
          offset++;
          continue;
      }

      final bitrate = bitrates[versionIndex][bitrateIndex];
      final sampleRate = versionBits == 0x03
          ? sampleRates[0][sampleRateIndex]
          : versionBits == 0x02
              ? sampleRates[1][sampleRateIndex]
              : sampleRates[2][sampleRateIndex];

      if (bitrate == 0 || sampleRate == 0) {
        offset++;
        continue;
      }

      // 帧长度（Layer 3）= floor(144 * bitrate * 1000 / sampleRate) + padding
      final frameLength = (144 * bitrate * 1000) ~/ sampleRate + padding;
      if (frameLength <= 0) {
        offset++;
        continue;
      }

      // 每帧时长 ≈ 1152 samples / sample_rate
      totalDuration += 1152.0 / sampleRate;
      framesScanned++;
      offset += frameLength;
    }

    return totalDuration;
  }

  // ---------------------------------------------------------------------------
  // M4A / MP4 (ISOBMFF)
  // ---------------------------------------------------------------------------

  static LocalTrackMetadata _parseMp4(String path, Uint8List bytes) {
    double duration = 0;
    String title = '';
    String artist = '';
    String album = '';
    String? coverDataUrl;

    int offset = 0;
    while (offset + 8 <= bytes.length) {
      final size = _readUint32BE(bytes, offset);
      final type = latin1.decode(bytes.sublist(offset + 4, offset + 8),
          allowInvalid: true);

      if (size == 0) break;
      if (size < 8 || offset + size > bytes.length) {
        // 可能是 mdat 等大块，跳过
        if (size < 8) break;
        offset += size;
        continue;
      }

      if (type == 'moov') {
        final moovData = bytes.sublist(offset + 8, offset + size);
        final info = _parseMoov(moovData);
        duration = info.duration;
        title = info.title;
        artist = info.artist;
        album = info.album;
        coverDataUrl = info.coverDataUrl;
        break; // moov 包含了所有需要的信息
      }

      offset += size;
    }

    return LocalTrackMetadata(
      filePath: path,
      name: title.isNotEmpty ? title : _baseName(path),
      artists: artist,
      album: album,
      duration: duration,
      coverDataUrl: coverDataUrl,
    );
  }

  static ({
    double duration,
    String title,
    String artist,
    String album,
    String? coverDataUrl,
  }) _parseMoov(Uint8List moovData) {
    double duration = 0;
    String title = '';
    String artist = '';
    String album = '';
    String? coverDataUrl;

    int offset = 0;
    while (offset + 8 <= moovData.length) {
      final size = _readUint32BE(moovData, offset);
      final type = latin1.decode(moovData.sublist(offset + 4, offset + 8),
          allowInvalid: true);

      if (size < 8 || offset + size > moovData.length) break;

      if (type == 'mvhd') {
        final mvhdData = moovData.sublist(offset + 8, offset + size);
        duration = _parseMvhd(mvhdData);
      } else if (type == 'udta') {
        final udtaData = moovData.sublist(offset + 8, offset + size);
        final parsed = _parseUdtaIlst(udtaData);
        title = parsed.tags['©nam'] ?? '';
        artist = parsed.tags['©ART'] ?? '';
        album = parsed.tags['©alb'] ?? '';
        coverDataUrl = parsed.coverDataUrl;
      }

      offset += size;
    }

    return (
      duration: duration,
      title: title,
      artist: artist,
      album: album,
      coverDataUrl: coverDataUrl,
    );
  }

  static double _parseMvhd(Uint8List data) {
    if (data.length < 4) return 0;
    final version = data[0];
    int timescale;
    int durationInTimescale;

    if (version == 0) {
      if (data.length < 24) return 0;
      timescale = _readUint32BE(data, 12);
      durationInTimescale = _readUint32BE(data, 16);
    } else {
      if (data.length < 36) return 0;
      timescale = _readUint32BE(data, 20);
      durationInTimescale = _readUint32BE(data, 24);
    }

    if (timescale == 0) return 0;
    return durationInTimescale / timescale;
  }

  static ({Map<String, String> tags, String? coverDataUrl}) _parseUdtaIlst(
    Uint8List udtaData,
  ) {
    final tags = <String, String>{};
    String? coverDataUrl;
    int offset = 0;

    // udta → ilst → 各标签 atom
    while (offset + 8 <= udtaData.length) {
      final size = _readUint32BE(udtaData, offset);
      final type = latin1.decode(udtaData.sublist(offset + 4, offset + 8),
          allowInvalid: true);

      if (size < 8 || offset + size > udtaData.length) break;

      if (type == 'ilst') {
        // 遍历 ilst 子 atom
        int ilstOffset = offset + 8;
        final ilstEnd = offset + size;
        while (ilstOffset + 8 <= ilstEnd) {
          final tagSize = _readUint32BE(udtaData, ilstOffset);
          final tagType = latin1.decode(
            udtaData.sublist(ilstOffset + 4, ilstOffset + 8),
            allowInvalid: true,
          );

          if (tagSize < 8 || ilstOffset + tagSize > ilstEnd) break;

          // 标签 atom 内含 'data' atom
          final tagData = udtaData.sublist(ilstOffset + 8, ilstOffset + tagSize);
          if (tagType == 'covr') {
            // 封面：data atom flags=13(PNG) / 14(JPEG) / 21(JPEG)
            coverDataUrl ??= _parseCoverDataAtom(tagData);
          } else {
            final value = _parseIlstDataAtom(tagType, tagData);
            if (value != null) {
              tags[tagType] ??= value;
            }
          }

          ilstOffset += tagSize;
        }
      }

      offset += size;
    }

    return (tags: tags, coverDataUrl: coverDataUrl);
  }

  /// 解析 M4A covr 封面 data atom，返回 data URL。
  static String? _parseCoverDataAtom(Uint8List tagData) {
    int offset = 0;
    while (offset + 8 <= tagData.length) {
      final size = _readUint32BE(tagData, offset);
      final type = latin1.decode(tagData.sublist(offset + 4, offset + 8),
          allowInvalid: true);

      if (size < 8 || offset + size > tagData.length) break;

      if (type == 'data' && size > 16) {
        final flags = _readUint32BE(tagData, offset + 8);
        final payload = tagData.sublist(offset + 16, offset + size);

        String? mime;
        if (flags == 13) {
          mime = 'image/png';
        } else if (flags == 14 || flags == 21) {
          mime = 'image/jpeg';
        } else {
          mime = _sniffImageMime(payload);
        }
        if (mime != null && payload.isNotEmpty) {
          return _pictureToDataUrl(payload, mime);
        }
      }

      offset += size;
    }
    return null;
  }

  static String? _parseIlstDataAtom(String tagType, Uint8List tagData) {
    int offset = 0;
    while (offset + 8 <= tagData.length) {
      final size = _readUint32BE(tagData, offset);
      final type = latin1.decode(tagData.sublist(offset + 4, offset + 8),
          allowInvalid: true);

      if (size < 8 || offset + size > tagData.length) break;

      if (type == 'data' && size > 16) {
        // data atom: 4 bytes flags + 4 bytes reserved + payload
        final flags = _readUint32BE(tagData, offset + 8);
        final payload = tagData.sublist(offset + 16, offset + size);

        // flags=1 → UTF-8 text, flags=21 → JPEG, flags=13 → PNG, flags=0 → integer
        if (flags == 1) {
          return utf8.decode(payload, allowMalformed: true).trim();
        }
      }

      offset += size;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // WAV (RIFF)
  // ---------------------------------------------------------------------------

  static LocalTrackMetadata _parseWav(String path, Uint8List bytes) {
    double duration = 0;

    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && // R
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46 && // F
        bytes[3] == 0x46 && // F
        bytes[8] == 0x57 && // W
        bytes[9] == 0x41 && // A
        bytes[10] == 0x56 && // V
        bytes[11] == 0x45) { // E

      int offset = 12;
      int sampleRate = 0;
      int channels = 0;
      int bitsPerSample = 0;
      int dataSize = 0;

      while (offset + 8 <= bytes.length) {
        final chunkId = latin1.decode(bytes.sublist(offset, offset + 4),
            allowInvalid: true);
        final chunkSize = _readUint32LE(bytes, offset + 4);

        if (chunkId == 'fmt ' && chunkSize >= 16 && offset + 8 + 16 <= bytes.length) {
          final fmtData = bytes.sublist(offset + 8, offset + 8 + 16);
          channels = _readUint16LE(fmtData, 2);
          sampleRate = _readUint32LE(fmtData, 4);
          bitsPerSample = _readUint16LE(fmtData, 14);
        } else if (chunkId == 'data') {
          dataSize = chunkSize;
        }

        if (chunkSize == 0) break;
        offset += 8 + chunkSize;
        // chunks are word-aligned
        if (chunkSize.isOdd) offset++;
      }

      if (sampleRate > 0 && channels > 0 && bitsPerSample > 0 && dataSize > 0) {
        final bytesPerSecond = sampleRate * channels * (bitsPerSample ~/ 8);
        if (bytesPerSecond > 0) {
          duration = dataSize / bytesPerSecond;
        }
      }
    }

    return LocalTrackMetadata(
      filePath: path,
      name: _baseName(path),
      artists: '',
      album: '',
      duration: duration,
    );
  }

  // ---------------------------------------------------------------------------
  // OGG (Vorbis)
  // ---------------------------------------------------------------------------

  static LocalTrackMetadata _parseOgg(String path, Uint8List bytes) {
    double duration = 0;
    String title = '';
    String artist = '';
    String album = '';
    String? lyric;
    String? coverDataUrl;

    // Vorbis: 第 1 个 packet = identification header
    //         第 2 个 packet = comment header
    //         第 3 个 packet = setup header
    // OGG 页面结构: 'OggS' + 27 bytes header + segments

    int offset = 0;
    int packetIndex = 0;
    int sampleRate = 0;
    int? lastGranule;

    while (offset + 27 <= bytes.length) {
      // OGG page header
      if (bytes[offset] != 0x4F || // O
          bytes[offset + 1] != 0x67 || // g
          bytes[offset + 2] != 0x67 || // g
          bytes[offset + 3] != 0x53) { // S
        break;
      }

      final numSegments = bytes[offset + 26];
      final headerSize = 27 + numSegments;
      if (offset + headerSize > bytes.length) break;

      final segmentTable = bytes.sublist(offset + 27, offset + headerSize);
      final granulePos = _readUint64LE(bytes, offset + 6);
      if (granulePos > 0) lastGranule = granulePos;

      // 计算本页所有 segment 的总大小
      int pageDataSize = 0;
      for (final s in segmentTable) {
        pageDataSize += s;
      }

      final pageData = bytes.sublist(
        offset + headerSize,
        (offset + headerSize + pageDataSize).clamp(0, bytes.length),
      );

      // 拼接本页的所有 segment 成 packet（简化：只处理每页完整 packet 的情况）
      int segOffset = 0;
      for (final segLen in segmentTable) {
        if (segLen == 0) continue;
        if (segOffset + segLen > pageData.length) break;

        final segment = pageData.sublist(segOffset, segOffset + segLen);
        segOffset += segLen;

        // Vorbis identification header: 0x01 + 'vorbis'
        if (packetIndex == 0 &&
            segment.length >= 30 &&
            segment[0] == 0x01 &&
            segment[1] == 0x76 && // v
            segment[2] == 0x6F && // o
            segment[3] == 0x72 && // r
            segment[4] == 0x62 && // b
            segment[5] == 0x69 && // i
            segment[6] == 0x73) {
          sampleRate = _readUint32LE(segment, 12);
        }

        // Vorbis comment header: 0x03 + 'vorbis'
        if (packetIndex == 1 &&
            segment.length >= 7 &&
            segment[0] == 0x03 &&
            segment[1] == 0x76 && // v
            segment[2] == 0x6F && // o
            segment[3] == 0x72 && // r
            segment[4] == 0x62 && // b
            segment[5] == 0x69 && // i
            segment[6] == 0x73) {
          final comments = _parseVorbisComment(
            segment.sublist(7),
          );
          title = comments['TITLE'] ?? '';
          artist = comments['ARTIST'] ?? '';
          album = comments['ALBUM'] ?? '';
          lyric = comments['LYRICS'] ??
              comments['UNSYNCEDLYRICS'] ??
              comments['SYNCEDLYRICS'];
          coverDataUrl ??= _coverFromVorbisComments(comments);
        }

        // 简化处理：最后一个 segment < 255 表示 packet 结束
        packetIndex++;
        if (segLen < 255) {
          // packet complete
        }
      }

      offset += headerSize + pageDataSize;
    }

    if (lastGranule != null && sampleRate > 0) {
      duration = lastGranule / sampleRate;
    }

    return LocalTrackMetadata(
      filePath: path,
      name: title.isNotEmpty ? title : _baseName(path),
      artists: artist,
      album: album,
      duration: duration,
      coverDataUrl: coverDataUrl,
      lyric: lyric,
    );
  }

  // ---------------------------------------------------------------------------
  // APE (Monkey's Audio)
  // ---------------------------------------------------------------------------

  static LocalTrackMetadata _parseApe(String path, Uint8List bytes) {
    String title = '';
    String artist = '';
    String album = '';
    String? lyric;
    String? coverDataUrl;
    double duration = 0;

    // MAC 头部在文件开头：'MAC ' + version
    // APEv2 标签在文件末尾：'APETAGEX'
    // 时长 = 总帧数 / 每秒帧数，可从 MAC 头部读取

    // 解析 MAC 头部获取时长
    if (bytes.length >= 56 &&
        bytes[0] == 0x4D && // M
        bytes[1] == 0x41 && // A
        bytes[2] == 0x43 && // C
        bytes[3] == 0x20) { // (space)
      final version = _readUint16LE(bytes, 4);
      // 不同版本头部结构不同，这里只尝试常见版本 (>=3.97)
      if (version >= 3970 && bytes.length >= 56) {
        // APEDescriptor: 52 bytes
        // APEHeader (at offset 52): 24 bytes
        //   offset 0: version (2 bytes)
        //   offset 4: totalFrames (4 bytes)
        //   offset 8: finalFrameBlocks (4 bytes)
        //   offset 16: sampleRate (4 bytes)
        final totalFrames = _readUint32LE(bytes, 52 + 4);
        final finalFrameBlocks = _readUint32LE(bytes, 52 + 8);
        final sampleRate = _readUint32LE(bytes, 52 + 16);
        final blocksPerFrame = version >= 3980 ? 73728 * 4 : 73728;
        if (sampleRate > 0) {
          final totalBlocks = (totalFrames > 0 ? (totalFrames - 1) : 0) * blocksPerFrame + finalFrameBlocks;
          duration = totalBlocks / sampleRate;
        }
      }
    }

    // 解析 APEv2 标签（从文件末尾搜索 'APETAGEX'）
    final tagData = _findApeTag(bytes);
    if (tagData != null) {
      final parsed = _parseApev2Tag(tagData);
      title = parsed.tags['Title'] ?? '';
      artist = parsed.tags['Artist'] ?? '';
      album = parsed.tags['Album'] ?? '';
      lyric = parsed.tags['Lyrics'] ?? parsed.tags['UNSYNCED LYRICS'];
      coverDataUrl = parsed.coverDataUrl;
    }

    return LocalTrackMetadata(
      filePath: path,
      name: title.isNotEmpty ? title : _baseName(path),
      artists: artist,
      album: album,
      duration: duration,
      coverDataUrl: coverDataUrl,
      lyric: lyric,
    );
  }

  static Uint8List? _findApeTag(Uint8List bytes) {
    // APEv2 标签从文件末尾开始查找，标志为 'APETAGEX'（8 字节）
    const tagStart = [0x41, 0x50, 0x45, 0x54, 0x41, 0x47, 0x45, 0x58]; // APETAGEX
    final searchStart = bytes.length > 1 << 20 ? bytes.length - (1 << 20) : 0;

    for (int i = bytes.length - 32; i >= searchStart; i--) {
      if (i < 0) break;
      bool match = true;
      for (int j = 0; j < 8; j++) {
        if (bytes[i + j] != tagStart[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        // APEv2 footer: 32 bytes header
        //   0-7: 'APETAGEX'
        //   8-11: version (4 bytes LE)
        //   12-15: tag size (4 bytes LE, includes footer)
        //   16-19: item count (4 bytes LE)
        //   20-23: flags (4 bytes LE, bit 30 = has header)
        //   24-31: reserved
        if (i + 32 > bytes.length) return null;
        final tagSize = _readUint32LE(bytes, i + 12);
        final flags = _readUint32LE(bytes, i + 20);
        final hasHeader = (flags & (1 << 31)) != 0;

        final startOffset = hasHeader ? i - (tagSize - 32) : i;
        if (startOffset < 0 || startOffset + tagSize > bytes.length) {
          return bytes.sublist(i, bytes.length);
        }
        return bytes.sublist(startOffset, startOffset + tagSize);
      }
    }
    return null;
  }

  static ({Map<String, String> tags, String? coverDataUrl}) _parseApev2Tag(
    Uint8List tagData,
  ) {
    final tags = <String, String>{};
    String? coverDataUrl;

    // 跳过 footer 或 header（32 bytes）
    // 找到 'APETAGEX' 起始位置
    int tagStart = 0;
    for (int i = 0; i < tagData.length - 8; i++) {
      if (tagData[i] == 0x41 && // A
          tagData[i + 1] == 0x50 && // P
          tagData[i + 2] == 0x45 && // E
          tagData[i + 3] == 0x54 && // T
          tagData[i + 4] == 0x41 && // A
          tagData[i + 5] == 0x47 && // G
          tagData[i + 6] == 0x45 && // E
          tagData[i + 7] == 0x58) { // X
        tagStart = i;
        break;
      }
    }

    // 如果有 header，从 header 之后开始读 items；否则从 footer 之前
    final flags = _readUint32LE(tagData, tagStart + 20);
    final hasHeader = (flags & (1 << 31)) != 0;
    final tagSize = _readUint32LE(tagData, tagStart + 12);
    final itemCount = _readUint32LE(tagData, tagStart + 16);

    int itemsStart;
    int itemsEnd;
    if (hasHeader) {
      itemsStart = tagStart + 32; // after header
      itemsEnd = tagStart + tagSize - 32; // before footer
    } else {
      itemsStart = tagStart + 32;
      itemsEnd = tagStart + tagSize - 32;
    }

    int offset = itemsStart;
    for (int i = 0; i < itemCount && offset < itemsEnd; i++) {
      if (offset + 8 > itemsEnd) break;
      final itemSize = _readUint32LE(tagData, offset);
      offset += 4;
      offset += 4; // item flags

      // 读取 key（UTF-8，以 \0 结尾）
      int keyEnd = offset;
      while (keyEnd < itemsEnd && tagData[keyEnd] != 0) {
        keyEnd++;
      }
      final key = utf8.decode(tagData.sublist(offset, keyEnd),
          allowMalformed: true);
      offset = keyEnd + 1; // skip null terminator

      if (offset + itemSize > itemsEnd) break;

      // 封面项：原始二进制（常见），或 base64 文本（APEv2 flags 带二进制标记时）
      final upperKey = key.toUpperCase();
      if (upperKey == 'COVER ART (FRONT)' || upperKey == 'COVERART') {
        final rawValue = tagData.sublist(offset, offset + itemSize);
        var mime = _sniffImageMime(rawValue);
        if (mime != null) {
          coverDataUrl ??= _pictureToDataUrl(rawValue, mime);
        } else {
          // 尝试 base64 文本
          try {
            final text = utf8.decode(rawValue, allowMalformed: true).trim();
            final decoded = base64Decode(text);
            mime = _sniffImageMime(decoded);
            if (mime != null) {
              coverDataUrl ??= _pictureToDataUrl(decoded, mime);
            }
          } catch (_) {
            // 无法解析，忽略
          }
        }
      }

      final value = utf8.decode(tagData.sublist(offset, offset + itemSize),
          allowMalformed: true);
      tags[key] ??= value;
      offset += itemSize;
    }

    return (tags: tags, coverDataUrl: coverDataUrl);
  }

  // ---------------------------------------------------------------------------
  // Vorbis Comment 通用解析（FLAC / OGG 共用）
  // ---------------------------------------------------------------------------

  static Map<String, String> _parseVorbisComment(Uint8List block) {
    final result = <String, String>{};
    int offset = 0;

    // Vendor string length (LE 32) + vendor string
    if (offset + 4 > block.length) return result;
    final vendorLength = _readUint32LE(block, offset);
    offset += 4;
    if (offset + vendorLength > block.length) return result;
    offset += vendorLength;

    // Comment count (LE 32)
    if (offset + 4 > block.length) return result;
    final commentCount = _readUint32LE(block, offset);
    offset += 4;

    for (int i = 0; i < commentCount && offset + 4 <= block.length; i++) {
      final commentLength = _readUint32LE(block, offset);
      offset += 4;
      if (offset + commentLength > block.length) break;

      final comment = utf8.decode(block.sublist(offset, offset + commentLength),
          allowMalformed: true);
      offset += commentLength;

      final eqIndex = comment.indexOf('=');
      if (eqIndex <= 0) continue;
      final key = comment.substring(0, eqIndex).toUpperCase();
      final value = comment.substring(eqIndex + 1);
      result[key] ??= value; // 取第一个值
    }

    return result;
  }

  /// 从 Vorbis Comments 中提取封面（FLAC / OGG 共用）。
  ///
  /// - `METADATA_BLOCK_PICTURE`：base64 编码的 FLAC picture block
  /// - `COVERART`：base64 编码的原始图片数据（无 MIME 信息，需探测）
  static String? _coverFromVorbisComments(Map<String, String> comments) {
    final picture = comments['METADATA_BLOCK_PICTURE'];
    if (picture != null && picture.isNotEmpty) {
      try {
        final bytes = base64Decode(picture);
        final dataUrl = _parseFlacPictureBlock(bytes);
        if (dataUrl != null) return dataUrl;
      } catch (_) {
        // base64 解码失败，尝试下一个来源
      }
    }

    final coverArt = comments['COVERART'];
    if (coverArt != null && coverArt.isNotEmpty) {
      try {
        final bytes = base64Decode(coverArt);
        final mime = _sniffImageMime(bytes);
        if (mime != null) return _pictureToDataUrl(bytes, mime);
      } catch (_) {
        // 忽略
      }
    }

    return null;
  }

  /// 解析 FLAC METADATA_BLOCK_PICTURE 块，返回 data URL。
  ///
  /// 块结构：picture type(4) + MIME 长度(4) + MIME + 描述长度(4) + 描述
  ///         + 宽(4) + 高(4) + 位深(4) + 颜色数(4) + 数据长度(4) + 图片数据
  static String? _parseFlacPictureBlock(Uint8List block) {
    if (block.length < 8) return null;
    int offset = 4; // 跳过 picture type

    final mimeLen = _readUint32BE(block, offset);
    offset += 4;
    if (offset + mimeLen > block.length) return null;
    final mime = latin1.decode(
      block.sublist(offset, offset + mimeLen),
      allowInvalid: true,
    );
    offset += mimeLen;

    if (offset + 4 > block.length) return null;
    final descLen = _readUint32BE(block, offset);
    offset += 4;
    if (offset + descLen > block.length) return null;
    offset += descLen; // 跳过描述（UTF-8）

    // 宽(4) + 高(4) + 位深(4) + 颜色数(4)
    if (offset + 16 + 4 > block.length) return null;
    offset += 16;

    final dataLen = _readUint32BE(block, offset);
    offset += 4;
    if (offset + dataLen > block.length || dataLen <= 0) return null;

    final image = block.sublist(offset, offset + dataLen);
    final resolvedMime = mime.isNotEmpty ? mime : _sniffImageMime(image);
    if (resolvedMime == null) return null;
    return _pictureToDataUrl(image, resolvedMime);
  }

  /// 将图片字节编码为 data URL。
  static String? _pictureToDataUrl(Uint8List data, String mime) {
    if (data.isEmpty) return null;
    return 'data:$mime;base64,${base64Encode(data)}';
  }

  /// 通过文件头探测图片 MIME 类型。
  static String? _sniffImageMime(Uint8List data) {
    if (data.length >= 8 &&
        data[0] == 0x89 &&
        data[1] == 0x50 &&
        data[2] == 0x4E &&
        data[3] == 0x47) {
      return 'image/png';
    }
    if (data.length >= 3 &&
        data[0] == 0xFF &&
        data[1] == 0xD8 &&
        data[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (data.length >= 6 &&
        data[0] == 0x47 && // G
        data[1] == 0x49 && // I
        data[2] == 0x46 && // F
        data[3] == 0x38) {
      return 'image/gif';
    }
    if (data.length >= 4 && data[0] == 0x42 && data[1] == 0x4D) {
      return 'image/bmp'; // 'BM'
    }
    if (data.length >= 12 &&
        data[0] == 0x52 && // R
        data[1] == 0x49 && // I
        data[2] == 0x46 && // F
        data[3] == 0x46 &&
        data[8] == 0x57 && // W
        data[9] == 0x45 && // E
        data[10] == 0x42 && // B
        data[11] == 0x50) {
      return 'image/webp'; // 'RIFF' + 'WEBP'
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // 辅助方法
  // ---------------------------------------------------------------------------

  static LocalTrackMetadata _fallback(String path) {
    return LocalTrackMetadata(
      filePath: path,
      name: _baseName(path),
      artists: '',
      album: '',
      duration: 0,
    );
  }

  static String _extension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  static String _baseName(String path) {
    // 去掉扩展名和路径
    final slash = path.lastIndexOf(Platform.pathSeparator);
    var name = slash >= 0 ? path.substring(slash + 1) : path;
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    return name;
  }

  static int _readUint16LE(Uint8List data, int offset) {
    return data[offset] | (data[offset + 1] << 8);
  }

  static int _readUint32LE(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  static int _readUint32BE(Uint8List data, int offset) {
    return (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
  }

  static int _readUint24(Uint8List data, int offset) {
    return (data[offset] << 16) | (data[offset + 1] << 8) | data[offset + 2];
  }

  static int _readUint64LE(Uint8List data, int offset) {
    // 只取低 32 位（时长不会超过 2^32 samples）
    var result = 0;
    for (int i = 7; i >= 0; i--) {
      if (offset + i < data.length) {
        result = (result << 8) | data[offset + i];
      }
    }
    return result;
  }

  static int _syncsafeInt(Uint8List data, int offset) {
    return ((data[offset] & 0x7F) << 21) |
        ((data[offset + 1] & 0x7F) << 14) |
        ((data[offset + 2] & 0x7F) << 7) |
        (data[offset + 3] & 0x7F);
  }

  static String? _decodeUtf16(Uint8List data) {
    if (data.length < 2) return null;
    // 检查 BOM
    if (data[0] == 0xFF && data[1] == 0xFE) {
      return _decodeUtf16le(data.sublist(2));
    } else if (data[0] == 0xFE && data[1] == 0xFF) {
      return _decodeUtf16be(data.sublist(2));
    }
    return _decodeUtf16le(data);
  }

  static String? _decodeUtf16le(Uint8List data) {
    if (data.isEmpty) return null;
    final codeUnits = <int>[];
    for (int i = 0; i + 1 < data.length; i += 2) {
      codeUnits.add(data[i] | (data[i + 1] << 8));
    }
    // 去掉末尾的 null
    while (codeUnits.isNotEmpty && codeUnits.last == 0) {
      codeUnits.removeLast();
    }
    return String.fromCharCodes(codeUnits).trim();
  }

  static String? _decodeUtf16be(Uint8List data) {
    if (data.isEmpty) return null;
    final codeUnits = <int>[];
    for (int i = 0; i + 1 < data.length; i += 2) {
      codeUnits.add((data[i] << 8) | data[i + 1]);
    }
    while (codeUnits.isNotEmpty && codeUnits.last == 0) {
      codeUnits.removeLast();
    }
    return String.fromCharCodes(codeUnits).trim();
  }
}
