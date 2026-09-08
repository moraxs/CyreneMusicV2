import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/stores/ai_settings_store.dart';
import '../../domain/ai/ai_models.dart';
import '../../infrastructure/ai/ai_client.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
import 'settings_body.dart';

/// 「AI 助手」设置：兼容路由、Base URL、API Key、模型，以及一个测试连接。
class AiSettingsPage extends StatelessWidget {
  const AiSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => CyrenePage(
    title: 'AI 助手',
    bodyBuilder: (context, topPadding) =>
        AiSettingsBody(topPadding: topPadding),
  );
}

/// 「AI 助手」设置正文，不含页面骨架。
///
/// 独立成组件是为了让桌面端的合并设置页直接嵌这一份（连同「测试连接」的
/// 临时状态一起搬过来），而不是照抄一遍表单。
class AiSettingsBody extends StatefulWidget {
  const AiSettingsBody({
    super.key,
    this.topPadding = EdgeInsets.zero,
    this.embedded = false,
  });

  final EdgeInsets topPadding;
  final bool embedded;

  @override
  State<AiSettingsBody> createState() => _AiSettingsBodyState();
}

class _AiSettingsBodyState extends State<AiSettingsBody> {
  final _settings = AiSettingsStore.instance;

  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => SettingsBody(
        topPadding: widget.topPadding,
        embedded: widget.embedded,
        children: [
          CyreneMenuGroup(
            children: [
              CyreneMenuRow(
                key: const Key('toggle-ai'),
                vector: MiuixIcons.extended.byName('mindMap')!,
                iconBackground: const Color(0xFF7C5CFF),
                title: '启用 AI 功能',
                subtitle: '用你自己的模型服务生成赏析、总结与推荐',
                trailing: MiuixSwitch(
                  value: _settings.enabled,
                  onChanged: _settings.setEnabled,
                ),
                onTap: () => _settings.setEnabled(!_settings.enabled),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const MiuixSmallTitle(
            '服务配置',
            insideMargin: EdgeInsets.fromLTRB(16, 4, 16, 8),
          ),
          CyreneMenuGroup(
            children: [
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('link')!,
                iconBackground: const Color(0xFF3482FF),
                title: '兼容路由',
                subtitle: _settings.route == AiRoute.openai
                    ? 'POST {地址}/chat/completions'
                    : 'POST {地址}/v1/messages',
                value: _settings.route.label,
                onTap: _pickRoute,
              ),
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('cloudFill')!,
                iconBackground: const Color(0xFF00A6A6),
                title: 'Base URL',
                subtitle: _settings.baseUrl.isEmpty
                    ? '如 ${_settings.route.baseUrlHint}'
                    : null,
                value: _shorten(_settings.baseUrl),
                onTap: () => _editText(
                  title: 'Base URL',
                  summary: '带不带结尾的 /v1 都可以，会自动补齐路径',
                  initial: _settings.baseUrl,
                  hint: _settings.route.baseUrlHint,
                  onSubmit: _settings.setBaseUrl,
                ),
              ),
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('lock')!,
                iconBackground: const Color(0xFFFF375F),
                title: 'API Key',
                subtitle: _settings.apiKey.isEmpty ? '还没有填' : '已加密保存在本机',
                value: _settings.maskedApiKey,
                onTap: () => _editText(
                  title: 'API Key',
                  summary: '只保存在这台设备上，不会上传到 Cyrene 的服务器',
                  initial: _settings.apiKey,
                  hint: 'sk-...',
                  obscure: true,
                  onSubmit: _settings.setApiKey,
                ),
              ),
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('playlist')!,
                iconBackground: const Color(0xFF3CC756),
                title: '模型',
                subtitle: _settings.model.isEmpty
                    ? '如 ${_settings.route.suggestedModel}'
                    : null,
                value: _shorten(_settings.model),
                onTap: () => _editText(
                  title: '模型',
                  summary: '填服务端认得的模型名，两家的模型名不通用',
                  initial: _settings.model,
                  hint: _settings.route.suggestedModel,
                  onSubmit: _settings.setModel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CyreneMenuGroup(
            children: [
              CyreneMenuRow(
                key: const Key('test-ai-connection'),
                vector: MiuixIcons.extended.byName('refresh')!,
                iconBackground: const Color(0xFFFF9F0A),
                title: '测试连接',
                subtitle: '真发一次请求，把服务端的原话带回来',
                trailing: _testing
                    ? const MiuixCircularProgressIndicator(
                        size: 18,
                        strokeWidth: 2,
                      )
                    : null,
                onTap: _testing ? null : _runTest,
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 12),
            CyreneInlineAlert(
              vector: MiuixIcons.extended.byName(_testOk ? 'ok' : 'info')!,
              title: _testOk ? '连接正常' : '连接失败',
              description: _testResult!,
              destructive: !_testOk,
            ),
          ],
          const SizedBox(height: 12),
          CyreneInlineAlert(
            vector: MiuixIcons.extended.byName('info')!,
            description:
                '这里配置的是**你自己的**模型服务：请求由本机直接发往你填的地址，'
                '歌曲信息会随请求发过去，Cyrene 的服务器不参与、也拿不到你的密钥。'
                '密钥在本机加密保存，但密钥派生自 App 内固定口令——它挡的是随手'
                '翻看，不等于拿到设备也解不开。费用按你自己的服务商计费。',
          ),
        ],
      ),
    );
  }

  static String _shorten(String value) {
    if (value.length <= 22) return value;
    return '…${value.substring(value.length - 21)}';
  }

  Future<void> _pickRoute() async {
    final picked = await showCyreneSheet<AiRoute>(
      context: context,
      title: '兼容路由',
      builder: (sheetContext, dismiss) => CyreneMenuGroup(
        children: [
          for (final route in AiRoute.values)
            CyreneMenuRow(
              vector: MiuixIcons.extended.byName('link')!,
              iconBackground: const Color(0xFF3482FF),
              title: route.label,
              subtitle: route == AiRoute.openai
                  ? '大多数第三方中转与自建网关走这套'
                  : 'Claude 官方 API 与 Anthropic 兼容网关',
              value: _settings.route == route ? '当前' : null,
              onTap: () => dismiss(route),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await _settings.setRoute(picked);
  }

  Future<void> _editText({
    required String title,
    required String summary,
    required String initial,
    required String hint,
    required Future<void> Function(String) onSubmit,
    bool obscure = false,
  }) async {
    final value = await showCyreneDialog<String>(
      context: context,
      title: title,
      summary: summary,
      builder: (dialogContext, dismiss) => _TextEditor(
        initial: initial,
        hint: hint,
        obscure: obscure,
        onSubmit: dismiss,
      ),
    );
    if (value == null) return;
    await onSubmit(value);
    if (!mounted) return;
    // 配置一变，上一次的测试结论就作废了，别让它误导人。
    setState(() => _testResult = null);
  }

  Future<void> _runTest() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    String message;
    bool ok;
    try {
      message = await AiClient.instance.testConnection();
      ok = true;
    } on AiException catch (error) {
      message = error.message;
      ok = false;
    } catch (error) {
      message = '$error';
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = ok;
      _testResult = message;
    });
    CyreneToast.show(ok ? 'AI 服务连接正常' : 'AI 服务连接失败');
  }
}

class _TextEditor extends StatefulWidget {
  const _TextEditor({
    required this.initial,
    required this.hint,
    required this.obscure,
    required this.onSubmit,
  });

  final String initial;
  final String hint;
  final bool obscure;
  final void Function([String? value]) onSubmit;

  @override
  State<_TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<_TextEditor> {
  late final TextEditingController _input = TextEditingController(
    text: widget.initial,
  );

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
          label: widget.hint,
          useLabelAsPlaceholder: true,
          singleLine: true,
          autofocus: true,
          obscureText: widget.obscure,
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
              child: MiuixText('保存', style: theme.textStyles.button),
            ),
          ],
        ),
      ],
    );
  }
}
