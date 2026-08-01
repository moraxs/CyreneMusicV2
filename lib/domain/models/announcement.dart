/// 公告信息（对应 Next.js demo/lib/services/announcementService.ts 的 Announcement）。
class Announcement {
  const Announcement({
    required this.enabled,
    required this.id,
    required this.title,
    required this.content,
  });

  final bool enabled;
  final String id;
  final String title;
  final String content;

  factory Announcement.fromJson(Map<String, Object?> json) => Announcement(
    enabled: json['enabled'] == true,
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    content: json['content']?.toString() ?? '',
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'id': id,
    'title': title,
    'content': content,
  };
}
