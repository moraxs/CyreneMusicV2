import '../../../../domain/models/music_source.dart';
import '../../../../domain/models/track.dart';

/// 歌曲详情模型
class SongDetail {
  final dynamic id; // 支持 int 和 String（网易云用int，QQ和酷狗用String）
  final String name;
  final String pic;
  final String arName; // 艺术家名称
  final String alName; // 专辑名称
  final String level; // 音质
  final String size; // 文件大小
  final String url; // 播放链接
  final String lyric; // 歌词
  final String tlyric; // 翻译歌词
  final String yrc; // 逐字歌词（网易云YRC格式）
  final String ytlrc; // YRC对应的翻译歌词（时间戳与YRC匹配）
  final String qrc; // QQ音乐逐字歌词（QRC格式）
  final String qrcTrans; // QRC对应的翻译歌词
  final String? decryptionKey; // 解密密钥（用于 Amazon Music 等加密流）
  final MusicSource source;

  SongDetail({
    required this.id,
    required this.name,
    required this.pic,
    required this.arName,
    required this.alName,
    required this.level,
    required this.size,
    required this.url,
    required this.lyric,
    required this.tlyric,
    this.yrc = '',
    this.ytlrc = '',
    this.qrc = '',
    this.qrcTrans = '',
    this.decryptionKey,
    this.source = MusicSource.netease,
  });

  /// 从 JSON 创建 SongDetail 对象
  factory SongDetail.fromJson(Map<String, dynamic> json, {MusicSource? source}) {
    // 🔧 安全获取歌词字段（兼容网易云和QQ音乐格式）
    String lyricText = '';
    String tlyricText = '';
    String yrcText = '';
    String qrcText = '';
    String qrcTransText = '';
    String ytlrcText = '';

    // 网易云音乐格式：lyric 和 tlyric 直接是字符串
    // QQ音乐格式：可能是 Map（不应该直接传入，但做防御性处理）
    final lyricValue = json['lyric'];
    final tlyricValue = json['tlyric'];
    final yrcValue = json['yrc'];

    if (lyricValue is String) {
      lyricText = lyricValue;
    } else if (lyricValue is Map) {
      // QQ音乐格式：{lyric: string, tylyric: string}
      lyricText = (lyricValue['lyric'] is String) ? lyricValue['lyric'] : '';
    }

    if (tlyricValue is String) {
      tlyricText = tlyricValue;
    } else if (tlyricValue is Map) {
      // QQ音乐格式
      tlyricText = (tlyricValue['tylyric'] is String) ? tlyricValue['tylyric'] : '';
    }

    if (yrcValue is String) {
      yrcText = yrcValue;
    }

    // 解析 YRC 对应的翻译歌词
    final ytlrcValue = json['ytlrc'];
    if (ytlrcValue is String) {
      ytlrcText = ytlrcValue;
    }

    // 解析 QQ 音乐 QRC 逐字歌词
    final qrcValue = json['qrc'];
    if (qrcValue is String) {
      qrcText = qrcValue;
    }

    // 解析 QRC 对应的翻译歌词
    final qrcTransValue = json['qrcTrans'];
    if (qrcTransValue is String) {
      qrcTransText = qrcTransValue;
    }

    return SongDetail(
      id: json['id'] ?? 0, // 支持 int 和 String
      name: json['name'] as String? ?? '',
      pic: json['pic'] as String? ?? '',
      arName: json['ar_name'] as String? ?? '',
      alName: json['al_name'] as String? ?? '',
      level: json['level'] as String? ?? '',
      size: json['size'] as String? ?? '',
      url: json['url'] as String? ?? '',
      lyric: lyricText,
      tlyric: tlyricText,
      yrc: yrcText,
      ytlrc: ytlrcText,
      qrc: qrcText,
      qrcTrans: qrcTransText,
      decryptionKey: json['decryptionKey'] as String?,
      source: source ?? MusicSource.netease,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'pic': pic,
      'ar_name': arName,
      'al_name': alName,
      'level': level,
      'size': size,
      'url': url,
      'lyric': lyric,
      'tlyric': tlyric,
      'decryptionKey': decryptionKey,
      'source': source.name,
    };
  }

  /// 转换为 Track 对象
  Track toTrack() {
    return Track(
      id: id.toString(),
      name: name,
      artists: arName,
      album: alName,
      picUrl: pic,
      source: source,
    );
  }

  /// 兼容层：由新架构的 [Track]（歌词已在解析音源时随附）合成歌曲详情。
  factory SongDetail.fromTrack(Track track) {
    final isQQ = track.source == MusicSource.qq;
    return SongDetail(
      id: track.id,
      name: track.name,
      pic: track.picUrl,
      arName: track.artists,
      alName: track.album,
      level: '',
      size: '',
      url: track.playbackUrl?.toString() ?? '',
      lyric: track.lyric ?? '',
      tlyric: track.tlyric ?? '',
      // 新架构统一把逐字歌词放在 yrc/ytlrc 字段（QQ 的 QRC 也在其中）。
      yrc: isQQ ? '' : (track.yrc ?? ''),
      ytlrc: isQQ ? '' : (track.ytlrc ?? ''),
      qrc: isQQ ? (track.yrc ?? '') : '',
      qrcTrans: isQQ ? (track.ytlrc ?? '') : '',
      source: track.source,
    );
  }
}

/// 音质等级枚举
enum AudioQuality {
  standard,  // 标准
  exhigh,    // 极高
  lossless,  // 无损
  hires,     // Hi-Res
  jyeffect,  // 高清环绕声
  sky,       // 沉浸环绕声
  jymaster,  // 超清母带
}

extension AudioQualityExtension on AudioQuality {
  String get value {
    switch (this) {
      case AudioQuality.standard:
        return 'standard';
      case AudioQuality.exhigh:
        return 'exhigh';
      case AudioQuality.lossless:
        return 'lossless';
      case AudioQuality.hires:
        return 'hires';
      case AudioQuality.jyeffect:
        return 'jyeffect';
      case AudioQuality.sky:
        return 'sky';
      case AudioQuality.jymaster:
        return 'jymaster';
    }
  }

  String get displayName {
    switch (this) {
      case AudioQuality.standard:
        return '标准音质';
      case AudioQuality.exhigh:
        return '极高音质';
      case AudioQuality.lossless:
        return '无损音质';
      case AudioQuality.hires:
        return 'Hi-Res';
      case AudioQuality.jyeffect:
        return 'Audio Vivid';
      case AudioQuality.sky:
        return '沉浸环绕声';
      case AudioQuality.jymaster:
        return '超清母带';
    }
  }

  String get extension {
    switch (this) {
      case AudioQuality.lossless:
      case AudioQuality.hires:
      case AudioQuality.jyeffect:
      case AudioQuality.jymaster:
        return 'flac';
      default:
        return 'mp3';
    }
  }
}

