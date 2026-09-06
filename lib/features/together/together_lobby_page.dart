import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/together/together_controller.dart';
import '../../domain/models/media_url.dart';
import '../../domain/together/together_models.dart';
import '../../infrastructure/together/together_lobby_service.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';

/// 一起听大厅：谁在放什么、多少人在听，点一下就能进去一起听。
///
/// 只列公开房间；私有房不在这里出现，得让房主把 6 位房间号发给你（右上角
/// 「输入房间号」）。
class TogetherLobbyPage extends StatefulWidget {
  const TogetherLobbyPage({super.key});

  @override
  State<TogetherLobbyPage> createState() => _TogetherLobbyPageState();
}

class _TogetherLobbyPageState extends State<TogetherLobbyPage> {
  final _controller = TogetherController.instance;

  List<TogetherRoomSummary> _rooms = const [];
  bool _loading = true;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rooms = await TogetherLobbyService.instance.fetchRooms();
    if (!mounted) return;
    setState(() {
      _rooms = rooms;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) => CyrenePage(
    title: '一起听大厅',
    actions: [
      MiuixIconButton(
        onPressed: _loading ? null : _load,
        child: MiuixIcon(
          vector: MiuixIcons.extended.byName('refresh')!,
          size: 20,
        ),
      ),
    ],
    bodyBuilder: (context, topPadding) => ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => ListView(
        physics: const BouncingScrollPhysics(),
        padding: topPadding + const EdgeInsets.fromLTRB(12, 4, 12, 40),
        children: [
          if (_controller.isActive) ...[
            _CurrentRoomCard(controller: _controller),
            const SizedBox(height: 12),
          ],
          CyreneMenuGroup(
            children: [
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('add')!,
                iconBackground: const Color(0xFF3482FF),
                title: '输入房间号加入',
                subtitle: '私有房间也能靠房间号进去',
                onTap: _joining ? null : _promptJoinByCode,
              ),
              if (!_controller.isActive)
                CyreneMenuRow(
                  vector: MiuixIcons.extended.byName('play')!,
                  iconBackground: const Color(0xFF3CC756),
                  title: '开一个房间',
                  subtitle: '生成房间号，把它发给朋友',
                  onTap: _joining ? null : _startHosting,
                ),
            ],
          ),
          const SizedBox(height: 12),
          const MiuixSmallTitle(
            '正在一起听',
            insideMargin: EdgeInsets.fromLTRB(16, 4, 16, 8),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: MiuixCircularProgressIndicator(size: 22, strokeWidth: 2),
              ),
            )
          else if (_rooms.isEmpty)
            CyreneEmptyState(
              vector: MiuixIcons.extended.byName('community')!,
              title: '还没有人开房',
              description: '开一个公开房间，让别人听到你在听什么',
            )
          else
            CyreneMenuGroup(
              children: [
                for (final room in _rooms)
                  _RoomRow(
                    room: room,
                    onTap: _joining ? null : () => _join(room.code),
                  ),
              ],
            ),
        ],
      ),
    ),
  );

  Future<void> _promptJoinByCode() async {
    final code = await showCyreneDialog<String>(
      context: context,
      title: '加入房间',
      summary: '输入 6 位房间号',
      builder: (dialogContext, dismiss) => _CodeInput(onSubmit: dismiss),
    );
    if (code == null || code.trim().isEmpty) return;
    await _join(code.trim().toUpperCase());
  }

  Future<void> _join(String code) async {
    setState(() => _joining = true);
    final exists = await TogetherLobbyService.instance.roomExists(code);
    if (!exists) {
      if (mounted) setState(() => _joining = false);
      CyreneToast.show('房间不存在或已解散');
      return;
    }
    final ok = await _controller.join(code);
    if (!mounted) return;
    setState(() => _joining = false);
    if (!ok) {
      CyreneToast.show(_controller.errorMessage ?? '加入失败，请稍后再试');
      return;
    }
    CyreneToast.show('已加入房间 $code，开始跟随房主播放');
    await _load();
  }

  Future<void> _startHosting() async {
    setState(() => _joining = true);
    final ok = await _controller.host();
    if (!mounted) return;
    setState(() => _joining = false);
    CyreneToast.show(
      ok
          ? '房间已创建：${_controller.roomCode ?? ''}'
          : (_controller.errorMessage ?? '创建失败，请稍后再试'),
    );
    await _load();
  }
}

/// 顶部「我正在的房间」卡片。
class _CurrentRoomCard extends StatelessWidget {
  const _CurrentRoomCard({required this.controller});

  final TogetherController controller;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return MiuixCard(
      cornerRadius: 20,
      insideMargin: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MiuixText(
                      controller.isHost ? '我的房间' : '正在收听',
                      fontSize: 12,
                      color: colors.onSurfaceVariantSummary,
                    ),
                    const SizedBox(height: 4),
                    MiuixText(
                      controller.roomCode ?? '------',
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: colors.onBackground,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MiuixText(
                    '${controller.listeners} 人在听',
                    fontSize: 13,
                    color: colors.onSurfaceVariantSummary,
                  ),
                  const SizedBox(height: 4),
                  MiuixText(
                    controller.roomPrivate ? '私有' : '公开',
                    fontSize: 12,
                    color: colors.primary,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          MiuixButton(
            onPressed: () {
              final wasHost = controller.isHost;
              controller.leave();
              CyreneToast.show(wasHost ? '已结束一起听' : '已退出房间');
            },
            colors: MiuixButtonColors(
              color: colors.error.withValues(alpha: 0.12),
              disabledColor: colors.disabledPrimaryButton,
              contentColor: colors.error,
              disabledContentColor: colors.disabledOnPrimaryButton,
            ),
            child: MiuixText(
              controller.isHost ? '结束一起听' : '退出房间',
              style: theme.textStyles.button,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomRow extends StatelessWidget {
  const _RoomRow({required this.room, required this.onTap});

  final TogetherRoomSummary room;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final track = room.track;
    return CyreneMenuRow(
      leading: _RoomCover(picUrl: track?.picUrl ?? ''),
      title: track == null ? '还没开始播放' : track.name,
      subtitle: track == null
          ? '${room.hostName} 的房间'
          : '${track.artists} · ${room.hostName} 的房间',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.headphones_rounded,
            size: 14,
            color: colors.onSurfaceVariantActions,
          ),
          const SizedBox(width: 3),
          Text(
            '${room.listeners}',
            style: TextStyle(
              fontSize: 13,
              color: colors.onSurfaceVariantActions,
            ),
          ),
          const SizedBox(width: 8),
          MiuixIcon(
            vector: MiuixIcons.extended.byName('chevronForward')!,
            size: 15,
            tint: colors.onSurfaceVariantActions,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _RoomCover extends StatelessWidget {
  const _RoomCover({required this.picUrl});

  final String picUrl;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 40,
        height: 40,
        child: picUrl.isEmpty
            ? ColoredBox(
                color: colors.secondaryContainer,
                child: Icon(
                  Icons.music_note_rounded,
                  size: 20,
                  color: colors.onSurfaceVariantActions,
                ),
              )
            : CachedNetworkImage(
                imageUrl: picUrl,
                httpHeaders: imageHeaders(picUrl),
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => ColoredBox(
                  color: colors.secondaryContainer,
                  child: Icon(
                    Icons.music_note_rounded,
                    size: 20,
                    color: colors.onSurfaceVariantActions,
                  ),
                ),
              ),
      ),
    );
  }
}

class _CodeInput extends StatefulWidget {
  const _CodeInput({required this.onSubmit});

  final void Function([String? value]) onSubmit;

  @override
  State<_CodeInput> createState() => _CodeInputState();
}

class _CodeInputState extends State<_CodeInput> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        MiuixTextField(
          controller: _input,
          label: '如 A7K2M9',
          useLabelAsPlaceholder: true,
          singleLine: true,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          onSubmitted: (value) => widget.onSubmit(value),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            MiuixTextButton('取消', onPressed: () => widget.onSubmit()),
            const SizedBox(width: 10),
            MiuixButton(
              onPressed: () => widget.onSubmit(_input.text),
              colors: MiuixButtonDefaults.buttonColorsPrimary(context),
              child: MiuixText('加入', style: theme.textStyles.button),
            ),
          ],
        ),
      ],
    );
  }
}
