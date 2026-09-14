import 'package:flutter/material.dart';

import '../../application/playback/playback_controller.dart';
import '../../domain/models/track.dart';
import '../playlist/playlist_detail_page.dart';

/// 每日推荐详情页：与歌单详情页共享同一套沉浸式布局（固定全宽封面 +
/// 视差滚动 + 主题渐变背景 + 悬浮顶栏 + 排序/搜索 + 玻璃曲目卡）。
/// 封面随机取自有封面的推荐曲目，页面生命周期内保持稳定。
class DailyRecommendPage extends StatelessWidget {
  const DailyRecommendPage({
    super.key,
    required this.tracks,
    required this.playback,
    this.token,
    this.desktopLayout = false,
  });

  final List<Track> tracks;
  final PlaybackController playback;

  /// 登录令牌：曲目操作菜单（收藏到歌单等）需要；未登录可传 null。
  final String? token;

  /// 桌面端使用居中限宽与表格式曲目列表；默认关闭保留移动端沉浸布局。
  final bool desktopLayout;

  @override
  Widget build(BuildContext context) {
    return PlaylistDetailPage.fromTracks(
      initialTracks: tracks,
      title: '每日推荐',
      coverUrl: '',
      playback: playback,
      token: token,
      creator: '每日更新',
      description: '每日凌晨更新，遇见你的心头好',
      tags: const ['每日推荐'],
      desktopLayout: desktopLayout,
    );
  }
}
