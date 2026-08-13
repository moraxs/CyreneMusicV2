import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/models/account.dart';
import '../../infrastructure/services/account_service.dart';

/// 第三方平台标识。与后端 `/accounts/{platform}/...` 路径一一对应。
enum ThirdPartyPlatform { netease, kugou, qq }

/// 二维码扫码会话。同一时刻只绑一家，故单实例即可。
///
/// `qrImage` 为可直接渲染的二维码内容：
/// - 网易云：后端返回的 `qrimg`（base64 data URL），或为空时由调用方用
///   `qrUrl` 本地生成；
/// - 酷狗：`qrUrl`（由调用方本地生成二维码）；
/// - QQ：后端返回的 `img`（http URL 或 base64 data URL），直接展示。
/// 这里只保留「用于 check 的句柄」与「二维码渲染数据」，渲染细节归 UI 层。
class QrSession {
  const QrSession({
    required this.platform,
    required this.checkKey,
    required this.qrUrl,
    required this.qrImage,
    required this.qrImageIsDataUrl,
    required this.ptqrtoken,
    required this.qrsig,
    required this.status,
    required this.expired,
  });

  final ThirdPartyPlatform platform;

  /// 用于轮询 check 的句柄：网易云=unikey，酷狗=qrcode（QQ 不用此字段）。
  final String checkKey;

  /// 二维码内容 URL（网易云/酷狗用，供本地生成）。
  final String qrUrl;

  /// 直接可渲染的二维码图片数据：网易云 `qrimg`（data URL，可能为空）或
  /// QQ 的 `img`（http URL 或 data URL）。
  final String? qrImage;

  /// `qrImage` 是否是 base64 data URL（true→Image.memory，false→网络图）。
  final bool qrImageIsDataUrl;

  /// QQ 专用：check 时的 ptqrtoken / qrsig。
  final String? ptqrtoken;
  final String? qrsig;

  /// 面向用户的轮询状态文案。
  final String status;

  /// 二维码是否已过期（过期时 UI 显示刷新按钮）。
  final bool expired;

  QrSession copyWith({
    String? status,
    bool? expired,
  }) => QrSession(
    platform: platform,
    checkKey: checkKey,
    qrUrl: qrUrl,
    qrImage: qrImage,
    qrImageIsDataUrl: qrImageIsDataUrl,
    ptqrtoken: ptqrtoken,
    qrsig: qrsig,
    status: status ?? this.status,
    expired: expired ?? this.expired,
    );
}

class ThirdPartyAccountsState {
  const ThirdPartyAccountsState({
    this.loading = false,
    this.bindings,
    this.errorMessage,
    this.qrSession,
    this.captchaSending = false,
    this.captchaCountdown = 0,
    this.binding = false,
  });

  final bool loading;
  final AccountBindings? bindings;
  final String? errorMessage;
  final QrSession? qrSession;

  final bool captchaSending;
  final int captchaCountdown;
  final bool binding;

  ThirdPartyAccountsState copyWith({
    bool? loading,
    AccountBindings? bindings,
    bool clearBindings = false,
    String? errorMessage,
    bool clearError = false,
    QrSession? qrSession,
    bool clearQrSession = false,
    bool? captchaSending,
    int? captchaCountdown,
    bool? binding,
  }) => ThirdPartyAccountsState(
    loading: loading ?? this.loading,
    bindings: clearBindings ? null : bindings ?? this.bindings,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    qrSession: clearQrSession ? null : qrSession ?? this.qrSession,
    captchaSending: captchaSending ?? this.captchaSending,
    captchaCountdown: captchaCountdown ?? this.captchaCountdown,
    binding: binding ?? this.binding,
  );
}

/// 第三方账号绑定状态机（对应 Tauri `AccountBindingManager` + `QRCodeDialog`）。
///
/// 复用 [AccountService] 已封装的全部后端接口，不自己存会话：token 与
/// userId 由页面从 `AccountSessionController` 取后传入。二维码轮询用
/// `_requestId` 自增守卫——切走/刷新/解绑/换平台都会 `++_requestId`，使
/// 在途的 check 结果被丢弃，避免旧会话污染新状态（范式同
/// `AccountSessionController`）。
class ThirdPartyAccountsController extends ChangeNotifier {
  ThirdPartyAccountsController();

  final AccountService _service = AccountService.instance;

  ThirdPartyAccountsState _state = const ThirdPartyAccountsState();
  ThirdPartyAccountsState get state => _state;

  var _requestId = 0;
  bool _disposed = false;
  Timer? _qrTimer;
  Timer? _captchaTimer;

  void _emit(ThirdPartyAccountsState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  // --- 绑定列表 ---

  Future<void> loadBindings(String token) async {
    final requestId = ++_requestId;
    _emit(_state.copyWith(loading: true, clearError: true));
    try {
      final bindings = await _service.getBindings(token);
      if (requestId != _requestId) return;
      _emit(_state.copyWith(
        loading: false,
        bindings: bindings,
        clearError: bindings == null,
        errorMessage: bindings == null ? '获取绑定信息失败' : null,
      ));
    } catch (_) {
      if (requestId != _requestId) return;
      _emit(_state.copyWith(
        loading: false,
        errorMessage: '获取绑定信息失败，请稍后重试',
      ));
    }
  }

  // --- 解绑 ---

  Future<bool> unbind(String token, ThirdPartyPlatform platform) async {
    final requestId = ++_requestId;
    bool ok;
    switch (platform) {
      case ThirdPartyPlatform.netease:
        ok = await _service.unbindNetease(token);
      case ThirdPartyPlatform.kugou:
        ok = await _service.unbindKugou(token);
      case ThirdPartyPlatform.qq:
        ok = await _service.unbindQq(token);
    }
    if (requestId != _requestId) return ok;
    if (ok) {
      await loadBindings(token);
    } else {
      _emit(_state.copyWith(errorMessage: '解绑失败，请稍后重试'));
    }
    return ok;
  }

  // --- 扫码绑定 ---

  /// 发起网易云扫码：拿 key → 拿二维码图 → 启动 3s 轮询。
  Future<void> startNeteaseQr(int userId) async {
    final requestId = ++_requestId;
    _cancelQrTimer();
    _emit(_state.copyWith(
      qrSession: QrSession(
        platform: ThirdPartyPlatform.netease,
        checkKey: '',
        qrUrl: '',
        qrImage: null,
        qrImageIsDataUrl: false,
        ptqrtoken: null,
        qrsig: null,
        status: '正在加载二维码…',
        expired: false,
      ),
    ));
    final key = await _service.getNeteaseQRKey();
    if (requestId != _requestId) return;
    if (key == null || key.isEmpty) {
      if (requestId != _requestId) return;
      _emit(_state.copyWith(
        clearQrSession: true,
        errorMessage: '获取二维码失败，请稍后重试',
      ));
      return;
    }
    final qr = await _service.getNeteaseQRData(key);
    if (requestId != _requestId) return;
    if (qr == null) {
      _emit(_state.copyWith(
        clearQrSession: true,
        errorMessage: '获取二维码失败，请稍后重试',
      ));
      return;
    }
    final qrimg = qr.qrimg;
    _emit(_state.copyWith(
      qrSession: QrSession(
        platform: ThirdPartyPlatform.netease,
        checkKey: key,
        qrUrl: qr.qrUrl,
        // qrimg 非空时直接用后端直出的 base64 data URL；否则 UI 用 qrUrl 本地生成。
        qrImage: (qrimg != null && qrimg.isNotEmpty) ? qrimg : null,
        qrImageIsDataUrl: true,
        ptqrtoken: null,
        qrsig: null,
        status: '请使用网易云音乐 App 扫码',
        expired: false,
      ),
    ));
    _startQrPolling(requestId, ThirdPartyPlatform.netease, userId);
  }

  /// 发起酷狗扫码。
  Future<void> startKugouQr(int userId) async {
    final requestId = ++_requestId;
    _cancelQrTimer();
    _emit(_state.copyWith(
      qrSession: QrSession(
        platform: ThirdPartyPlatform.kugou,
        checkKey: '',
        qrUrl: '',
        qrImage: null,
        qrImageIsDataUrl: false,
        ptqrtoken: null,
        qrsig: null,
        status: '正在加载二维码…',
        expired: false,
      ),
    ));
    final data = await _service.getKugouQRData();
    if (requestId != _requestId) return;
    final qrcode = data?['qrcode']?.toString();
    final qrUrl = data?['qrUrl']?.toString() ?? '';
    if (qrcode == null || qrcode.isEmpty || qrUrl.isEmpty) {
      _emit(_state.copyWith(
        clearQrSession: true,
        errorMessage: '获取二维码失败，请稍后重试',
      ));
      return;
    }
    _emit(_state.copyWith(
      qrSession: QrSession(
        platform: ThirdPartyPlatform.kugou,
        checkKey: qrcode,
        qrUrl: qrUrl,
        qrImage: null,
        qrImageIsDataUrl: false,
        ptqrtoken: null,
        qrsig: null,
        status: '请使用酷狗音乐 App 扫码',
        expired: false,
      ),
    ));
    _startQrPolling(requestId, ThirdPartyPlatform.kugou, userId);
  }

  /// 发起 QQ 扫码。
  Future<void> startQqQr(int userId) async {
    final requestId = ++_requestId;
    _cancelQrTimer();
    _emit(_state.copyWith(
      qrSession: QrSession(
        platform: ThirdPartyPlatform.qq,
        checkKey: '',
        qrUrl: '',
        qrImage: null,
        qrImageIsDataUrl: false,
        ptqrtoken: null,
        qrsig: null,
        status: '正在加载二维码…',
        expired: false,
      ),
    ));
    final data = await _service.getQqQRData();
    if (requestId != _requestId) return;
    final img = data?['img']?.toString();
    final ptqrtoken = data?['ptqrtoken']?.toString();
    final qrsig = data?['qrsig']?.toString();
    if (img == null || img.isEmpty ||
        ptqrtoken == null || ptqrtoken.isEmpty ||
        qrsig == null || qrsig.isEmpty) {
      _emit(_state.copyWith(
        clearQrSession: true,
        errorMessage: '获取二维码失败，请稍后重试',
      ));
      return;
    }
    final isDataUrl = img.startsWith('data:');
    _emit(_state.copyWith(
      qrSession: QrSession(
        platform: ThirdPartyPlatform.qq,
        checkKey: '',
        qrUrl: '',
        qrImage: img,
        qrImageIsDataUrl: isDataUrl,
        ptqrtoken: ptqrtoken,
        qrsig: qrsig,
        status: '请使用 QQ 音乐 App 扫码',
        expired: false,
      ),
    ));
    _startQrPolling(requestId, ThirdPartyPlatform.qq, userId);
  }

  /// 启动 3 秒轮询。`requestId` 为发起本次扫码的序号，每次 check 前后比对，
  /// 不一致则停止（已被新的 start/refresh/unbind 抢占）。
  void _startQrPolling(int requestId, ThirdPartyPlatform platform, int userId) {
    _cancelQrTimer();
    // 首次立即检查一次，再按 3s 周期轮询（与 Tauri 前端一致）。
    _pollOnce(requestId, platform, userId);
    _qrTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (requestId != _requestId || _state.qrSession == null) {
        _cancelQrTimer();
        return;
      }
      _pollOnce(requestId, platform, userId);
    });
  }

  Future<void> _pollOnce(
    int requestId,
    ThirdPartyPlatform platform,
    int userId,
  ) async {
    final session = _state.qrSession;
    if (session == null || session.platform != platform) return;
    final Map<String, Object?> result;
    switch (platform) {
      case ThirdPartyPlatform.netease:
        result = await _service.checkNeteaseQR(session.checkKey, userId);
      case ThirdPartyPlatform.kugou:
        result = await _service.checkKugouQR(session.checkKey, userId);
      case ThirdPartyPlatform.qq:
        result = await _service.checkQqQR(
          session.ptqrtoken ?? '',
          session.qrsig ?? '',
          userId,
        );
    }
    if (requestId != _requestId) return;
    _handleQrResult(requestId, platform, result, userId);
  }

  void _handleQrResult(
    int requestId,
    ThirdPartyPlatform platform,
    Map<String, Object?> result,
    int userId,
  ) {
    final session = _state.qrSession;
    if (session == null) return;
    switch (platform) {
      case ThirdPartyPlatform.netease:
        final code = (result['code'] as num?)?.toInt();
        switch (code) {
          case 801:
            _emit(_state.copyWith(qrSession: session.copyWith(
              status: '请使用网易云音乐 App 扫码', expired: false)));
          case 802:
            _emit(_state.copyWith(qrSession: session.copyWith(
              status: '扫描成功，请在 App 内确认', expired: false)));
          case 803:
            _cancelQrTimer();
            _emit(_state.copyWith(
              qrSession: session.copyWith(
                status: '绑定成功', expired: false),
              errorMessage: null));
            notifyQrSuccess(ThirdPartyPlatform.netease);
          case 800:
            _emit(_state.copyWith(qrSession: session.copyWith(
              status: '二维码已过期，请刷新', expired: true)));
          default:
            // 其它码（如 500 网络错误）保持当前态，等下一轮重试。
            break;
        }
      case ThirdPartyPlatform.kugou:
        // 酷狗外层固定 { code:200, status, ... }。
        final status = (result['status'] as num?)?.toInt();
        switch (status) {
          case 1:
            _emit(_state.copyWith(qrSession: session.copyWith(
              status: '请使用酷狗音乐 App 扫码', expired: false)));
          case 2:
            _emit(_state.copyWith(qrSession: session.copyWith(
              status: '扫描成功，请在 App 内确认', expired: false)));
          case 4:
            _cancelQrTimer();
            _emit(_state.copyWith(qrSession: session.copyWith(
              status: '绑定成功', expired: false)));
            notifyQrSuccess(ThirdPartyPlatform.kugou);
          case 0:
            _emit(_state.copyWith(qrSession: session.copyWith(
              status: '二维码已过期，请刷新', expired: true)));
          default:
            break;
        }
      case ThirdPartyPlatform.qq:
        final code = (result['code'] as num?)?.toInt();
        final data = result['data'];
        final dataMap = data is Map ? Map<String, Object?>.from(data) : null;
        final isOk = dataMap?['isOk'] == true;
        final refresh = dataMap?['refresh'] == true;
        if (code == 200 && isOk) {
          _cancelQrTimer();
          _emit(_state.copyWith(qrSession: session.copyWith(
            status: '绑定成功', expired: false)));
          notifyQrSuccess(ThirdPartyPlatform.qq);
        } else if (refresh) {
          _emit(_state.copyWith(qrSession: session.copyWith(
            status: '二维码已过期，请刷新', expired: true)));
        } else {
          final msg = dataMap?['message']?.toString() ?? '';
          // QQ 中间态：message 含「扫描成功」表示待确认。
          if (msg.contains('扫描成功') || msg.contains('认证')) {
            _emit(_state.copyWith(qrSession: session.copyWith(
              status: '扫描成功，请在 App 内确认', expired: false)));
          } else {
            _emit(_state.copyWith(qrSession: session.copyWith(
              status: '请使用 QQ 音乐 App 扫码', expired: false)));
          }
        }
    }
  }

  /// 绑定成功回调钩子：由页面注入，用于 toast + 刷新列表 + 关弹窗。
  void Function(ThirdPartyPlatform platform)? onQrSuccess;

  void notifyQrSuccess(ThirdPartyPlatform platform) =>
      onQrSuccess?.call(platform);

  /// 刷新当前平台二维码（过期时用）。自增 requestId 使旧轮询作废。
  Future<void> refreshQr(int userId) async {
    final platform = _state.qrSession?.platform;
    if (platform == null) return;
    switch (platform) {
      case ThirdPartyPlatform.netease:
        await startNeteaseQr(userId);
      case ThirdPartyPlatform.kugou:
        await startKugouQr(userId);
      case ThirdPartyPlatform.qq:
        await startQqQr(userId);
    }
  }

  /// 取消当前扫码会话（sheet 关闭 / 页面退出时调）。停轮询并清会话。
  void cancelQr() {
    ++_requestId;
    _cancelQrTimer();
    if (_state.qrSession != null) {
      _emit(_state.copyWith(clearQrSession: true));
    }
  }

  void _cancelQrTimer() {
    _qrTimer?.cancel();
    _qrTimer = null;
  }

  // --- 网易云手机验证码登录 ---

  Future<void> sendCaptcha(String phone, {String ctcode = '86'}) async {
    if (_state.captchaSending || _state.captchaCountdown > 0) return;
    _emit(_state.copyWith(captchaSending: true, clearError: true));
    final result = await _service.sendNeteaseCaptcha(phone, ctcode: ctcode);
    if (_disposed) return;
    if (result.code == 200) {
      _startCaptchaCountdown();
      _emit(_state.copyWith(captchaSending: false, errorMessage: null));
    } else {
      _emit(_state.copyWith(
        captchaSending: false,
        errorMessage: result.message ?? '验证码发送失败',
      ));
    }
  }

  /// 手机号验证码登录并绑定。成功返回 true。
  Future<bool> loginByCellphone(
    String token,
    String phone,
    String captcha, {
    String ctcode = '86',
  }) async {
    _emit(_state.copyWith(binding: true, clearError: true));
    final result = await _service.loginNeteaseByCellphone(
      token,
      phone,
      captcha,
      ctcode: ctcode,
    );
    if (_disposed) return false;
    _emit(_state.copyWith(binding: false));
    if (result.code == 200) {
      await loadBindings(token);
      return true;
    }
    _emit(_state.copyWith(
      errorMessage: result.message ?? '绑定失败，请检查验证码',
    ));
    return false;
  }

  void _startCaptchaCountdown() {
    _captchaTimer?.cancel();
    _emit(_state.copyWith(captchaCountdown: 60));
    _captchaTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      final left = _state.captchaCountdown - 1;
      if (left > 0) {
        _emit(_state.copyWith(captchaCountdown: left));
      } else {
        _emit(_state.copyWith(captchaCountdown: 0));
        timer.cancel();
      }
    });
  }

  void clearError() {
    if (_state.errorMessage == null) return;
    _emit(_state.copyWith(clearError: true));
  }

  @override
  void dispose() {
    _disposed = true;
    ++_requestId;
    _cancelQrTimer();
    _captchaTimer?.cancel();
    _captchaTimer = null;
    super.dispose();
  }
}
