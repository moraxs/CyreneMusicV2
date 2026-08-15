import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../infrastructure/services/account_pool_service.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';

/// 号池管理页（开发者工具）。
///
/// 展示后端公共账号池（酷狗/网易云/QQ）的状态，并支持对酷狗号池发起扫码登录，
/// 成功后后端自动把 token 写入对应 cookie 文件，供播放链路作为公共账号使用。
class AccountPoolPage extends StatefulWidget {
  const AccountPoolPage({super.key, required this.token});

  /// WebUI 管理会话 token（进入页面时已通过密码校验取得）。
  final String token;

  @override
  State<AccountPoolPage> createState() => _AccountPoolPageState();
}

class _AccountPoolPageState extends State<AccountPoolPage> {
  static const _iconBlue = Color(0xFF3482FF);
  static const _iconGreen = Color(0xFF3CC756);
  static const _iconOrange = Color(0xFFFF9F0A);

  final _service = AccountPoolService.instance;

  bool _loading = true;
  String? _error;
  List<AccountPoolEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _service.getPool(widget.token);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openQrLogin(AccountPoolEntry entry) async {
    await showCyreneSheet<void>(
      context: context,
      title: '${entry.platformName}扫码登录',
      insideMargin: 18,
      builder: (sheetContext, dismiss) => _PoolQrLoginSheet(
        service: _service,
        token: widget.token,
        platformId: entry.id,
        platformName: entry.platformName,
        onSuccess: () {
          _load();
          dismiss();
        },
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return CyrenePage(
      title: '号池管理',
      bodyBuilder: (context, topPadding) {
        if (_loading) {
          return const Center(
            child: MiuixCircularProgressIndicator(size: 24, strokeWidth: 2),
          );
        }
        if (_error != null) {
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: topPadding + const EdgeInsets.fromLTRB(12, 4, 12, 40),
            children: [
              CyreneInlineAlert(
                vector: MiuixIcons.extended.byName('info')!,
                title: '加载失败',
                description: _error!,
                destructive: true,
              ),
              const SizedBox(height: 12),
              MiuixButton(
                onPressed: _load,
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                child: MiuixText('重试', style: MiuixTheme.of(context).textStyles.button),
              ),
            ],
          );
        }
        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: topPadding + const EdgeInsets.fromLTRB(12, 4, 12, 40),
          children: [
            const MiuixSmallTitle(
              '号池账号',
              insideMargin: EdgeInsets.fromLTRB(16, 8, 16, 8),
            ),
            if (_entries.isEmpty)
              CyreneEmptyState(
                vector: MiuixIcons.extended.byName('contacts')!,
                title: '暂无号池账号',
                description: '后端未返回任何号池账号。',
              )
            else
              CyreneMenuGroup(
                children: _entries.map(_accountRow).toList(growable: false),
              ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MiuixIcon(
                    vector: MiuixIcons.extended.byName('info')!,
                    size: 15,
                    tint: MiuixTheme.of(context).colors.onSurfaceVariantSummary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '号池账号是后端播放链路的公共登录态。扫码成功后凭证保存在服务器，'
                      '不会下发到本机。',
                      style: MiuixTheme.of(context).textStyles.body2.copyWith(
                        color: MiuixTheme.of(context).colors.onSurfaceVariantSummary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _accountRow(AccountPoolEntry entry) {
    final theme = MiuixTheme.of(context);
    return CyreneMenuRow(
      vector: _platformVector(entry.id),
      iconBackground: _platformColor(entry.id),
      title: entry.platformName,
      subtitle: _detailText(entry),
      value: _statusLabel(entry.status),
      trailing: entry.isKugou
          ? MiuixButton(
              onPressed: () => _openQrLogin(entry),
              colors: MiuixButtonDefaults.buttonColorsPrimary(context),
              child: MiuixText(
                '扫码登录',
                style: theme.textStyles.button.copyWith(fontSize: 12),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  String _statusLabel(String status) => switch (status) {
    'valid' => '有效',
    'invalid' => '无效',
    _ => '未配置',
  };

  String _detailText(AccountPoolEntry entry) {
    if (entry.status == 'empty') return '尚未配置公共账号';
    switch (entry.id) {
      case 'kugou':
        final uid = entry.detail['userid']?.toString() ?? '';
        final name = entry.detail['username']?.toString() ?? '';
        if (name.isNotEmpty && uid.isNotEmpty) return '$name（UID $uid）';
        if (name.isNotEmpty) return name;
        if (uid.isNotEmpty) return 'UID $uid';
      case 'netease':
        final nick = entry.detail['nickname']?.toString() ?? '';
        if (nick.isNotEmpty) return nick;
    }
    return '已配置';
  }

  Color _platformColor(String id) => switch (id) {
    'netease' => _iconOrange,
    'qq' => _iconBlue,
    'kugou' => _iconGreen,
    _ => _iconBlue,
  };

  MiuixVectorIcon _platformVector(String id) {
    final icon = switch (id) {
      'netease' => 'music',
      'qq' => 'contactsCircle',
      'kugou' => 'tune',
      _ => 'contacts',
    };
    return MiuixIcons.extended.byName(icon)!;
  }
}

// ---------------------------------------------------------------------------
// 号池扫码登录 sheet
// ---------------------------------------------------------------------------

class _PoolQrLoginSheet extends StatefulWidget {
  const _PoolQrLoginSheet({
    required this.service,
    required this.token,
    required this.platformId,
    required this.platformName,
    required this.onSuccess,
  });

  final AccountPoolService service;
  final String token;
  final String platformId;
  final String platformName;
  final VoidCallback onSuccess;

  @override
  State<_PoolQrLoginSheet> createState() => _PoolQrLoginSheetState();
}

class _PoolQrLoginSheetState extends State<_PoolQrLoginSheet> {
  PoolQrKey? _key;
  Timer? _timer;
  bool _loading = true;
  bool _expired = false;
  String _statusText = '正在获取二维码…';

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _timer?.cancel();
    setState(() {
      _loading = true;
      _expired = false;
      _statusText = '正在获取二维码…';
    });
    try {
      final key = await widget.service.startQr(widget.token, widget.platformId);
      if (!mounted) return;
      if (key == null || key.qrUrl.isEmpty) {
        setState(() {
          _loading = false;
          _expired = true;
          _statusText = '获取二维码失败';
        });
        return;
      }
      setState(() {
        _key = key;
        _loading = false;
        _statusText = '请使用${widget.platformName} App 扫码';
      });
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _expired = true;
        _statusText = '获取二维码失败：$e';
      });
    }
  }

  Future<void> _poll() async {
    final key = _key;
    if (key == null) return;
    try {
      final result = await widget.service.checkQr(
        widget.token,
        widget.platformId,
        key.qrcode,
      );
      if (!mounted) return;
      if (result.success) {
        _timer?.cancel();
        setState(() => _statusText = '登录成功');
        CyreneToast.show('${widget.platformName}号池账号已更新');
        widget.onSuccess();
        return;
      }
      if (result.expired) {
        _timer?.cancel();
        setState(() {
          _expired = true;
          _statusText = '二维码已过期';
        });
        return;
      }
      setState(() {
        _statusText = switch (result.status) {
          2 => '扫码成功，请在手机上确认',
          1 => '等待扫码…',
          _ => result.message.isNotEmpty ? result.message : '等待扫码…',
        };
      });
    } catch (_) {
      // 忽略单次轮询的网络抖动。
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final key = _key;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 80),
            child: Center(
              child: MiuixCircularProgressIndicator(size: 24, strokeWidth: 2),
            ),
          )
        else if (key != null && key.qrUrl.isNotEmpty)
          _QrBox(url: key.qrUrl)
        else
          const SizedBox(
            height: 200,
            child: Center(child: MiuixText('无法获取二维码')),
          ),
        const SizedBox(height: 18),
        Text(
          _statusText,
          textAlign: TextAlign.center,
          style: theme.textStyles.body2.copyWith(
            color: _expired ? colors.error : colors.onSurfaceVariantSummary,
          ),
        ),
        if (_expired) ...[
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: MiuixButton(
              onPressed: _start,
              colors: MiuixButtonDefaults.buttonColorsPrimary(context),
              child: MiuixText('刷新二维码', style: theme.textStyles.button),
            ),
          ),
        ],
      ],
    );
  }
}

/// 二维码渲染框。
class _QrBox extends StatelessWidget {
  const _QrBox({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 220,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: QrImageView(
        data: url,
        version: QrVersions.auto,
        size: 200,
        eyeStyle: const QrEyeStyle(
          color: Colors.black,
          eyeShape: QrEyeShape.square,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          color: Colors.black,
          dataModuleShape: QrDataModuleShape.square,
        ),
        backgroundColor: Colors.white,
        padding: const EdgeInsets.all(8),
      ),
    );
  }
}
