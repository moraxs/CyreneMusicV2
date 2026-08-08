import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/auth/account_session_controller.dart';
import '../../application/playback/playback_controller.dart';
import '../../application/playlists/playlist_library_controller.dart';
import '../../domain/models/media_url.dart';
import '../../domain/models/playlist.dart';
import '../../infrastructure/services/playlist_service.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
import '../../presentation/cyrene/cyrene_user_hero_card.dart';
import '../history/history_page.dart';
import '../local/local_music_page.dart';
import '../playlist/playlist_detail_page.dart';
import '../settings/login_page.dart';
import 'listening_footprint_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.accountSessionController,
    required this.playback,
    required this.playlists,
    this.desktopLayout = false,
    this.onOpenSecondary,
    this.body,
  });

  final AccountSessionController accountSessionController;
  final PlaybackController playback;
  final PlaylistLibraryController playlists;
  final bool desktopLayout;

  /// 桌面端由外壳提供，用内容区二级页替代整窗路由跳转。
  final ValueChanged<Widget>? onOpenSecondary;

  /// 当前桌面端二级页；移动端保持为空并继续使用原有路由。
  final Widget? body;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _loadedToken;
  final _syncingIds = <int>{};

  @override
  void initState() {
    super.initState();
    widget.accountSessionController.addListener(_onAccountChanged);
    _reloadPlaylists();
  }

  @override
  void dispose() {
    widget.accountSessionController.removeListener(_onAccountChanged);
    super.dispose();
  }

  void _onAccountChanged() {
    final token = widget.accountSessionController.token;
    if (token == _loadedToken) return;
    _reloadPlaylists();
  }

  void _reloadPlaylists() {
    _loadedToken = widget.accountSessionController.token;
    widget.playlists.load(_loadedToken);
  }

  @override
  Widget build(BuildContext context) {
    final body = widget.body;
    if (body != null) return body;

    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.accountSessionController,
        widget.playlists,
      ]),
      builder: (context, _) {
        final state = widget.accountSessionController.state;
        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 180),
          children: [
            _AccountCard(state: state, onLogin: () => _openLogin(context)),
            const SizedBox(height: 24),
            const CyreneSectionTitle(
              title: '音乐资料库',
              description: '管理收藏、歌单与设备音乐',
            ),
            const SizedBox(height: 12),
            CyreneMenuGroup(
              children: [
                CyreneMenuRow(
                  icon: Icons.download_rounded,
                  title: '本地与下载',
                  subtitle: '管理设备上的音乐',
                  onTap: () => _open(
                    context,
                    LocalMusicPage(playback: widget.playback),
                  ),
                ),
                CyreneMenuRow(
                  icon: Icons.history_rounded,
                  title: '播放历史',
                  onTap: () =>
                      _open(context, HistoryPage(playback: widget.playback)),
                ),
                CyreneMenuRow(
                  icon: Icons.bar_chart_rounded,
                  title: '听歌统计',
                  onTap: () => _open(
                    context,
                  ListeningFootprintPage(
                    account: widget.accountSessionController,
                    playback: widget.playback,
                    desktopLayout: widget.desktopLayout,
                  ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _MyPlaylistsSection(
              isLoggedIn: state.isLoggedIn,
              state: widget.playlists.state,
              syncingIds: _syncingIds,
              onOpen: _openPlaylist,
              onDelete: _deletePlaylist,
              onCreate: () => _createPlaylist(context),
              onSync: _syncPlaylist,
            ),
          ],
        );
      },
    );
  }

  void _openPlaylist(Playlist playlist) {
    final token = widget.accountSessionController.token;
    if (token == null) return;
    _open(
      context,
      PlaylistDetailPage.personal(
        playlistId: playlist.id,
        title: playlist.name,
        coverUrl: playlist.coverUrl ?? '',
        playback: widget.playback,
        token: token,
        trackCount: playlist.trackCount,
        desktopLayout: widget.desktopLayout,
      ),
    );
  }

  Future<void> _deletePlaylist(Playlist playlist) async {
    final token = widget.accountSessionController.token;
    if (token == null) return;
    final confirmed = await showCyreneDialog<bool>(
      context: context,
      title: '删除歌单',
      summary: '确定要删除歌单「${playlist.name}」吗？此操作无法撤销。',
      builder: (dialogContext, dismiss) {
        final theme = MiuixTheme.of(dialogContext);
        final colors = theme.colors;
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            MiuixTextButton('取消', onPressed: () => dismiss(false)),
            const SizedBox(width: 12),
            MiuixButton(
              onPressed: () => dismiss(true),
              colors: MiuixButtonColors(
                color: colors.error,
                disabledColor: colors.disabledPrimaryButton,
                contentColor: colors.onError,
                disabledContentColor: colors.disabledOnPrimaryButton,
              ),
              child: MiuixText('确认删除', style: theme.textStyles.button),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final ok = await widget.playlists.delete(token, playlist);
    if (!mounted) return;
    CyreneToast.show(ok ? '歌单已删除' : '删除歌单失败');
  }

  /// 新建歌单（对应原版「我的」页的新建入口）。
  Future<void> _createPlaylist(BuildContext context) async {
    final token = widget.accountSessionController.token;
    if (token == null) return;
    final controller = TextEditingController();
    final name = await showCyreneDialog<String>(
      context: context,
      title: '新建歌单',
      builder: (dialogContext, dismiss) {
        final theme = MiuixTheme.of(dialogContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MiuixTextField(
              controller: controller,
              label: '请输入歌单名称',
              singleLine: true,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (value) => dismiss(value.trim()),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                MiuixTextButton('取消', onPressed: () => dismiss()),
                const SizedBox(width: 12),
                MiuixButton(
                  onPressed: () => dismiss(controller.text.trim()),
                  colors: MiuixButtonDefaults.buttonColorsPrimary(
                    dialogContext,
                  ),
                  child: MiuixText('创建', style: theme.textStyles.button),
                ),
              ],
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    final playlist = await widget.playlists.create(token, name);
    if (!mounted) return;
    CyreneToast.show(playlist != null ? '歌单「$name」创建成功' : '创建歌单失败');
  }

  /// 增量同步已绑定来源的歌单（对应原版「我的」页的同步入口）。
  Future<void> _syncPlaylist(Playlist playlist) async {
    final token = widget.accountSessionController.token;
    if (token == null || _syncingIds.contains(playlist.id)) return;
    setState(() => _syncingIds.add(playlist.id));
    try {
      final result = await PlaylistService.instance.syncPlaylist(
        token,
        playlist.id,
      );
      if (!mounted) return;
      if (result == null) {
        CyreneToast.show('同步失败，请稍后重试');
      } else {
        CyreneToast.show(
          result.insertedCount > 0
              ? '「${playlist.name}」已同步，新增 ${result.insertedCount} 首'
              : '「${playlist.name}」已是最新',
        );
        widget.playlists.load(token);
      }
    } finally {
      if (mounted) setState(() => _syncingIds.remove(playlist.id));
    }
  }

  void _open(BuildContext context, Widget page) {
    final onOpenSecondary = widget.onOpenSecondary;
    if (onOpenSecondary != null) {
      onOpenSecondary(page);
      return;
    }
    Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => page));
  }

  void _openLogin(BuildContext context) {
    _open(
      context,
      LoginPage(account: widget.accountSessionController),
    );
  }
}

/// 我的歌单板块（对应 PlaylistSection 的移动端列表样式）。
class _MyPlaylistsSection extends StatelessWidget {
  const _MyPlaylistsSection({
    required this.isLoggedIn,
    required this.state,
    required this.syncingIds,
    required this.onOpen,
    required this.onDelete,
    required this.onCreate,
    required this.onSync,
  });

  final bool isLoggedIn;
  final PlaylistLibraryState state;
  final Set<int> syncingIds;
  final ValueChanged<Playlist> onOpen;
  final ValueChanged<Playlist> onDelete;
  final VoidCallback onCreate;
  final ValueChanged<Playlist> onSync;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CyreneSectionTitle(
          title: '我的歌单',
          description: '你收藏与创建的歌单',
          trailing: isLoggedIn
              ? MiuixIconButton(
                  key: const Key('create-playlist-button'),
                  onPressed: onCreate,
                  child: MiuixIcon(
                    vector: MiuixIcons.extended.byName('add')!,
                    size: 20,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 12),
        if (!isLoggedIn)
          const _EmptyCard(
            icon: Icons.queue_music_rounded,
            title: '登录后查看歌单',
            description: '登录 Cyrene Music 账号即可同步你的歌单。',
          )
        else if (state.isLoading && state.playlists.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: MiuixCircularProgressIndicator()),
          )
        else if (state.playlists.isEmpty)
          const _EmptyCard(
            icon: Icons.music_note_rounded,
            title: '暂无收藏的歌单',
            description: '记录你的第一个歌单，开始音乐之旅。',
          )
        else
          CyreneMenuGroup(
            children: state.playlists
                .map(
                  (playlist) => _PlaylistRow(
                    playlist: playlist,
                    isSyncing: syncingIds.contains(playlist.id),
                    onOpen: () => onOpen(playlist),
                    onDelete: () => onDelete(playlist),
                    onSync: playlist.source?.isNotEmpty == true
                        ? () => onSync(playlist)
                        : null,
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    required this.playlist,
    required this.isSyncing,
    required this.onOpen,
    required this.onDelete,
    this.onSync,
  });

  final Playlist playlist;
  final bool isSyncing;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  /// 仅已绑定外部来源（如同步收藏的网易云歌单）的歌单可增量同步。
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final cover = playlist.coverUrl ?? '';
    final fallback = ColoredBox(
      color: colors.secondaryContainer,
      child: Icon(
        Icons.queue_music_rounded,
        size: 22,
        color: colors.onSurfaceVariantSummary,
      ),
    );
    // 透明背景的可点击卡片：保持组内行按压反馈，同时不遮盖 CyreneMenuGroup 底色。
    return MiuixCard(
      colors: MiuixCardColors(
        color: Colors.transparent,
        contentColor: colors.onSurfaceContainer,
      ),
      insideMargin: const EdgeInsets.all(12),
      onPressed: onOpen,
      feedbackType: MiuixPressFeedbackType.sink,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox.square(
              dimension: 52,
              child: cover.isEmpty
                  ? fallback
                  : CachedNetworkImage(
                      imageUrl: cover,
                      httpHeaders: imageHeaders(cover),
                      fit: BoxFit.cover,
                      // 52px 显示,按显示尺寸降采样解码(见 coverDecodeWidth)。
                      memCacheWidth: coverDecodeWidth(
                        52,
                        MediaQuery.devicePixelRatioOf(context),
                      ),
                      errorWidget: (_, _, _) => fallback,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.body2.copyWith(
                    color: colors.onSurfaceContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${playlist.trackCount} 首歌曲',
                  style: theme.textStyles.body2.copyWith(
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ),
          ),
          if (onSync != null)
            MiuixIconButton(
              enabled: !isSyncing,
              onPressed: onSync,
              child: isSyncing
                  ? const MiuixCircularProgressIndicator(
                      size: 16,
                      strokeWidth: 2,
                    )
                  : MiuixIcon(
                      icon: Icons.sync_rounded,
                      size: 18,
                      tint: colors.onSurfaceContainer,
                    ),
            ),
          MiuixIconButton(
            onPressed: onDelete,
            child: MiuixIcon(
              vector: MiuixIcons.extended.byName('delete')!,
              size: 18,
              tint: colors.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return MiuixCard(
      insideMargin: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Column(
            children: [
              CyreneIconBox(icon: icon, size: 44),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textStyles.body2.copyWith(
                  color: colors.onSurfaceContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                textAlign: TextAlign.center,
                style: theme.textStyles.body2.copyWith(
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 用户卡片（对应原版「我的」页沉浸式头部的卡片化改写）：
/// 已登录时用模糊头像铺满卡片背景 + 渐变遮罩 + 玻璃高光描边，
/// 前景为大头像 / 用户名 / 邮箱 / Sponsor 徽章；未登录为 HyperOS
/// 风格的登录引导行，整卡可点进登录页。
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.state, required this.onLogin});

  final AccountSessionState state;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    if (state.status == AccountSessionStatus.restoring) {
      return MiuixCard(
        insideMargin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            children: [
              const MiuixCircularProgressIndicator(size: 18, strokeWidth: 2),
              const SizedBox(width: 12),
              Text(
                '正在恢复账号信息…',
                style: theme.textStyles.body1.copyWith(
                  color: colors.onSurfaceContainer,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final user = state.user;
    if (user == null) {
      return MiuixCard(
        cornerRadius: 20,
        onPressed: onLogin,
        feedbackType: MiuixPressFeedbackType.sink,
        insideMargin: const EdgeInsets.all(16),
        child: Row(
          key: const Key('profile-login-button'),
          children: [
            CyreneIconBox(
              icon: Icons.person_rounded,
              size: 48,
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MiuixText(
                    '登录 Cyrene Music',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: colors.onSurfaceContainer,
                  ),
                  const SizedBox(height: 3),
                  MiuixText(
                    '同步收藏、歌单与播放记录',
                    fontSize: 13,
                    color: colors.onSurfaceVariantSummary,
                  ),
                ],
              ),
            ),
            MiuixIcon(
              vector: MiuixIcons.extended.byName('chevronForward')!,
              size: 16,
              tint: colors.onSurfaceVariantActions,
            ),
          ],
        ),
      );
    }
    return CyreneUserHeroCard(user: user);
  }
}
