/// 公告信息（对应 Next.js demo/lib/services/announcementService.ts 的 Announcement）。
///
/// 由后端 `GET /config/public` 的 `data.announcement` 下发，字段与 config.json 的
/// `announcement` 段一一对应。
class Announcement {
  const Announcement({
    required this.enabled,
    required this.id,
    required this.title,
    required this.content,
    this.popup = true,
  });

  final bool enabled;

  /// 公告编号，形如 `announcement_2026_007`。
  ///
  /// 用户勾了「不再提示」后记的就是它，之后只有**编号更大**的公告才会重新自动弹窗，
  /// 比较规则见 [compareAnnouncementIds]。
  final String id;

  final String title;
  final String content;

  /// 是否参与启动自动弹窗。false 表示只保留设置页里的手动入口。
  final bool popup;

  /// 是否具备自动弹窗的资格。
  ///
  /// 空 id 不弹：没有编号就没法记「不再提示」，弹了也压不住，只会每次启动都糊一脸。
  bool get canPopup =>
      enabled && popup && id.isNotEmpty && content.isNotEmpty;

  factory Announcement.fromJson(Map<String, Object?> json) => Announcement(
    enabled: json['enabled'] == true,
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    content: json['content']?.toString() ?? '',
    // 缺省 true：老后端不下发该字段时，维持「有公告就弹」的预期行为。
    popup: json['popup'] != false,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'id': id,
    'title': title,
    'content': content,
    'popup': popup,
  };
}

/// 比较两个公告编号的新旧：[a] 比 [b] 新返回正数，旧返回负数，相同返回 0。
///
/// 取 id 里所有数字段按顺序组成元组逐位比较——`announcement_2026_007` → [2026, 7]，
/// 于是 `announcement_2026_008` > `announcement_2026_007`，跨年的
/// `announcement_2027_001` 也大于 `announcement_2026_099`，编号不必一直往上累加。
/// 前缀不参与比较，改前缀（但数字不变）不会被当成新公告。
///
/// 两边都不含数字时退化为字符串比较，保证任何输入都能给出确定结果（否则
/// 一个手写的畸形 id 就会让「不再提示」彻底失效或彻底卡死）。
int compareAnnouncementIds(String a, String b) {
  if (a == b) return 0;
  final left = _numericSegments(a);
  final right = _numericSegments(b);
  if (left.isEmpty && right.isEmpty) return a.compareTo(b);
  // 一侧有编号一侧没有：有编号的算新的（空 id 的场景就是「从没勾过不再提示」）。
  if (left.isEmpty) return -1;
  if (right.isEmpty) return 1;

  for (var i = 0; i < left.length || i < right.length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l > r ? 1 : -1;
  }
  return 0;
}

/// 抽出 id 里连续的数字段。超长数字段按 int 解析失败时丢弃该段，不让异常冒出去。
List<int> _numericSegments(String id) => RegExp(r'\d+')
    .allMatches(id)
    .map((m) => int.tryParse(m.group(0)!))
    .whereType<int>()
    .toList(growable: false);
