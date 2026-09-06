import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/url_service.dart';

/// 一起听的 WebSocket 通道（`/together/ws`）。
///
/// 只管连接与收发 JSON，房间语义全在 [TogetherController] 里。用 dart:io 的
/// [WebSocket] 而不是 web_socket_channel：不必新增依赖，而且能带 Authorization
/// 头（服务端也认 query 里的 token，两条路都留着）。
class TogetherClient {
  TogetherClient({UrlService? urls}) : _urls = urls ?? UrlService.instance;

  final UrlService _urls;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  final _messages = StreamController<Map<String, Object?>>.broadcast();

  /// 服务端推来的消息（已解析成 Map，带 `t` 字段区分类型）。
  Stream<Map<String, Object?>> get messages => _messages.stream;

  bool get isConnected => _socket != null;

  /// 连接断开时回调（正常关闭与异常断开都会触发一次）。
  void Function()? onDisconnected;

  Uri _endpoint({
    required bool asHost,
    String? code,
    bool isPrivate = false,
    bool allowGuestControl = false,
    String? token,
  }) {
    final base = Uri.parse(_urls.baseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}/together/ws',
      queryParameters: {
        'role': asHost ? 'host' : 'guest',
        if (code != null && code.isNotEmpty) 'code': code,
        if (asHost) 'private': isPrivate ? '1' : '0',
        if (asHost) 'allow': allowGuestControl ? '1' : '0',
        // 浏览器端没法给 WebSocket 加头，服务端因此同时认 query token；
        // 这里两个都给，桌面/移动走头，服务端优先用头。
        if (token != null && token.isNotEmpty) 'token': token,
      },
    );
  }

  /// 建立连接。成功返回 true；失败已在内部记日志，调用方按 false 处理即可。
  Future<bool> connect({
    required bool asHost,
    String? code,
    bool isPrivate = false,
    bool allowGuestControl = false,
    String? token,
  }) async {
    await disconnect();
    final uri = _endpoint(
      asHost: asHost,
      code: code,
      isPrivate: isPrivate,
      allowGuestControl: allowGuestControl,
      token: token,
    );
    try {
      final socket = await WebSocket.connect(
        uri.toString(),
        headers: {
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 12));
      _socket = socket;
      _subscription = socket.listen(
        _onData,
        onError: (Object error) {
          debugPrint('[Together] 连接出错: $error');
          _handleClosed();
        },
        onDone: _handleClosed,
        cancelOnError: true,
      );
      return true;
    } catch (error) {
      debugPrint('[Together] 连接失败: $error');
      _socket = null;
      return false;
    }
  }

  void _onData(dynamic data) {
    if (data is! String) return;
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map) {
        _messages.add(Map<String, Object?>.from(decoded));
      }
    } catch (error) {
      debugPrint('[Together] 消息解析失败: $error');
    }
  }

  void _handleClosed() {
    if (_socket == null) return;
    _socket = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    onDisconnected?.call();
  }

  void send(Map<String, Object?> payload) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.add(jsonEncode(payload));
    } catch (error) {
      debugPrint('[Together] 发送失败: $error');
    }
  }

  Future<void> disconnect() async {
    final socket = _socket;
    _socket = null;
    await _subscription?.cancel();
    _subscription = null;
    if (socket != null) {
      try {
        await socket.close(WebSocketStatus.normalClosure);
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    onDisconnected = null;
    await disconnect();
    await _messages.close();
  }
}
