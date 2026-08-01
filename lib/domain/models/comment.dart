/// 评论中的楼中楼回复条目（对应 Next.js BeReplied）。
///
/// [user] 字段复用 [CommentUser]，回复场景下 [CommentUser.avatarDetailUrl] 与
/// [CommentUser.vipRights] 通常为 null。
class BeReplied {
  const BeReplied({
    required this.beRepliedCommentId,
    required this.content,
    this.status,
    this.user,
  });

  final int beRepliedCommentId;
  final String content;
  final int? status;
  final CommentUser? user;

  factory BeReplied.fromJson(Map<String, Object?> json) => BeReplied(
    beRepliedCommentId: (json['beRepliedCommentId'] as num?)?.toInt() ?? 0,
    content: json['content']?.toString() ?? '',
    status: (json['status'] as num?)?.toInt(),
    user: _parseUser(json['user']),
  );

  Map<String, Object?> toJson() => {
    'beRepliedCommentId': beRepliedCommentId,
    'content': content,
    'status': status,
    'user': user?.toJson(),
  };

  static CommentUser? _parseUser(Object? data) => data is Map
      ? CommentUser.fromJson(Map<String, Object?>.from(data))
      : null;
}

/// 评论用户（对应 CommentItem.user / BeReplied.user 的内联结构）。
class CommentUser {
  const CommentUser({
    this.userId,
    this.nickname,
    this.avatarUrl,
    this.vipType,
    this.avatarDetailUrl,
    this.vipRights,
  });

  final int? userId;
  final String? nickname;
  final String? avatarUrl;
  final int? vipType;

  /// 由 `avatarDetail.url` 解析得到。
  final String? avatarDetailUrl;

  /// 原始 `vipRights`，结构与网易云一致（任意 JSON 值）。
  final Object? vipRights;

  factory CommentUser.fromJson(Map<String, Object?> json) => CommentUser(
    userId: (json['userId'] as num?)?.toInt(),
    nickname: json['nickname']?.toString(),
    avatarUrl: json['avatarUrl']?.toString(),
    vipType: (json['vipType'] as num?)?.toInt(),
    avatarDetailUrl: _parseAvatarDetailUrl(json['avatarDetail']),
    vipRights: json['vipRights'],
  );

  Map<String, Object?> toJson() => {
    'userId': userId,
    'nickname': nickname,
    'avatarUrl': avatarUrl,
    'vipType': vipType,
    'avatarDetail': avatarDetailUrl == null ? null : {'url': avatarDetailUrl},
    'vipRights': vipRights,
  };

  static String? _parseAvatarDetailUrl(Object? data) =>
      data is Map ? data['url']?.toString() : null;
}

/// 单条评论（对应 Next.js CommentItem）。
class CommentItem {
  const CommentItem({
    required this.commentId,
    required this.content,
    required this.time,
    required this.likedCount,
    this.richContent,
    this.timeStr,
    this.liked,
    this.status,
    this.parentCommentId,
    this.ipLocation,
    this.user,
    this.beReplied,
  });

  final int commentId;
  final String content;
  final String? richContent;
  final int time;
  final String? timeStr;
  final int likedCount;
  final bool? liked;
  final int? status;
  final int? parentCommentId;

  /// 由 `ipLocation.location` 解析得到。
  final String? ipLocation;
  final CommentUser? user;
  final List<BeReplied>? beReplied;

  factory CommentItem.fromJson(Map<String, Object?> json) => CommentItem(
    commentId: (json['commentId'] as num?)?.toInt() ?? 0,
    content: json['content']?.toString() ?? '',
    richContent: json['richContent']?.toString(),
    time: (json['time'] as num?)?.toInt() ?? 0,
    timeStr: json['timeStr']?.toString(),
    likedCount: (json['likedCount'] as num?)?.toInt() ?? 0,
    liked: json['liked'] is bool ? json['liked'] as bool : null,
    status: (json['status'] as num?)?.toInt(),
    parentCommentId: (json['parentCommentId'] as num?)?.toInt(),
    ipLocation: _parseIpLocation(json['ipLocation']),
    user: _parseUser(json['user']),
    beReplied: _parseBeReplied(json['beReplied']),
  );

  Map<String, Object?> toJson() => {
    'commentId': commentId,
    'content': content,
    'richContent': richContent,
    'time': time,
    'timeStr': timeStr,
    'likedCount': likedCount,
    'liked': liked,
    'status': status,
    'parentCommentId': parentCommentId,
    'ipLocation': ipLocation == null ? null : {'location': ipLocation},
    'user': user?.toJson(),
    'beReplied': beReplied?.map((e) => e.toJson()).toList(),
  };

  static String? _parseIpLocation(Object? data) =>
      data is Map ? data['location']?.toString() : null;

  static CommentUser? _parseUser(Object? data) => data is Map
      ? CommentUser.fromJson(Map<String, Object?>.from(data))
      : null;

  static List<BeReplied>? _parseBeReplied(Object? data) => data is List
      ? data
            .whereType<Map>()
            .map((e) => BeReplied.fromJson(Map<String, Object?>.from(e)))
            .toList()
      : null;
}

/// 歌曲评论响应（对应 Next.js SongComments）。
///
/// 后端 `/comment/music` 与 `/qq/comment/music` 共用此结构，前端评论组件对两种音源
/// 可共用同一套渲染逻辑。
class SongComments {
  const SongComments({
    required this.total,
    required this.more,
    required this.moreHot,
    required this.hotComments,
    required this.comments,
  });

  final int total;
  final bool more;
  final bool moreHot;
  final List<CommentItem> hotComments;
  final List<CommentItem> comments;

  factory SongComments.fromJson(Map<String, Object?> json) => SongComments(
    total: (json['total'] as num?)?.toInt() ?? 0,
    more: json['more'] == true,
    moreHot: json['moreHot'] == true,
    hotComments: _parseList(json['hotComments']),
    comments: _parseList(json['comments']),
  );

  Map<String, Object?> toJson() => {
    'total': total,
    'more': more,
    'moreHot': moreHot,
    'hotComments': hotComments.map((e) => e.toJson()).toList(),
    'comments': comments.map((e) => e.toJson()).toList(),
  };

  static List<CommentItem> _parseList(Object? data) => data is List
      ? data
            .whereType<Map>()
            .map((e) => CommentItem.fromJson(Map<String, Object?>.from(e)))
            .toList()
      : const [];
}
