import '../models/music_source.dart';
import '../models/track.dart';

/// 房间里的一位听众。
class TogetherMember {
  const TogetherMember({
    required this.id,
    required this.name,
    this.userId,
    this.avatar = '',
    this.isHost = false,
  });

  final String id;
  final int? userId;
  final String name;
  final String avatar;
  final bool isHost;

  factory TogetherMember.fromJson(Map<String, Object?> json) => TogetherMember(
    id: json['id']?.toString() ?? '',
    userId: (json['userId'] as num?)?.toInt(),
    name: json['name']?.toString() ?? '听众',
    avatar: json['avatar']?.toString() ?? '',
    isHost: json['isHost'] == true,
  );
}

/// 一条弹幕 / 房间消息。
class TogetherChatMessage {
  const TogetherChatMessage({
    required this.id,
    required this.name,
    required this.text,
    this.memberId = '',
    this.userId,
    this.avatar = '',
    this.positionMs = 0,
    required this.createdAt,
    this.isSystem = false,
  });

  final String id;
  final String memberId;
  final int? userId;
  final String name;
  final String avatar;
  final String text;

  /// 发言时房间的播放进度，用于把弹幕对齐到歌曲时间轴。
  final int positionMs;
  final DateTime createdAt;

  /// 系统提示。两个来源：本地生成的（谁进来了、房主离开了），以及服务端下发的
  /// 房间日志（谁点了哪首歌，带 `system: true`）。两者都不飘弹幕，只在消息
  /// 列表里居中显示。
  final bool isSystem;

  factory TogetherChatMessage.fromJson(Map<String, Object?> json) =>
      TogetherChatMessage(
        id: json['id']?.toString() ?? '',
        memberId: json['memberId']?.toString() ?? '',
        userId: (json['userId'] as num?)?.toInt(),
        name: json['name']?.toString() ?? '听众',
        avatar: json['avatar']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['createdAt'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        ),
        isSystem: json['system'] == true,
      );

  factory TogetherChatMessage.system(String text) => TogetherChatMessage(
    id: 'sys-${DateTime.now().microsecondsSinceEpoch}',
    name: '',
    text: text,
    createdAt: DateTime.now(),
    isSystem: true,
  );
}

/// 房间里正在播的那首歌。
///
/// 只同步「哪首歌」，不同步音频地址——每台设备用自己的音源和音质各自取流，
/// 所以房主的 Premium 音源不会外泄，听众没有音源时也不至于把房间卡住。
class TogetherTrack {
  const TogetherTrack({
    required this.id,
    required this.name,
    required this.artists,
    required this.album,
    required this.picUrl,
    required this.source,
    this.durationMs = 0,
  });

  final String id;
  final String name;
  final String artists;
  final String album;
  final String picUrl;
  final String source;
  final int durationMs;

  factory TogetherTrack.fromTrack(Track track) => TogetherTrack(
    id: track.id,
    name: track.name,
    artists: track.artists,
    album: track.album,
    picUrl: track.picUrl,
    source: track.source.wireName,
    durationMs: track.duration?.inMilliseconds ?? 0,
  );

  static TogetherTrack? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, Object?>.from(raw);
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    return TogetherTrack(
      id: id,
      name: json['name']?.toString() ?? '',
      artists: json['artists']?.toString() ?? '',
      album: json['album']?.toString() ?? '',
      picUrl: json['picUrl']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'artists': artists,
    'album': album,
    'picUrl': picUrl,
    'source': source,
    'durationMs': durationMs,
  };

  Track toTrack() => Track(
    id: id,
    name: name,
    artists: artists,
    album: album,
    picUrl: picUrl,
    source: MusicSource.fromWireName(source),
    duration: durationMs > 0 ? Duration(milliseconds: durationMs) : null,
  );

  String get key => '$source:$id';
}

/// 大厅里的一个公开房间。
class TogetherRoomSummary {
  const TogetherRoomSummary({
    required this.code,
    required this.hostName,
    required this.listeners,
    this.hostAvatar = '',
    this.track,
    this.isPlaying = false,
  });

  final String code;
  final String hostName;
  final String hostAvatar;
  final int listeners;
  final TogetherTrack? track;
  final bool isPlaying;

  factory TogetherRoomSummary.fromJson(Map<String, Object?> json) =>
      TogetherRoomSummary(
        code: json['code']?.toString() ?? '',
        hostName: json['hostName']?.toString() ?? '房主',
        hostAvatar: json['hostAvatar']?.toString() ?? '',
        listeners: (json['listeners'] as num?)?.toInt() ?? 0,
        track: TogetherTrack.fromJson(json['track']),
        isPlaying: json['isPlaying'] == true,
      );
}

/// 本机在一起听里的角色。
enum TogetherRole {
  /// 没参与。
  none,

  /// 房主：自己播什么，房间就播什么。
  host,

  /// 听众：跟着房主播。
  guest,
}

/// 连接状态，供 UI 显示「连接中 / 已断开」。
enum TogetherConnection { idle, connecting, connected, closed }
