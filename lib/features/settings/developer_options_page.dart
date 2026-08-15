import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../infrastructure/core/url_service.dart';
import '../../infrastructure/services/account_pool_service.dart';
import '../../infrastructure/services/developer_mode_service.dart';
import '../../infrastructure/services/network_capture_service.dart';
import '../../infrastructure/services/sponsor_admin_service.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
import 'account_pool_page.dart';
import 'sponsor_admin_page.dart';

/// 开发者选项（对应原版 developer_page.dart 在移动端有意义的核心子集：
/// 性能叠加层开关 + 运行日志；另补充显示模式信息用于核对高刷是否生效）。
/// 入口仅在开发者模式开启时出现在设置主页。
class DeveloperOptionsPage extends StatefulWidget {
  const DeveloperOptionsPage({super.key});

  @override
  State<DeveloperOptionsPage> createState() => _DeveloperOptionsPageState();
}

class _DeveloperOptionsPageState extends State<DeveloperOptionsPage> {
  static const _iconBlue = Color(0xFF3482FF);
  static const _iconGreen = Color(0xFF3CC756);
  static const _iconOrange = Color(0xFFFF9F0A);

  final _developer = DeveloperModeService.instance;
  String _displayModeText = '读取中…';

  @override
  void initState() {
    super.initState();
    _loadDisplayMode();
    NetworkCaptureService.instance.ensureLoaded();
  }

  Future<void> _loadDisplayMode() async {
    if (!Platform.isAndroid) {
      setState(() => _displayModeText = '仅 Android 可用');
      return;
    }
    try {
      final active = await FlutterDisplayMode.active;
      final supported = await FlutterDisplayMode.supported;
      final best = supported.fold<int>(
        0,
        (max, mode) => mode.refreshRate > max ? mode.refreshRate.round() : max,
      );
      if (!mounted) return;
      setState(() {
        _displayModeText =
            '${active.width}x${active.height} @${active.refreshRate.round()}Hz'
            '（设备最高 ${best}Hz）';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _displayModeText = '读取失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) => CyrenePage(
    title: '开发者选项',
    bodyBuilder: (context, topPadding) => ListenableBuilder(
      listenable: Listenable.merge([
        _developer,
        NetworkCaptureService.instance,
      ]),
      builder: (context, _) => ListView(
        physics: const BouncingScrollPhysics(),
        padding: topPadding + const EdgeInsets.fromLTRB(12, 4, 12, 40),
        children: [
          const MiuixSmallTitle(
            '调试',
            insideMargin: EdgeInsets.fromLTRB(16, 8, 16, 8),
          ),
          CyreneMenuGroup(
            children: [
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('stopwatch')!,
                iconBackground: _iconGreen,
                title: '性能叠加层',
                subtitle: '在应用上方显示 UI/Raster 线程帧耗时图表',
                trailing: MiuixSwitch(
                  value: _developer.showPerformanceOverlay,
                  onChanged: _developer.setShowPerformanceOverlay,
                ),
                onTap: () => _developer.setShowPerformanceOverlay(
                  !_developer.showPerformanceOverlay,
                ),
              ),
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('layers')!,
                iconBackground: _iconBlue,
                title: '合并搜索结果',
                subtitle: '关闭后搜索页按平台分别展示结果标签',
                trailing: MiuixSwitch(
                  value: _developer.isSearchResultMergeEnabled,
                  onChanged: _developer.setSearchResultMergeEnabled,
                ),
                onTap: () => _developer.setSearchResultMergeEnabled(
                  !_developer.isSearchResultMergeEnabled,
                ),
              ),
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('screenMirroring')!,
                iconBackground: _iconBlue,
                title: '显示模式',
                subtitle: _displayModeText,
                trailing: const SizedBox.shrink(),
                onTap: _loadDisplayMode,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const MiuixSmallTitle(
            '日志',
            insideMargin: EdgeInsets.fromLTRB(16, 8, 16, 8),
          ),
          CyreneMenuGroup(
            children: [
              ValueListenableBuilder<int>(
                valueListenable: _developer.logRevision,
                builder: (context, _, _) => CyreneMenuRow(
                  vector: MiuixIcons.extended.byName('notes')!,
                  iconBackground: _iconOrange,
                  title: '运行日志',
                  subtitle: '应用内 debugPrint 输出（上限 1000 条）',
                  value: '${_developer.logs.length} 条',
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => const _DeveloperLogPage(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const MiuixSmallTitle(
            '网络',
            insideMargin: EdgeInsets.fromLTRB(16, 8, 16, 8),
          ),
          CyreneMenuGroup(
            children: [
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('tune')!,
                iconBackground: _iconGreen,
                title: '网络捕获',
                subtitle: '开启后记录所有 API 请求与响应数据',
                trailing: MiuixSwitch(
                  value: NetworkCaptureService.instance.enabled,
                  onChanged: NetworkCaptureService.instance.setEnabled,
                ),
                onTap: () => NetworkCaptureService.instance.setEnabled(
                  !NetworkCaptureService.instance.enabled,
                ),
              ),
              ValueListenableBuilder<int>(
                valueListenable: NetworkCaptureService.instance.revision,
                builder: (context, _, _) => CyreneMenuRow(
                  vector: MiuixIcons.extended.byName('notes')!,
                  iconBackground: _iconOrange,
                  title: '查看捕获记录',
                  subtitle: '查看 API 请求与响应的原始数据',
                  value: '${NetworkCaptureService.instance.entries.length} 条',
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => const _NetworkCapturePage(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const MiuixSmallTitle(
            '后端',
            insideMargin: EdgeInsets.fromLTRB(16, 8, 16, 8),
          ),
          CyreneMenuGroup(
            children: [
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('link')!,
                iconBackground: _iconBlue,
                title: '后端地址',
                subtitle: UrlService.instance.baseUrl,
                value: UrlService.instance.sourceType == BackendSourceType.official
                    ? '官方'
                    : '自定义',
                onTap: _editBackendUrl,
              ),
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('contactsCircle')!,
                iconBackground: _iconOrange,
                title: '号池管理',
                subtitle: '管理后端公共账号状态与扫码登录',
                onTap: _openAccountPool,
              ),
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('bankCards')!,
                iconBackground: _iconGreen,
                title: '订阅和赞助管理',
                subtitle: '手动管理用户订阅与赞助金额',
                onTap: _openSponsorAdmin,
              ),
            ],
          ),
          const SizedBox(height: 12),
          CyreneMenuGroup(
            children: [
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('back')!,
                title: '退出开发者模式',
                destructive: true,
                trailing: const SizedBox.shrink(),
                onTap: () => _confirmExit(context),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _confirmExit(BuildContext context) async {
    final confirmed = await showCyreneDialog<bool>(
      context: context,
      title: '退出开发者模式？',
      summary: '性能叠加层将一并关闭；可随时连点版本号重新开启。',
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
                  child: MiuixText('退出', style: theme.textStyles.button),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await _developer.disableDeveloperMode();
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _editBackendUrl() async {
    final urls = UrlService.instance;
    final draft = await showCyreneDialog<_BackendDraft>(
      context: context,
      title: '后端地址',
      summary: '自定义后端可指向本地开发服务器，方便调试。',
      builder: (dialogContext, dismiss) => _BackendUrlEditor(
        initialCustom: urls.sourceType == BackendSourceType.custom,
        initialUrl: urls.customBaseUrl.isNotEmpty
            ? urls.customBaseUrl
            : UrlService.officialBaseUrl,
        onCancel: () => dismiss(),
        onSave: (d) => dismiss(d),
      ),
    );
    if (draft == null) return;

    if (draft.useCustom) {
      urls.setCustomBaseUrl(draft.url);
      urls.setSourceType(BackendSourceType.custom);
      CyreneToast.show('已切换到自定义后端');
    } else {
      urls.setSourceType(BackendSourceType.official);
      CyreneToast.show('已切换回官方服务器');
    }
    if (mounted) setState(() {});
  }

  Future<void> _openAccountPool() async {
    final token = await _promptAdminPassword(
      title: '号池管理',
      summary: '请输入管理密码以访问号池账号',
      login: AccountPoolService.instance.login,
    );
    if (token == null || !mounted) return;
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => AccountPoolPage(token: token),
      ),
    );
  }

  Future<void> _openSponsorAdmin() async {
    final token = await _promptAdminPassword(
      title: '订阅和赞助管理',
      summary: '请输入管理密码以管理用户订阅与赞助',
      login: SponsorAdminService.instance.login,
    );
    if (token == null || !mounted) return;
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => SponsorAdminPage(token: token),
      ),
    );
  }

  Future<String?> _promptAdminPassword({
    required String title,
    required String summary,
    required Future<String?> Function(String password) login,
  }) {
    return showCyreneDialog<String>(
      context: context,
      title: title,
      summary: summary,
      builder: (dialogContext, dismiss) => _PasswordGate(
        login: login,
        onCancel: () => dismiss(),
        onSuccess: (token) => dismiss(token),
      ),
    );
  }
}

/// 管理功能密码门弹层：输入密码后调用对应后端登录接口校验。
class _PasswordGate extends StatefulWidget {
  const _PasswordGate({
    required this.login,
    required this.onCancel,
    required this.onSuccess,
  });

  final Future<String?> Function(String password) login;
  final VoidCallback onCancel;
  final void Function(String token) onSuccess;

  @override
  State<_PasswordGate> createState() => _PasswordGateState();
}

class _PasswordGateState extends State<_PasswordGate> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _controller.text.trim();
    if (password.isEmpty) {
      setState(() => _error = '请输入密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await widget.login(password);
      if (!mounted) return;
      if (token != null) {
        widget.onSuccess(token);
      } else {
        setState(() {
          _busy = false;
          _error = '密码错误';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '无法连接后端：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MiuixTextField(
          controller: _controller,
          label: '管理密码',
          singleLine: true,
          autofocus: true,
          obscureText: _obscure,
          enabled: !_busy,
          leadingIcon: MiuixIcon(
            vector: MiuixIcons.extended.byName('lock')!,
            size: 20,
            tint: colors.onSecondaryContainer,
          ),
          trailingIcon: Padding(
            padding: const EdgeInsets.only(left: 4, right: 8),
            child: MiuixIconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              child: MiuixIcon(
                vector: MiuixIcons.extended.byName(_obscure ? 'hide' : 'show')!,
                size: 20,
                tint: colors.onSecondaryContainer,
              ),
            ),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (!_busy) _submit();
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: theme.textStyles.footnote1.copyWith(color: colors.error),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            MiuixTextButton('取消', onPressed: _busy ? null : widget.onCancel),
            const SizedBox(width: 10),
            MiuixButton(
              onPressed: _busy ? null : _submit,
              colors: MiuixButtonDefaults.buttonColorsPrimary(context),
              child: _busy
                  ? const MiuixCircularProgressIndicator(size: 16, strokeWidth: 2)
                  : MiuixText('确认', style: theme.textStyles.button),
            ),
          ],
        ),
      ],
    );
  }
}

/// 运行日志查看页：等宽小字号逐行展示，支持复制全部与清空。
class _DeveloperLogPage extends StatelessWidget {
  const _DeveloperLogPage();

  @override
  Widget build(BuildContext context) {
    final developer = DeveloperModeService.instance;
    final theme = MiuixTheme.of(context);
    return CyrenePage(
      title: '运行日志',
      largeTitle: false,
      actions: [
        MiuixIconButton(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: developer.logs.join('\n')),
            );
            CyreneToast.show('日志已复制到剪贴板');
          },
          child: MiuixIcon(
            vector: MiuixIcons.extended.byName('copy')!,
            size: 20,
          ),
        ),
        MiuixIconButton(
          onPressed: () {
            developer.clearLogs();
            CyreneToast.show('日志已清空');
          },
          child: MiuixIcon(
            vector: MiuixIcons.extended.byName('delete')!,
            size: 20,
            tint: theme.colors.error,
          ),
        ),
      ],
      body: ValueListenableBuilder<int>(
        valueListenable: developer.logRevision,
        builder: (context, _, _) {
          final logs = developer.logs;
          if (logs.isEmpty) {
            return CyreneEmptyState(
              vector: MiuixIcons.extended.byName('notes')!,
              title: '暂无日志',
              description: '应用内的 debugPrint 输出会实时收集到这里。',
            );
          }
          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            itemCount: logs.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText(
                logs[index],
                style: theme.textStyles.footnote1.copyWith(
                  color: theme.colors.onSurfaceContainer,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 后端地址编辑结果。
class _BackendDraft {
  const _BackendDraft({required this.useCustom, required this.url});

  final bool useCustom;
  final String url;
}

/// 后端地址编辑弹层内容：切换官方/自定义 + 输入自定义地址。
class _BackendUrlEditor extends StatefulWidget {
  const _BackendUrlEditor({
    required this.initialCustom,
    required this.initialUrl,
    required this.onCancel,
    required this.onSave,
  });

  final bool initialCustom;
  final String initialUrl;
  final VoidCallback onCancel;
  final void Function(_BackendDraft draft) onSave;

  @override
  State<_BackendUrlEditor> createState() => _BackendUrlEditorState();
}

class _BackendUrlEditorState extends State<_BackendUrlEditor> {
  late bool _useCustom = widget.initialCustom;
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialUrl,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (!_useCustom) {
      widget.onSave(const _BackendDraft(useCustom: false, url: ''));
      return;
    }
    final url = _controller.text.trim();
    if (!UrlService.instance.isValidUrl(url)) {
      setState(() => _error = '请输入有效的 http(s) 地址');
      return;
    }
    widget.onSave(_BackendDraft(useCustom: true, url: url));
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '使用自定义地址',
                style: theme.textStyles.body2.copyWith(
                  color: colors.onSurfaceContainer,
                ),
              ),
            ),
            MiuixSwitch(
              value: _useCustom,
              onChanged: (value) => setState(() {
                _useCustom = value;
                _error = null;
              }),
            ),
          ],
        ),
        if (_useCustom) ...[
          const SizedBox(height: 8),
          MiuixTextField(
            controller: _controller,
            label: '后端地址（http/https）',
            singleLine: true,
            autofocus: true,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textStyles.footnote1.copyWith(color: colors.error),
            ),
          ],
        ] else ...[
          const SizedBox(height: 8),
          Text(
            '官方服务器：${UrlService.officialBaseUrl}',
            style: theme.textStyles.footnote1.copyWith(
              color: colors.onSurfaceVariantSummary,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: MiuixTextButton('取消', onPressed: widget.onCancel),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MiuixButton(
                onPressed: _save,
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                child: MiuixText('保存', style: theme.textStyles.button),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 网络捕获记录查看页。
class _NetworkCapturePage extends StatelessWidget {
  const _NetworkCapturePage();

  String _formatEntry(NetworkCaptureEntry e) => [
    '[${e.method}] ${e.url}',
    if (e.isError) '错误: ${e.error}',
    if (!e.isError) '状态: ${e.status}',
    if (e.requestBody != null) '请求体: ${e.requestBody}',
    if (e.responseBody.isNotEmpty) '响应体: ${e.responseBody}',
  ].join('\n');

  @override
  Widget build(BuildContext context) {
    final capture = NetworkCaptureService.instance;
    final theme = MiuixTheme.of(context);
    return CyrenePage(
      title: '网络捕获',
      largeTitle: false,
      actions: [
        MiuixIconButton(
          onPressed: () async {
            final text = capture.entries
                .map(_formatEntry)
                .join('\n\n--------\n\n');
            await Clipboard.setData(ClipboardData(text: text));
            CyreneToast.show('已复制全部捕获');
          },
          child: MiuixIcon(vector: MiuixIcons.extended.byName('copy')!, size: 20),
        ),
        MiuixIconButton(
          onPressed: () {
            capture.clear();
            CyreneToast.show('已清空捕获记录');
          },
          child: MiuixIcon(
            vector: MiuixIcons.extended.byName('delete')!,
            size: 20,
            tint: theme.colors.error,
          ),
        ),
      ],
      body: ValueListenableBuilder<int>(
        valueListenable: capture.revision,
        builder: (context, _, _) {
          final entries = capture.entries;
          if (entries.isEmpty) {
            return CyreneEmptyState(
              vector: MiuixIcons.extended.byName('link')!,
              title: '暂无捕获',
              description: '在开发者选项中开启「网络捕获」后，API 请求会记录到这里。',
            );
          }
          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              // 最新的在最上面。
              final entry = entries[entries.length - 1 - index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _NetworkCaptureCard(entry: entry),
              );
            },
          );
        },
      ),
    );
  }
}

/// 单条捕获卡片：方法/状态/URL + 请求体 + 响应体。
class _NetworkCaptureCard extends StatelessWidget {
  const _NetworkCaptureCard({required this.entry});

  final NetworkCaptureEntry entry;

  static String _prettyJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return raw;
    }
  }

  Color _methodColor(String method) => switch (method) {
    'GET' => const Color(0xFF3482FF),
    'POST' => const Color(0xFF3CC756),
    'DELETE' => const Color(0xFFFF5252),
    _ => const Color(0xFFFF9F0A),
  };

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final mono = theme.textStyles.footnote1.copyWith(
      fontFamily: 'monospace',
      fontSize: 11,
    );
    final statusColor = entry.isError
        ? colors.error
        : (entry.status != null && entry.status! >= 400)
        ? colors.error
        : (entry.status != null && entry.status! >= 300)
        ? const Color(0xFFFF9F0A)
        : const Color(0xFF3CC756);

    return MiuixCard(
      insideMargin: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                entry.method,
                style: mono.copyWith(
                  color: _methodColor(entry.method),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                entry.isError ? '网络错误' : '${entry.status}',
                style: mono.copyWith(color: statusColor),
              ),
              const Spacer(),
              Text(
                entry.time.toIso8601String().substring(11, 23),
                style: mono.copyWith(color: colors.onSurfaceVariantSummary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            entry.url,
            style: mono.copyWith(color: colors.onSurfaceContainer),
          ),
          if (entry.requestBody != null) ...[
            const SizedBox(height: 8),
            Text(
              '请求体',
              style: mono.copyWith(
                color: colors.onSurfaceVariantSummary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(
              _prettyJson(entry.requestBody!),
              style: mono.copyWith(color: colors.onSurfaceContainer),
            ),
          ],
          if (entry.isError) ...[
            const SizedBox(height: 8),
            Text(
              '错误',
              style: mono.copyWith(color: colors.error, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            SelectableText(entry.error!, style: mono.copyWith(color: colors.error)),
          ] else if (entry.responseBody.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '响应体',
              style: mono.copyWith(
                color: colors.onSurfaceVariantSummary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(
              _prettyJson(entry.responseBody),
              style: mono.copyWith(color: colors.onSurfaceContainer),
            ),
          ],
        ],
      ),
    );
  }
}
