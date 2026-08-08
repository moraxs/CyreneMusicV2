import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
// 只取进度指示器：与同目录面板保持一致的 miuix 引入方式，避免全量导入撞名。
import 'package:flutter_miuix/miuix.dart'
    show MiuixCircularProgressIndicator, MiuixProgressIndicatorColors;

import '../../../../domain/models/comment.dart';
import '../../../../domain/models/media_url.dart';
import '../../../../domain/models/music_source.dart';
import '../../../../domain/models/track.dart';
import '../../../../infrastructure/services/netease_comment_service.dart';
import '../../../../infrastructure/services/qq_comment_service.dart';

/// 移动端歌曲评论面板。
///
/// 嵌入全屏播放器歌曲信息面板「关于歌手」下方，展示网易云歌曲的热门评论与
/// 最新评论，支持按时间 / 按热度排序、展开收起、加载更多分页。逻辑对齐
/// Tauri 参考实现 `components/player/song-info/SongComments.tsx`。
///
/// 后端 `/comment/music` 首页同时返回 `hotComments` + `comments`，后续分页仅
/// 返回 `comments`；超过 5000 条评论后用 `before` 游标（上一页最后一条的
/// `time`）翻页。仅支持网易云音源（与所在面板的音源门控一致）。
class MobilePlayerSongComments extends StatefulWidget {
  const MobilePlayerSongComments({super.key, required this.track});

  final Track track;

  @override
  State<MobilePlayerSongComments> createState() =>
      _MobilePlayerSongCommentsState();
}

class _MobilePlayerSongCommentsState extends State<MobilePlayerSongComments> {
  /// 单页评论数量
  static const int _pageSize = 20;

  /// 收起时热门 / 最新评论各自最多展示的条数
  static const int _previewLimit = 3;

  SongComments? _firstPage;
  // 后续分页累计的评论（不含首页），展开后与首页 comments 拼接展示
  List<CommentItem> _latestPage = const [];
  int _offset = 0;
  int _page = 0;
  // before 分页游标：取上一页最后一条评论的 time，用于超过 5000 条评论后的翻页
  int _before = 0;

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _expanded = false;
  String? _error;
  // 0=按时间，1=按热度
  int _sortType = 0;

  // 请求竞态守卫：新请求递增后，旧请求回调比对 _reqId 即可作废
  int _reqId = 0;
  String? _lastTrackId;

  @override
  void initState() {
    super.initState();
    _lastTrackId = widget.track.key;
    _fetchFirst();
  }

  @override
  void didUpdateWidget(covariant MobilePlayerSongComments oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.track.key != _lastTrackId) {
      _lastTrackId = widget.track.key;
      _reset();
      _fetchFirst();
    }
  }

  void _reset() {
    _firstPage = null;
    _latestPage = const [];
    _offset = 0;
    _page = 0;
    _before = 0;
    _expanded = false;
    _error = null;
  }

  /// 加载第一页（热门评论 + 最新评论首页）
  Future<void> _fetchFirst() async {
    final reqId = ++_reqId;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final data = await _fetchComments(firstPage: true);
      if (reqId != _reqId) return; // 已被新请求取代
      if (data != null) {
        _firstPage = data;
        _latestPage = const [];
        _offset = _pageSize;
        _page = 1;
        _before = data.comments.isNotEmpty ? data.comments.last.time : 0;
      } else {
        _firstPage = null;
      }
    } catch (e) {
      debugPrint('[SongComments] 加载评论失败: $e');
      if (reqId == _reqId) _error = '评论加载失败';
    } finally {
      if (reqId == _reqId && mounted) setState(() => _isLoading = false);
    }
  }

  /// 加载更多最新评论
  Future<void> _loadMore() async {
    final firstPage = _firstPage;
    if (_isLoadingMore || firstPage == null || !firstPage.more) return;
    setState(() => _isLoadingMore = true);
    try {
      final data = await _fetchComments(firstPage: false);
      if (data != null) {
        _latestPage = [..._latestPage, ...data.comments];
        _offset += _pageSize;
        _page += 1;
        if (data.comments.isNotEmpty) {
          _before = data.comments.last.time;
        }
        // 同步 more 标志，控制「加载更多」是否继续显示
        _firstPage = SongComments(
          total: firstPage.total,
          more: data.more,
          moreHot: firstPage.moreHot,
          hotComments: firstPage.hotComments,
          comments: firstPage.comments,
        );
      }
    } catch (e) {
      debugPrint('[SongComments] 加载更多失败: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<SongComments?> _fetchComments({required bool firstPage}) {
    if (widget.track.source == MusicSource.qq) {
      return QqCommentService.instance.fetchSongComments(
        widget.track.id,
        pagesize: _pageSize,
        pagenum: firstPage ? 0 : _page,
        sortType: _sortType,
      );
    }
    return NeteaseCommentService.instance.fetchSongComments(
      widget.track.id,
      limit: _pageSize,
      offset: firstPage ? 0 : _offset,
      before: firstPage ? 0 : _before,
      sortType: _sortType,
    );
  }

  /// 切换排序：重置状态后由 _fetchFirst 重新拉取
  void _changeSort(int newSort) {
    if (newSort == _sortType) return;
    _sortType = newSort;
    _reset();
    _fetchFirst();
  }

  /// 点赞数格式化：>=1万显示万
  String _formatCount(int count) {
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
    return count.toString();
  }

  /// 时间戳格式化为 yyyy-MM-dd
  String _formatTime(int ts) {
    if (ts <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true).toLocal();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: MiuixCircularProgressIndicator(
            size: 24,
            strokeWidth: 3,
            colors: MiuixProgressIndicatorColors(
              foregroundColor: Colors.white70,
              disabledForegroundColor: Colors.white70,
              backgroundColor: Colors.transparent,
            ),
          ),
        ),
      );
    }

    final firstPage = _firstPage;
    if (firstPage == null) {
      if (_error != null) {
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            _error!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 13,
            ),
          ),
        );
      }
      // 未支持的音源 / 无数据：不占位
      return const SizedBox.shrink();
    }

    // 无评论：不渲染，避免留白
    if (firstPage.hotComments.isEmpty && firstPage.comments.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildComments(firstPage);
  }

  Widget _buildComments(SongComments firstPage) {
    final hasHot = firstPage.hotComments.isNotEmpty;
    final hasLatest = firstPage.comments.isNotEmpty;

    final hotToShow = _expanded
        ? firstPage.hotComments
        : firstPage.hotComments.take(_previewLimit).toList();
    final latestToShow = _expanded
        ? [...firstPage.comments, ..._latestPage]
        : firstPage.comments.take(_previewLimit).toList();

    final canExpand =
        !_expanded &&
        (firstPage.hotComments.length > _previewLimit ||
            firstPage.comments.length > _previewLimit);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行：评论 + 总数 + 排序选择器
        Row(
          children: [
            Text(
              '评论',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatCount(firstPage.total),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
            const Spacer(),
            _buildSortSelector(),
          ],
        ),
        const SizedBox(height: 12),

        // 精彩评论
        if (hasHot) ...[
          Text(
            '精彩评论',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          for (final c in hotToShow) _buildCommentRow(c),
          const SizedBox(height: 12),
        ],

        // 最新评论 / 最热评论
        if (hasLatest) ...[
          if (hasHot || _expanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _sortType == 1 ? '最热评论' : '最新评论',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          for (final c in latestToShow) _buildCommentRow(c),
        ],

        _buildActions(canExpand, firstPage),
      ],
    );
  }

  /// 排序方式选择器（按时间 / 按热度）
  Widget _buildSortSelector() {
    const options = <(int, String)>[(0, '按时间'), (1, '按热度')];
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, label) in options)
            GestureDetector(
              onTap: () => _changeSort(value),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: value == _sortType
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: value == _sortType
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 操作按钮：展开更多 / 加载更多 / 收起
  Widget _buildActions(bool canExpand, SongComments firstPage) {
    final buttons = <Widget>[];
    if (canExpand) {
      buttons.add(
        _buildActionButton(
          '展开更多',
          onTap: () => setState(() => _expanded = true),
        ),
      );
    }
    if (_expanded && firstPage.more) {
      buttons.add(
        _buildActionButton(
          '加载更多',
          loading: _isLoadingMore,
          onTap: _isLoadingMore ? null : _loadMore,
        ),
      );
    }
    if (_expanded) {
      buttons.add(
        _buildActionButton(
          '收起',
          showIcon: false,
          onTap: () => setState(() => _expanded = false),
        ),
      );
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            buttons[i],
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String label, {
    bool loading = false,
    bool showIcon = true,
    VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                ),
              )
            else if (showIcon)
              Icon(
                Icons.chevron_right,
                size: 14,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            if (loading || showIcon) const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: disabled
                    ? Colors.white.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentRow(CommentItem comment) {
    final user = comment.user;
    final avatarUrl = user?.avatarUrl ?? '';
    final nickname = (user?.nickname?.isNotEmpty ?? false)
        ? user!.nickname!
        : '未知用户';
    final ipLocation = comment.ipLocation;
    final isVip = (user?.vipType ?? 0) > 0;
    final timeStr = comment.timeStr;
    final timeText = (timeStr != null && timeStr.isNotEmpty)
        ? timeStr
        : _formatTime(comment.time);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(avatarUrl, nickname),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 昵称 + VIP
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (isVip) ...[const SizedBox(width: 6), _buildVipBadge()],
                  ],
                ),
                // 正文
                if (comment.content.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    comment.content,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
                // 楼中楼回复
                if (comment.beReplied != null &&
                    comment.beReplied!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(6),
                      border: Border(
                        left: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1),
                          width: 2,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final r in comment.beReplied!)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text:
                                        '@${(r.user?.nickname?.isNotEmpty ?? false) ? r.user!.nickname! : '未知用户'}: ',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.8,
                                      ),
                                    ),
                                  ),
                                  TextSpan(
                                    text: r.content,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              style: const TextStyle(fontSize: 12, height: 1.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                // 底部信息：时间 / IP / 点赞
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (timeText.isNotEmpty)
                      Text(
                        timeText,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 11,
                        ),
                      ),
                    if (timeText.isNotEmpty &&
                        ipLocation != null &&
                        ipLocation.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Text(
                        ipLocation,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 11,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Icon(
                      comment.liked == true
                          ? Icons.favorite
                          : Icons.favorite_border,
                      size: 12,
                      color: comment.liked == true
                          ? const Color(0xFFEF4444)
                          : Colors.white.withValues(alpha: 0.4),
                    ),
                    if (comment.likedCount > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        _formatCount(comment.likedCount),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(String url, String nickname) {
    const size = 36.0;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.08),
      ),
      alignment: Alignment.center,
      child: Text(
        nickname.isNotEmpty ? nickname[0] : '?',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 12,
        ),
      ),
    );
    if (url.isEmpty) return placeholder;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        httpHeaders: imageHeaders(url),
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: coverDecodeWidth(
          size,
          MediaQuery.devicePixelRatioOf(context),
        ),
        placeholder: (_, _) => Container(
          width: size,
          height: size,
          color: Colors.white.withValues(alpha: 0.08),
        ),
        errorWidget: (_, _, _) => placeholder,
      ),
    );
  }

  Widget _buildVipBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFBBF24), Color(0xFFF97316)],
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Text(
        'VIP',
        style: TextStyle(
          color: Colors.black,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          height: 1.2,
        ),
      ),
    );
  }
}
