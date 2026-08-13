import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/audio_sources/audio_source_preferences_controller.dart';
import '../../application/auth/account_session_controller.dart';
import '../../domain/models/audio_quality.dart';
import '../../domain/models/audio_source_config.dart';
import '../../domain/models/cyrene_config.dart';
import '../../infrastructure/services/cyrene_config_service.dart';
import '../../infrastructure/services/listening_card_service.dart';
import '../../infrastructure/services/sponsor_service.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';

enum _SourceSetupAction { omniManual, omniFile, lxMusic }

class AudioSourceSettingsPage extends StatelessWidget {
  const AudioSourceSettingsPage({
    super.key,
    required this.controller,
    required this.account,
    required this.token,
    this.desktopLayout = false,
  });

  final AudioSourcePreferencesController controller;

  /// 账号会话，用于购买 Cyrene Premium 成功后回写持卡状态到本机 User，
  /// 使个人中心/我的页无需退出重登即反映 Premium。
  final AccountSessionController account;

  /// 登录态 token，用于 Cyrene Premium 购买/状态/下发接口鉴权；为空则隐藏该区块。
  final String? token;
  final bool desktopLayout;

  @override
  Widget build(BuildContext context) => CyrenePage(
    title: '音源配置',
    bodyBuilder: (context, topPadding) => AudioSourceSettingsBody(
      controller: controller,
      account: account,
      topPadding: topPadding,
      token: token,
      desktopLayout: desktopLayout,
    ),
  );
}

/// 音源配置正文，不含页面骨架。
///
/// 设置里的 [AudioSourceSettingsPage] 与首启引导的音源步骤共用——添加/导入
/// /排序/删除/音质的全部逻辑都在这里，引导页不复制一份简化版，免得两处行为
/// 分叉（例如引导里加的源没走同一套校验）。
class AudioSourceSettingsBody extends StatelessWidget {
  const AudioSourceSettingsBody({
    super.key,
    required this.controller,
    required this.account,
    required this.topPadding,
    required this.token,
    this.desktopLayout = false,
  });

  final AudioSourcePreferencesController controller;
  final AccountSessionController account;
  final EdgeInsets topPadding;
  final String? token;
  final bool desktopLayout;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => _AudioSourceSettingsBody(
      controller: controller,
      account: account,
      state: controller.state,
      topPadding: topPadding,
      token: token,
      desktopLayout: desktopLayout,
    ),
  );
}

class _AudioSourceSettingsBody extends StatelessWidget {
  const _AudioSourceSettingsBody({
    required this.controller,
    required this.account,
    required this.state,
    required this.topPadding,
    required this.token,
    required this.desktopLayout,
  });

  final AudioSourcePreferencesController controller;
  final AccountSessionController account;
  final AudioSourcePreferencesState state;
  final EdgeInsets topPadding;
  final String? token;
  final bool desktopLayout;

  @override
  Widget build(BuildContext context) {
    if (state.status == AudioSourcePreferencesStatus.initial ||
        state.status == AudioSourcePreferencesStatus.loading) {
      return const Center(child: MiuixCircularProgressIndicator());
    }

    final theme = MiuixTheme.of(context);
    final content = ListView(
      physics: const BouncingScrollPhysics(),
      // 桌面端内容区居中后增加留白；移动端继续沿用 HyperOS 的 12px 页边距。
      padding: topPadding +
          EdgeInsets.fromLTRB(
            desktopLayout ? 24 : 12,
            4,
            desktopLayout ? 24 : 12,
            40,
          ),
      children: [
        // Cyrene Premium：付款后后端自动下发 OmniParse 音源配置。仅登录用户显示。
        if (token != null && token!.isNotEmpty) ...[
          if (desktopLayout)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 260,
                  child: _ListeningCardCard(
                    controller: controller,
                    account: account,
                    sources: state.sources,
                    token: token!,
                  ),
                ),
                const SizedBox(width: 24),
                const Expanded(child: _PremiumIntroduction()),
              ],
            )
          else
            _ListeningCardCard(
              controller: controller,
              account: account,
              sources: state.sources,
              token: token!,
            ),
          const SizedBox(height: 28),
        ],
        const MiuixSmallTitle(
          '解析服务',
          insideMargin: EdgeInsets.fromLTRB(16, 8, 16, 4),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            '按列表顺序解析播放地址；禁用的音源不会参与搜索与播放。',
            style: theme.textStyles.footnote1.copyWith(
              color: theme.colors.onSurfaceVariantSummary,
            ),
          ),
        ),
        if (state.errorMessage != null) ...[
          _SourceError(
            message: state.errorMessage!,
            onDismiss: controller.clearError,
          ),
          const SizedBox(height: 12),
        ],
        if (state.sources.isEmpty)
          _EmptySources(onAdd: () => _chooseSourceType(context))
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: state.sources.length,
            onReorderItem: state.isBusy
                ? (_, _) {}
                : (oldIndex, newIndex) {
                    controller.reorderSources(
                      oldIndex,
                      oldIndex < newIndex ? newIndex + 1 : newIndex,
                    );
                  },
            itemBuilder: (context, index) => Padding(
              key: ValueKey(state.sources[index].id),
              padding: const EdgeInsets.only(bottom: 10),
              child: _SourceCard(
                source: state.sources[index],
                index: index,
                isBusy: state.isBusy,
                onEnabledChanged: (value) =>
                    controller.setSourceEnabled(state.sources[index].id, value),
                onEdit: (state.sources[index].type == AudioSourceType.omniParse &&
                        state.sources[index].id != _officialOmniParseId)
                    ? () => _editOmniParse(context, state.sources[index])
                    : null,
                onRemove: () => _confirmRemove(context, state.sources[index]),
              ),
            ),
          ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: MiuixButton(
            key: const Key('add-audio-source-button'),
            enabled: !state.isBusy,
            colors: MiuixButtonDefaults.buttonColorsPrimary(context),
            onPressed: () => _chooseSourceType(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MiuixIcon(vector: MiuixIcons.extended.byName('add')!, size: 18),
                const SizedBox(width: 8),
                MiuixText('添加音源', style: theme.textStyles.button),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        const MiuixSmallTitle(
          '默认音质',
          insideMargin: EdgeInsets.fromLTRB(16, 8, 16, 4),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'higher / 杜比全景声 / 高清环绕声 / 沉浸环绕声 / 超清母带仅对网易云生效，其余平台使用默认音质。',
            style: theme.textStyles.footnote1.copyWith(
              color: theme.colors.onSurfaceVariantSummary,
            ),
          ),
        ),
        _QualityCard(
          value: state.quality,
          enabled: !state.isBusy,
          onChanged: controller.setQuality,
        ),
        // 暂停适配 Lx Music，先隐藏页面级运行时说明；恢复适配时解除注释。
        // const SizedBox(height: 20),
        // CyreneInlineAlert(
        //   vector: MiuixIcons.extended.byName('info')!,
        //   title: 'Lx Music 运行时未启用',
        //   description:
        //       '当前 Android 版本可以导入、排序和持久化洛雪脚本，但尚不能执行 JavaScript。播放时会跳过该音源并继续尝试后续 OmniParse。',
        // ),
      ],
    );

    if (!desktopLayout) return content;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: SizedBox(width: double.infinity, child: content),
      ),
    );
  }

  Future<void> _chooseSourceType(BuildContext context) async {
    final action = await showCyreneDialog<_SourceSetupAction>(
      context: context,
      title: '添加音源',
      summary: '选择要配置的解析服务类型。',
      builder: (dialogContext, dismiss) {
        final theme = MiuixTheme.of(dialogContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            const SizedBox(height: 12),
            MiuixButton(
              key: const Key('choose-omniparse-source'),
              minHeight: 58,
              onPressed: () => dismiss(_SourceSetupAction.omniManual),
              child: Row(
                children: [
                  MiuixIcon(
                    vector: MiuixIcons.extended.byName('layers')!,
                    size: 19,
                  ),
                  const SizedBox(width: 10),
                  MiuixText('OmniParse', style: theme.textStyles.button),
                ],
              ),
            ),
            MiuixButton(
              key: const Key('import-omniparse-file'),
              minHeight: 58,
              onPressed: () => dismiss(_SourceSetupAction.omniFile),
              child: Row(
                children: [
                  MiuixIcon(
                    vector: MiuixIcons.extended.byName('import')!,
                    size: 19,
                  ),
                  const SizedBox(width: 10),
                  MiuixText('导入 .cyrene 文件', style: theme.textStyles.button),
                ],
              ),
            ),
            // 暂停适配 Lx Music，保留入口代码以便后续恢复。
            // MiuixButton(
            //   key: const Key('choose-lx-music-source'),
            //   minHeight: 58,
            //   onPressed: () => dismiss(_SourceSetupAction.lxMusic),
            //   child: Row(
            //     children: [
            //       MiuixIcon(
            //         vector: MiuixIcons.extended.byName('file')!,
            //         size: 19,
            //       ),
            //       const SizedBox(width: 10),
            //       MiuixText('Lx Music', style: theme.textStyles.button),
            //     ],
            //   ),
            // ),
          ],
        );
      },
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case _SourceSetupAction.omniManual:
        await _openOmniParseDialog(context);
      case _SourceSetupAction.omniFile:
        await _importOmniParseFile(context);
      case _SourceSetupAction.lxMusic:
        await _openLxMusicDialog(context);
    }
  }

  Future<void> _openOmniParseDialog(
    BuildContext context, {
    AudioSourceConfig? source,
  }) async {
    final draft = await showCyreneDialog<_OmniParseDraft>(
      context: context,
      title: source == null ? '添加 OmniParse' : '编辑 OmniParse',
      summary: '配置兼容 OmniParse 协议的解析服务。',
      builder: (_, dismiss) =>
          _OmniParseDialog(source: source, dismiss: dismiss),
    );
    if (!context.mounted || draft == null) return;
    final success = source == null
        ? await controller.addOmniParse(
            name: draft.name,
            url: draft.url,
            apiKey: draft.apiKey,
          )
        : await controller.updateOmniParse(
            id: source.id,
            name: draft.name,
            url: draft.url,
            apiKey: draft.apiKey,
          );
    if (context.mounted && success) {
      _showSuccess(context, source == null ? 'OmniParse 已添加' : 'OmniParse 已更新');
    }
  }

  Future<void> _editOmniParse(BuildContext context, AudioSourceConfig source) =>
      _openOmniParseDialog(context, source: source);

  Future<void> _openLxMusicDialog(BuildContext context) async {
    final action = await showCyreneDialog<_LxImportAction>(
      context: context,
      title: '导入 Lx Music',
      summary: '支持本地 JS/TXT 脚本或脚本直链。',
      builder: (_, dismiss) => _LxMusicImportDialog(dismiss: dismiss),
    );
    if (!context.mounted || action == null) return;

    var success = false;
    switch (action) {
      case _LxFileImport():
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['js', 'txt'],
          withData: true,
        );
        final file = result?.files.single;
        final bytes = file?.bytes;
        if (file == null || bytes == null) return;
        success = await controller.importLxMusicScript(
          utf8.decode(bytes, allowMalformed: true),
          sourceLabel: file.name,
        );
      case _LxUrlImport(:final url):
        success = await controller.importLxMusicUrl(url);
    }
    if (context.mounted && success) {
      _showSuccess(context, 'Lx Music 音源已导入');
    }
  }

  Future<void> _importOmniParseFile(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['cyrene'],
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (bytes == null) return;

    // 与 Next.js 行为对齐：先解密 .cyrene 文件，将结果预填到表单供用户确认，
    // 而非静默添加。
    final config = await CyreneConfigService.instance.decrypt(bytes);
    if (!context.mounted) return;
    if (config == null) {
      CyreneToast.show('配置文件解析失败，请检查文件是否损坏或密码不正确。');
      return;
    }

    final draft = await showCyreneDialog<_OmniParseDraft>(
      context: context,
      title: '导入 OmniParse 配置',
      summary: '配置文件已解密，请确认以下信息后保存。',
      builder: (_, dismiss) =>
          _OmniParseDialog(preFilledConfig: config, dismiss: dismiss),
    );
    if (!context.mounted || draft == null) return;
    final success = await controller.importOmniParse(bytes);
    if (context.mounted && success) {
      _showSuccess(context, 'OmniParse 配置已导入');
    }
  }

  Future<void> _confirmRemove(
    BuildContext context,
    AudioSourceConfig source,
  ) async {
    final confirmed = await showCyreneDialog<bool>(
      context: context,
      title: '删除音源？',
      summary: '“${_audioSourceDisplayName(source)}”将从本机配置中移除。',
      builder: (dialogContext, dismiss) {
        final theme = MiuixTheme.of(dialogContext);
        final colors = theme.colors;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                MiuixTextButton('取消', onPressed: () => dismiss(false)),
                const SizedBox(width: 10),
                MiuixButton(
                  onPressed: () => dismiss(true),
                  colors: MiuixButtonColors(
                    color: colors.error,
                    disabledColor: colors.disabledPrimaryButton,
                    contentColor: colors.onError,
                    disabledContentColor: colors.disabledOnPrimaryButton,
                  ),
                  child: MiuixText('删除', style: theme.textStyles.button),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (confirmed == true) await controller.removeSource(source.id);
  }

  void _showSuccess(BuildContext context, String message) {
    CyreneToast.show(message);
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.index,
    required this.isBusy,
    required this.onEnabledChanged,
    required this.onRemove,
    this.onEdit,
  });

  final AudioSourceConfig source;
  final int index;
  final bool isBusy;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback? onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final isPrimary = index == 0 && source.isEnabled;
    return MiuixCard(
      key: Key('audio-source-${source.id}'),
      insideMargin: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: MiuixIcon(
                    vector: MiuixIcons.extended.byName('sort')!,
                    size: 19,
                    tint: colors.onSurfaceVariantActions,
                  ),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isPrimary ? colors.primary : colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${index + 1}',
                  style: theme.textStyles.body2.copyWith(
                    fontWeight: FontWeight.w500,
                    color: isPrimary
                        ? colors.onPrimary
                        : colors.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (source.type == AudioSourceType.omniParse)
                MiuixIcon(
                  vector: MiuixIcons.extended.byName('layers')!,
                  size: 20,
                )
              else
                MiuixIcon(
                  vector: MiuixIcons.extended.byName('file')!,
                  size: 20,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _audioSourceDisplayName(source),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textStyles.body2.copyWith(
                              color: colors.onSurfaceContainer,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (isPrimary) ...[
                          const SizedBox(width: 7),
                          MiuixBadge(
                            containerColor: colors.primary,
                            contentColor: colors.onPrimary,
                            child: MiuixText(
                              '最高优先',
                              style: theme.textStyles.footnote2,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      source.type.displayName,
                      style: theme.textStyles.body2.copyWith(
                        color: colors.onSurfaceVariantSummary,
                      ),
                    ),
                  ],
                ),
              ),
              MiuixSwitch(
                value: source.isEnabled,
                enabled: !isBusy,
                onChanged: onEnabledChanged,
              ),
            ],
          ),
          // 暂停适配 Lx Music，隐藏旧配置卡片内的运行时警告。
          // if (source.type == AudioSourceType.lxMusic) ...[
          //   const SizedBox(height: 12),
          //   CyreneInlineAlert(
          //     vector: MiuixIcons.extended.byName('info')!,
          //     title: '运行时未启用',
          //     description: '该脚本当前不会在 Android 上执行。',
          //     destructive: true,
          //   ),
          // ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (onEdit != null)
                MiuixIconButton(
                  key: Key('edit-audio-source-${source.id}'),
                  enabled: !isBusy,
                  onPressed: onEdit,
                  child: MiuixIcon(
                    vector: MiuixIcons.extended.byName('edit')!,
                    size: 18,
                    tint: colors.onSurfaceContainer,
                  ),
                ),
              MiuixIconButton(
                key: Key('remove-audio-source-${source.id}'),
                enabled: !isBusy,
                onPressed: onRemove,
                child: MiuixIcon(
                  vector: MiuixIcons.extended.byName('delete')!,
                  size: 18,
                  tint: colors.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QualityCard extends StatelessWidget {
  const _QualityCard({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final AudioQuality value;
  final bool enabled;
  final ValueChanged<AudioQuality> onChanged;

  static const labels = {
    AudioQuality.standard: '标准',
    AudioQuality.higher: '较高',
    AudioQuality.exHigh: '极高',
    AudioQuality.lossless: '无损',
    AudioQuality.hiRes: 'Hi-Res',
    AudioQuality.jyeffect: '高清环绕声',
    AudioQuality.sky: '沉浸环绕声',
    AudioQuality.dolby: '杜比全景声',
    AudioQuality.jymaster: '超清母带',
  };

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return MiuixCard(
      insideMargin: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: AudioQuality.values
            .map(
              (quality) => MiuixButton(
                enabled: enabled,
                onPressed: () => onChanged(quality),
                colors: value == quality
                    ? MiuixButtonDefaults.buttonColorsPrimary(context)
                    : null,
                child: MiuixText(
                  labels[quality]!,
                  style: theme.textStyles.button,
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _EmptySources extends StatelessWidget {
  const _EmptySources({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return MiuixCard(
      insideMargin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            MiuixIcon(
              vector: MiuixIcons.extended.byName('music')!,
              size: 30,
              tint: theme.colors.onSurfaceContainer,
            ),
            const SizedBox(height: 10),
            Text(
              '暂无已配置音源',
              style: theme.textStyles.body1.copyWith(
                color: theme.colors.onSurfaceContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '至少添加一个可用音源才能解析在线歌曲。',
              style: theme.textStyles.body2.copyWith(
                color: theme.colors.onSurfaceVariantSummary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            MiuixButton(
              onPressed: onAdd,
              child: MiuixText('立即添加', style: theme.textStyles.button),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceError extends StatelessWidget {
  const _SourceError({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Stack(
      children: [
        CyreneInlineAlert(
          vector: MiuixIcons.extended.byName('info')!,
          title: '音源配置',
          description: message,
          destructive: true,
        ),
        Positioned(
          top: 6,
          right: 6,
          child: MiuixIconButton(
            onPressed: onDismiss,
            child: MiuixIcon(
              vector: MiuixIcons.extended.byName('close')!,
              size: 16,
              tint: colors.onErrorContainer,
            ),
          ),
        ),
      ],
    );
  }
}

typedef _OmniParseDraft = ({String name, String url, String apiKey});

class _OmniParseDialog extends StatefulWidget {
  const _OmniParseDialog({
    required this.dismiss,
    this.source,
    this.preFilledConfig,
  });

  /// 弹层关闭回调：带结果保存、不带结果取消（替代原 Navigator.pop）。
  final void Function([_OmniParseDraft?]) dismiss;
  final AudioSourceConfig? source;
  final CyreneConfig? preFilledConfig;

  @override
  State<_OmniParseDialog> createState() => _OmniParseDialogState();
}

class _OmniParseDialogState extends State<_OmniParseDialog> {
  late final _name = TextEditingController(
    text: widget.source?.name ?? widget.preFilledConfig?.name ?? '',
  );
  // 手动编辑源时展示可编辑的真实 URL/API Key；文件导入时后端 URL 与密钥属敏感
  // 信息，不预填进输入框（标签已用 ••• 遮蔽），否则禁用态输入框仍会显示控制器
  // 里的明文。保存时 _submit 对文件导入路径直接从 preFilledConfig 读取，无需控制器。
  late final _url = TextEditingController(
    text: widget.source?.url ?? '',
  );
  late final _apiKey = TextEditingController(
    text: widget.source?.apiKey ?? '',
  );
  String? _validationMessage;

  /// 是否从文件导入（URL 应隐藏且不可编辑，与 Next.js 行为对齐）。
  bool get _isFileImport =>
      widget.preFilledConfig != null && widget.source == null;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        const SizedBox(height: 4),
        // 从文件导入时显示"已导入配置"徽章（与 Next.js AudioSourceManager 对齐）。
        if (_isFileImport)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.primary.withAlpha(15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.primary.withAlpha(25)),
            ),
            child: Row(
              children: [
                MiuixIcon(
                  vector: MiuixIcons.extended.byName('info')!,
                  size: 20,
                  tint: colors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '已导入配置',
                        style: theme.textStyles.body2.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'URL: ••••••••••••••••',
                        style: theme.textStyles.body2.copyWith(
                          color: colors.onSurfaceVariantSummary,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        'Name: ${_name.text}',
                        style: theme.textStyles.body2.copyWith(
                          color: colors.onSurfaceVariantSummary,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        MiuixTextField(
          key: const Key('omniparse-name-field'),
          controller: _name,
          label: '音源名称',
          singleLine: true,
        ),
        MiuixTextField(
          key: const Key('omniparse-url-field'),
          controller: _url,
          keyboardType: TextInputType.url,
          enabled: !_isFileImport,
          label: _isFileImport ? '••••••••••••••••' : 'https://api.example.com',
          singleLine: true,
        ),
        MiuixTextField(
          key: const Key('omniparse-api-key-field'),
          controller: _apiKey,
          obscureText: true,
          enabled: !_isFileImport,
          label: _isFileImport ? '••••••••••••••••' : 'API Key（可选）',
          singleLine: true,
        ),
        if (_validationMessage != null)
          Text(
            _validationMessage!,
            style: theme.textStyles.body2.copyWith(color: colors.error),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            MiuixTextButton('取消', onPressed: () => widget.dismiss()),
            const SizedBox(width: 10),
            MiuixButton(
              key: const Key('save-omniparse-source'),
              onPressed: _submit,
              colors: MiuixButtonDefaults.buttonColorsPrimary(context),
              child: MiuixText('保存配置', style: theme.textStyles.button),
            ),
          ],
        ),
      ],
    );
  }

  void _submit() {
    final name = _name.text.trim();
    // 从文件导入时 URL 由加密配置提供，不能从禁用的文本框读取。
    final url = _isFileImport
        ? widget.preFilledConfig!.url.trim()
        : _url.text.trim();
    final uri = Uri.tryParse(url);
    if (name.isEmpty ||
        uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      setState(() => _validationMessage = '请输入名称和有效的 HTTP/HTTPS API 地址。');
      return;
    }
    widget.dismiss((
      name: name,
      url: url,
      apiKey: _isFileImport
          ? widget.preFilledConfig!.apiKey
          : _apiKey.text.trim(),
    ));
  }
}

sealed class _LxImportAction {
  const _LxImportAction();
}

class _LxFileImport extends _LxImportAction {
  const _LxFileImport();
}

class _LxUrlImport extends _LxImportAction {
  const _LxUrlImport(this.url);

  final String url;
}

class _LxMusicImportDialog extends StatefulWidget {
  const _LxMusicImportDialog({required this.dismiss});

  /// 弹层关闭回调：带结果导入、不带结果取消（替代原 Navigator.pop）。
  final void Function([_LxImportAction?]) dismiss;

  @override
  State<_LxMusicImportDialog> createState() => _LxMusicImportDialogState();
}

class _LxMusicImportDialogState extends State<_LxMusicImportDialog> {
  final _url = TextEditingController();
  String? _validationMessage;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        const SizedBox(height: 4),
        CyreneInlineAlert(
          vector: MiuixIcons.extended.byName('info')!,
          title: 'Android 运行时未启用',
          description: '导入配置不会启用 JavaScript 执行能力。',
          destructive: true,
        ),
        MiuixButton(
          key: const Key('import-lx-file-button'),
          onPressed: () => widget.dismiss(const _LxFileImport()),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MiuixIcon(
                vector: MiuixIcons.extended.byName('import')!,
                size: 18,
              ),
              const SizedBox(width: 8),
              MiuixText('选择脚本文件', style: theme.textStyles.button),
            ],
          ),
        ),
        Row(
          children: [
            const Expanded(child: MiuixHorizontalDivider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '或',
                style: theme.textStyles.body2.copyWith(
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
            ),
            const Expanded(child: MiuixHorizontalDivider()),
          ],
        ),
        MiuixTextField(
          key: const Key('lx-url-field'),
          controller: _url,
          keyboardType: TextInputType.url,
          label: 'https://example.com/source.js',
          singleLine: true,
        ),
        MiuixButton(
          key: const Key('import-lx-url-button'),
          onPressed: _submitUrl,
          colors: MiuixButtonDefaults.buttonColorsPrimary(context),
          child: MiuixText('从链接导入', style: theme.textStyles.button),
        ),
        if (_validationMessage != null)
          Text(
            _validationMessage!,
            style: theme.textStyles.body2.copyWith(color: colors.error),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [MiuixTextButton('取消', onPressed: () => widget.dismiss())],
        ),
      ],
    );
  }

  void _submitUrl() {
    final value = _url.text.trim();
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      setState(() => _validationMessage = '请输入有效的 HTTP/HTTPS 脚本直链。');
      return;
    }
    widget.dismiss(_LxUrlImport(value));
  }
}

/// 默认官方音源 id（app_dependencies 装配），Cyrene Premium 下发后覆盖它而非新增，避免重复源。
const _officialOmniParseId = 'official-omniparse';

/// 官方 Cyrene Premium 音源在列表中的固定显示名。
/// 该源由服务端下发、锁定不可编辑，故统一以品牌名展示，与存储的 name 无关。
const _officialOmniParseDisplayName = 'Cyrene Premium';

/// 官方音源（Cyrene Premium）固定显示品牌名；其余音源显示用户自定义名称。
String _audioSourceDisplayName(AudioSourceConfig source) =>
    source.id == _officialOmniParseId
        ? _officialOmniParseDisplayName
        : source.name;

/// Cyrene Premium 区块：显示持有状态、购买入口、重新下发。
class _ListeningCardCard extends StatefulWidget {
  const _ListeningCardCard({
    required this.controller,
    required this.account,
    required this.sources,
    required this.token,
  });

  final AudioSourcePreferencesController controller;
  final AccountSessionController account;
  final List<AudioSourceConfig> sources;
  final String token;

  @override
  State<_ListeningCardCard> createState() => _ListeningCardCardState();
}

class _ListeningCardCardState extends State<_ListeningCardCard> {
  bool? _hasCard;
  bool _loading = true;
  /// Cyrene Premium 当前定价（元），由 /card/status 下发，取自后端 config.json。
  double _price = ListeningCardService.defaultCardPrice;
  /// 持卡开通时间（后端 listening_card_since）。会员卡上展示。
  String? _grantedAt;
  Timer? _pollTimer;
  int _pollCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// 本机 official-omniparse 是否已下发 apiKey（非空）。
  bool get _hasLocalApiKey {
    final src = widget.sources
        .where((s) => s.id == _officialOmniParseId)
        .cast<AudioSourceConfig?>()
        .firstWhere((s) => s != null, orElse: () => null);
    return src != null && src.apiKey.isNotEmpty;
  }

  Future<void> _loadStatus() async {
    final result = await ListeningCardService.instance.getCardStatus(widget.token);
    if (!mounted) return;
    if (result == null) {
      setState(() {
        _loading = false;
        _hasCard = _hasLocalApiKey ? true : null;
      });
      return;
    }
    setState(() {
      _hasCard = result.hasCard;
      _price = result.price;
      _grantedAt = result.grantedAt;
      _loading = false;
    });
  }

  Future<void> _purchase() async {
    final type = await _choosePaymentMethod(context);
    if (type == null || !mounted) return;

    final ip = await SponsorService.instance.getClientIp();
    if (ip == null || ip.isEmpty) {
      if (mounted) CyreneToast.show('获取 IP 地址失败');
      return;
    }

    final result = await ListeningCardService.instance.purchaseCard(
      token: widget.token,
      type: type,
      clientip: ip,
    );
    if (result == null) {
      if (mounted) CyreneToast.show('下单失败，请稍后重试');
      return;
    }

    await _launchPayment(result.payInfo);
    if (!mounted) return;
    _startPolling(result.outTradeNo);
  }

  Future<String?> _choosePaymentMethod(BuildContext context) {
    return showCyreneDialog<String>(
      context: context,
      title: '选择支付方式',
      summary: 'Cyrene Premium ¥${_price.toStringAsFixed(2)}，永久买断。',
      builder: (dialogContext, dismiss) {
        final theme = MiuixTheme.of(dialogContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            const SizedBox(height: 12),
            MiuixButton(
              minHeight: 52,
              onPressed: () => dismiss('alipay'),
              child: Row(
                children: [
                  MiuixIcon(
                    vector: MiuixIcons.extended.byName('bankCards')!,
                    size: 19,
                    tint: const Color(0xFF3482FF),
                  ),
                  const SizedBox(width: 10),
                  MiuixText('支付宝', style: theme.textStyles.button),
                ],
              ),
            ),
            MiuixButton(
              minHeight: 52,
              onPressed: () => dismiss('wxpay'),
              child: Row(
                children: [
                  MiuixIcon(
                    vector: MiuixIcons.extended.byName('messages')!,
                    size: 19,
                    tint: const Color(0xFF3CC756),
                  ),
                  const SizedBox(width: 10),
                  MiuixText('微信支付', style: theme.textStyles.button),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// 在系统默认浏览器打开支付链接。
  ///
  /// 网关返回字段名不固定，按 Next.js demo 的兜底链取值：
  /// `pay_info || qrcode || payurl || urlscheme`（见 DonateDialog.tsx）。
  /// 后端 /card/purchase 把整个网关响应塞进 data.pay_info，故这里在 payInfo 对象
  /// 内部按该链找第一个非空字符串字段。
  Future<void> _launchPayment(Map<String, Object?> payInfo) async {
    final url = [
      payInfo['pay_info'],
      payInfo['qrcode'],
      payInfo['payurl'],
      payInfo['urlscheme'],
    ].map((e) => e?.toString() ?? '').firstWhere((s) => s.isNotEmpty, orElse: () => '');
    if (url.isEmpty) {
      debugPrint('[ListeningCard] payInfo 无可用链接: $payInfo');
      if (mounted) CyreneToast.show('未获取到支付链接');
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      debugPrint('[ListeningCard] 支付链接无效: $url');
      if (mounted) CyreneToast.show('支付链接无效');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      if (mounted) CyreneToast.show('无法打开支付链接，请重试');
      return;
    }
    if (mounted) CyreneToast.show('请在新打开的页面完成支付');
  }

  /// 轮询 /pay/query，status==1 视为支付成功，落卡配置。
  void _startPolling(String outTradeNo) {
    _pollTimer?.cancel();
    _pollCount = 0;
    if (mounted) {
      setState(() => _loading = true);
    }
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
      _pollCount++;
      if (_pollCount > 100) {
        // 5 分钟超时
        t.cancel();
        if (mounted) {
          setState(() => _loading = false);
          CyreneToast.show('支付超时，如已付款请稍后重试下发');
        }
        return;
      }
      try {
        final result = await SponsorService.instance.queryPayStatus(outTradeNo);
        final status = result['status'];
        if (status == 1 || status == '1') {
          t.cancel();
          await _finalizeCard();
        }
      } catch (_) {
        // 单次查询失败继续轮询
      }
    });
  }

  /// 支付成功：拉取下发配置并应用，避免重复源。
  Future<void> _finalizeCard() async {
    // 优先回写持卡状态：即便下方 fetchCardConfig 因网络抖动失败，个人中心/
    // 我的页的徽章与「赞助状态」行也能先反映 Cyrene Premium（支付已成功，
    // 用户不该因音源下发失败而看不到 Premium 状态）。
    final grantedAt = DateTime.now().toIso8601String();
    await widget.account.patchUser(
      (u) => u.copyWith(
        hasListeningCard: true,
        listeningCardSince: u.listeningCardSince ?? grantedAt,
      ),
    );
    if (mounted) {
      setState(() {
        _hasCard = true;
        _grantedAt ??= grantedAt;
      });
    }
    try {
      final config = await ListeningCardService.instance.fetchCardConfig(widget.token);
      if (config == null) {
        if (mounted) {
          setState(() => _loading = false);
          CyreneToast.show('Cyrene Premium 已激活，音源配置下发失败，请稍后重试下发');
        }
        return;
      }
      final success = await _applyConfig(config);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasCard = true;
      });
      if (mounted) CyreneToast.show(success ? 'Cyrene Premium 已激活' : 'Cyrene Premium 已激活（音源已更新）');
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        CyreneToast.show('Cyrene Premium 已激活，音源配置下发失败，请稍后重试下发');
      }
    }
  }

  /// 应用下发的 CyreneConfig：覆盖 official-omniparse，不存在则新增。
  ///
  /// 固定以稳定 id `official-omniparse` 落地，使其后续可被识别为官方源
  /// （UI 锁定不可编辑、显示品牌名 Cyrene Premium）。name 仅作存储记录，
  /// 真实展示名以 [_officialOmniParseDisplayName] 为准。
  Future<bool> _applyConfig(CyreneConfig config) async {
    final existing = widget.sources
        .where((s) => s.id == _officialOmniParseId)
        .cast<AudioSourceConfig?>()
        .firstWhere((s) => s != null, orElse: () => null);
    if (existing != null) {
      return widget.controller.updateOmniParse(
        id: _officialOmniParseId,
        name: config.name.isEmpty ? existing.name : config.name,
        url: config.url.isEmpty ? existing.url : config.url,
        apiKey: config.apiKey,
      );
    }
    return widget.controller.addOmniParse(
      id: _officialOmniParseId,
      name: config.name.isEmpty ? 'Cyrene Premium' : config.name,
      url: config.url,
      apiKey: config.apiKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final hasCard = _hasCard == true;

    // 持卡：展示仿真会员卡（类 Visa 卡面）；未持卡：保持原购买卡片不变。
    if (hasCard) {
      return _PremiumMembershipCard(
        grantedAt: _grantedAt,
        loading: _loading,
        onRedeliver: _redeliver,
      );
    }

    return MiuixCard(
      insideMargin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MiuixIcon(
                vector: MiuixIcons.extended.byName('promotions')!,
                size: 22,
                tint: colors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cyrene Premium',
                  style: theme.textStyles.body1.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '付款 ${_price.toStringAsFixed(2)} 元，自动下发并激活 OmniParse 音源配置，永久买断。',
            style: theme.textStyles.body2.copyWith(
              color: colors.onSurfaceVariantSummary,
            ),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: MiuixCircularProgressIndicator(),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: MiuixButton(
                    key: const Key('listening-card-action'),
                    onPressed: _purchase,
                    colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                    child: MiuixText(
                      '购买 Cyrene Premium ¥${_price.toStringAsFixed(2)}',
                      style: theme.textStyles.button,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 已持卡用户主动重新下发（服务端轮换 apiKey 后手动刷新）。
  Future<void> _redeliver() async {
    if (mounted) setState(() => _loading = true);
    try {
      final config = await ListeningCardService.instance.fetchCardConfig(widget.token);
      if (config == null) {
        if (mounted) {
          setState(() => _loading = false);
          CyreneToast.show('配置下发失败，请稍后重试');
        }
        return;
      }
      await _applyConfig(config);
      if (!mounted) return;
      setState(() => _loading = false);
      CyreneToast.show('配置已更新');
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        CyreneToast.show('配置下发失败，请稍后重试');
      }
    }
  }
}

/// 持卡用户的仿真会员卡（类 Visa 卡面）。
///
/// 深紫渐变卡身 + 金色 EMV 芯片 + 品牌 wordmark + 持卡人（用户名）+
/// 永久买断标识 + 开通时间。卡身本身仅展示，下方接「重新下发配置」入口。
/// 卡片下方留按钮行，与未持卡卡片在同一区块内对齐。
class _PremiumMembershipCard extends StatelessWidget {
  const _PremiumMembershipCard({
    required this.grantedAt,
    required this.loading,
    required this.onRedeliver,
  });

  final String? grantedAt;
  final bool loading;
  final VoidCallback onRedeliver;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MembershipCardFace(grantedAt: grantedAt),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: MiuixButton(
                key: const Key('listening-card-action'),
                onPressed: loading ? null : onRedeliver,
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: MiuixCircularProgressIndicator(strokeWidth: 2),
                      )
                    : MiuixText('重新下发配置', style: theme.textStyles.button),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 桌面端 Premium 说明，与左侧仿真卡形成紧凑的横向信息区。
class _PremiumIntroduction extends StatelessWidget {
  const _PremiumIntroduction();

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return MiuixCard(
      insideMargin: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MiuixIcon(
                vector: MiuixIcons.extended.byName('promotions')!,
                size: 24,
                tint: theme.colors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'CyreneMusic Premium',
                  style: theme.textStyles.title3.copyWith(
                    color: theme.colors.onSurfaceContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'CyreneMusic Premium 是一项买断制的订阅服务，让您可以畅享主流平台的音乐。',
            style: theme.textStyles.body1.copyWith(
              color: theme.colors.onSurfaceVariantSummary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡面本体：渐变 + 光泽 + 芯片 + 文案。固定高度，比例接近真实卡（1.585）。
class _MembershipCardFace extends StatelessWidget {
  const _MembershipCardFace({required this.grantedAt});

  final String? grantedAt;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    // 卡面主色：Premium 紫，与个人中心徽章同源（0xFF8A64FF）。
    const primary = Color(0xFF8A64FF);
    final memberSince = _formatMemberSince(grantedAt);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 1.585,
        child: Stack(
          children: [
            // 卡身渐变：左上深紫 → 右下近黑，营造金属质感。
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      primary,
                      const Color(0xFF5B3FD6),
                      const Color(0xFF2A1B5C),
                    ],
                  ),
                ),
              ),
            ),
            // 光泽：右上角高光弧，模拟卡面反光。
            Positioned(
              top: -60,
              right: -40,
              child: Transform.rotate(
                angle: -0.5,
                child: Container(
                  width: 220,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    color: Colors.white.withValues(alpha: .12),
                  ),
                ),
              ),
            ),
            // 细网格纹理：极淡，增加卡面质感。
            Positioned.fill(
              child: CustomPaint(painter: _CardGridPainter()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 顶部：品牌 wordmark + 永久买断标。
                  LayoutBuilder(
                    builder: (context, constraints) => Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        MiuixIcon(
                          vector: MiuixIcons.extended.byName('promotions')!,
                          size: 20,
                          tint: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Cyrene Premium',
                          style: theme.textStyles.body1.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                        if (constraints.maxWidth >= 300) ...[
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.white.withValues(alpha: .16),
                            ),
                            child: Text(
                              '永久买断',
                              style: theme.textStyles.footnote2.copyWith(
                                color: Colors.white.withValues(alpha: .92),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // 中部：金色 EMV 芯片。
                  _EmvChip(),
                  // 底部：开通时间 + 品牌 wordmark。
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '开通时间',
                              style: theme.textStyles.footnote2.copyWith(
                                color: Colors.white.withValues(alpha: .65),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              memberSince,
                              style: theme.textStyles.body2.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'CYRENE',
                        style: theme.textStyles.body1.copyWith(
                          color: Colors.white.withValues(alpha: .85),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ISO 时间串 → 卡面风格 "yyyy.MM.dd"；解析失败回落到占位。
  String _formatMemberSince(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}.${two(dt.month)}.${two(dt.day)}';
  }
}

/// 金色 EMV 芯片：圆角矩形 + 横向分槽，模拟银行卡芯片外观。
class _EmvChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 32,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFFFFD479),
                      const Color(0xFFFFC107),
                      const Color(0xFFC8901A),
                    ],
                  ),
                ),
              ),
            ),
            // 横向分槽线。
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(
                  3,
                  (_) => Container(
                    height: 0.6,
                    color: Colors.black.withValues(alpha: .25),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 极淡网格纹理，给卡面加质感，不影响主信息可读性。
class _CardGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .04)
      ..strokeWidth = 0.5;
    const step = 16.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
