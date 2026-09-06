import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/models/track.dart';
import '../../domain/together/together_models.dart';
import '../../infrastructure/together/together_client.dart';
import '../auth/account_session_controller.dart';
import '../playback/playback_controller.dart';
import '../stores/together_settings_store.dart';

/// 一起听的会话控制器（单例）。
///
/// 两种角色共用一条 WebSocket：
/// - **房主**：本机播什么就往房间里广播什么（切歌 / 播放暂停 / 拖动 / 心跳）。
/// - **听众**：收到房主的 sync 后，用**自己的音源**播同一首歌并对齐进度——
///   房间里同步的只是「哪首歌、到哪儿了」，音频地址从不外传。
///
/// 与 [PlaybackController] 的耦合都收在这里：外部只需在启动时 [bind] 一次。
class TogetherController extends ChangeNotifier {
  TogetherController._();

  static final TogetherController instance = TogetherController._();

  final TogetherClient _client = TogetherClient();
  final TogetherSettingsStore _settings = TogetherSettingsStore.instance;

  PlaybackController? _playback;
  AccountSessionController? _account;

  StreamSubscription<Map<String, Object?>>? _messages;
  Timer? _heartbeat;
  Timer? _reconnect;

  /// 等 welcome 落地的握手。连上 WebSocket 只说明「socket 通了」，房间号要等
  /// 服务端的 welcome 帧才有——[host] / [join] 要等到这一步再返回，否则调用方
  /// 拿到 true 的瞬间 [roomCode] 还是 null（房间号显示成空白就是这么来的）。
  Completer<bool>? _handshake;

  TogetherRole _role = TogetherRole.none;
  TogetherConnection _connection = TogetherConnection.idle;
  String? _roomCode;
  bool _roomPrivate = false;
  bool _roomAllowGuestControl = false;
  TogetherMember? _self;
  List<TogetherMember> _members = const [];
  final List<TogetherChatMessage> _chat = [];
  TogetherTrack? _roomTrack;
  List<TogetherTrack> _roomQueue = const [];

  /// 进房前本机的播放列表。听众的队列会被房主那份覆盖，退出后要原样还回去，
  /// 不然人走了列表里还留着一屋子别人的歌。房主不会有这个值（没被覆盖过）。
  List<Track>? _queueBeforeJoin;
  String? _errorMessage;

  /// 正在把房主的状态套用到本机播放器——期间不要把这些变化当成用户操作再播回去。
  bool _applyingRemote = false;

  /// 上一次广播出去的队列指纹，用来判断队列有没有真的变过。
  String? _lastSyncedQueueSignature;

  /// 上一次广播出去的播放状态，用来判断「有没有值得再发一次 sync 的变化」。
  String? _lastSyncedTrackKey;
  bool _lastSyncedPlaying = false;
  Duration _lastKnownPosition = Duration.zero;

  /// 断线重连的剩余次数。
  int _reconnectAttempts = 0;

  /// 已经为哪首「跑偏的曲目」要过全量状态，避免重复发 pull。
  String? _pullRequestedFor;

  /// 弹幕/消息最多留这么多条，够铺满屏幕又不至于无限涨。
  static const _chatLimit = 120;

  /// 心跳兼进度校准：房主定期把当前进度报一次，晚进来的人也能对上。
  static const _heartbeatInterval = Duration(seconds: 15);

  /// 听众与房间进度差超过这个值才纠偏，否则频繁 seek 反而听着一顿一顿。
  static const _driftTolerance = Duration(seconds: 3);

  /// 同步出去的队列长度上限，与服务端 `QUEUE_LIMIT` 对齐。几千首的队列全量
  /// 推一遍对谁都不划算，超出的部分听众看不到，但播放本身不受影响。
  static const _queueLimit = 500;

  /// socket 通了但迟迟等不到 welcome：当成连接失败处理，别留一个没有房间号的
  /// 半吊子会话在界面上。
  static const _handshakeTimeout = Duration(seconds: 10);

  TogetherRole get role => _role;
  TogetherConnection get connection => _connection;
  String? get roomCode => _roomCode;
  bool get roomPrivate => _roomPrivate;

  /// 当前房间是否放开了点歌。以服务端那份为准——本地开关只是房主的意愿，
  /// 听众要看的是房间的实际状态。
  bool get roomAllowGuestControl => _roomAllowGuestControl;

  /// 本机现在能不能换房间里正在播的歌。
  bool get canPickTrack =>
      isActive && (isHost || _roomAllowGuestControl);
  bool get isActive => _role != TogetherRole.none;
  bool get isHost => _role == TogetherRole.host;
  TogetherMember? get self => _self;
  List<TogetherMember> get members => _members;
  List<TogetherChatMessage> get chat => List.unmodifiable(_chat);
  TogetherTrack? get roomTrack => _roomTrack;

  /// 房主的播放队列。听众的本地队列会被它覆盖，所以两边看到的列表是同一份。
  List<TogetherTrack> get roomQueue => _roomQueue;
  String? get errorMessage => _errorMessage;
  int get listeners => _members.length;

  /// 绑定播放器与账号（启动时调一次）。
  void bind({
    required PlaybackController playback,
    required AccountSessionController account,
  }) {
    if (_playback == playback && _account == account) return;
    _playback?.removeListener(_onPlaybackChanged);
    _playback?.positionListenable.removeListener(_onPositionChanged);
    _playback = playback;
    _account = account;
    playback.addListener(_onPlaybackChanged);
    playback.positionListenable.addListener(_onPositionChanged);
    _settings.removeListener(_onSettingsChanged);
    _settings.addListener(_onSettingsChanged);
    _client.onDisconnected = _onDisconnected;
    _messages ??= _client.messages.listen(_onMessage);
  }

  /// 房主改了「私有房间」/「允许听众点歌」就把当前房间一并改掉。不重开房间
  /// ——重开会换房间号，已经进来的人还得重新加一次。
  void _onSettingsChanged() {
    if (!isHost || _roomCode == null) return;
    if (_settings.isPrivate != _roomPrivate) {
      _client.send({'t': 'visibility', 'isPrivate': _settings.isPrivate});
    }
    if (_settings.allowGuestControl != _roomAllowGuestControl) {
      _client.send({
        't': 'permissions',
        'allowGuestControl': _settings.allowGuestControl,
      });
    }
  }

  // ───────────────────────── 开房 / 进房 / 离开 ─────────────────────────

  /// 播放开始时的自动开房：只在「开关打开 + 当前没在一起听」时触发。
  Future<void> autoHostIfNeeded() async {
    if (!_settings.enabled || isActive) return;
    if (_connection == TogetherConnection.connecting) return;
    await host();
  }

  /// 主动开房。房间号由服务端生成（6 位，去掉了易混字符）。
  ///
  /// 返回 true 时 [roomCode] 一定已经就位——调用方要么直接显示房间号，要么按
  /// 失败处理，不会拿到「已开房但没有房间号」的中间态。
  Future<bool> host() async {
    if (_connection == TogetherConnection.connecting) return false;
    // 已经是房主且房间号在手：重复调用（开关 + 播放事件可能各来一次）直接复用，
    // 不要再开一个房间把原来的人甩掉。
    if (isHost && _roomCode != null) return true;
    _errorMessage = null;
    _setConnection(TogetherConnection.connecting);
    final handshake = _handshake = Completer<bool>();
    final ok = await _client.connect(
      asHost: true,
      code: _roomCode,
      isPrivate: _settings.isPrivate,
      allowGuestControl: _settings.allowGuestControl,
      token: _account?.token,
    );
    if (!ok) {
      _handshake = null;
      _errorMessage = '无法连接一起听服务，请稍后再试';
      _setConnection(TogetherConnection.idle);
      return false;
    }
    _role = TogetherRole.host;
    return _awaitHandshake(handshake);
  }

  /// 以听众身份加入房间。
  Future<bool> join(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return false;
    _errorMessage = null;
    _setConnection(TogetherConnection.connecting);
    final handshake = _handshake = Completer<bool>();
    final ok = await _client.connect(
      asHost: false,
      code: normalized,
      token: _account?.token,
    );
    if (!ok) {
      _handshake = null;
      _errorMessage = '无法连接一起听服务，请稍后再试';
      _setConnection(TogetherConnection.idle);
      return false;
    }
    _role = TogetherRole.guest;
    _roomCode = normalized;
    return _awaitHandshake(handshake);
  }

  /// 等 welcome（或错误帧）落地。超时按连接失败收尾，免得界面上挂着一个
  /// 没有房间号、也同步不了的空会话。
  Future<bool> _awaitHandshake(Completer<bool> handshake) async {
    try {
      return await handshake.future.timeout(_handshakeTimeout);
    } on TimeoutException {
      _errorMessage = '一起听服务没有响应，请稍后再试';
      await leave(dissolve: false);
      return false;
    } finally {
      if (identical(_handshake, handshake)) _handshake = null;
    }
  }

  /// 握手有结果了就把等待的一方放行（重连路径没有等待者，null 时直接跳过）。
  void _completeHandshake(bool ok) {
    final handshake = _handshake;
    if (handshake == null || handshake.isCompleted) return;
    handshake.complete(ok);
  }

  /// 离开房间（房主离开会一并解散）。
  Future<void> leave({bool dissolve = true}) async {
    _reconnect?.cancel();
    _reconnectAttempts = 0;
    if (isHost && dissolve) _client.send({'t': 'close'});
    await _client.disconnect();
    _resetSession();
    notifyListeners();
  }

  void _resetSession() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _completeHandshake(false);
    // 要赶在 _role 清空之前：还原时 playback 会发一次通知，此时若已是
    // 「没在一起听」，开着总开关的用户会当场被自动开一个新房间。
    _restoreLocalQueue();
    _role = TogetherRole.none;
    _connection = TogetherConnection.idle;
    _roomCode = null;
    _roomPrivate = false;
    _roomAllowGuestControl = false;
    _self = null;
    _members = const [];
    _roomTrack = null;
    _roomQueue = const [];
    _chat.clear();
    _lastSyncedTrackKey = null;
    _lastSyncedQueueSignature = null;
  }

  // ───────────────────────── 收消息 ─────────────────────────

  void _onMessage(Map<String, Object?> message) {
    switch (message['t']) {
      case 'welcome':
        _onWelcome(message);
      case 'members':
        _onMembers(message);
      case 'room':
        // 房间属性变了（目前只有公开/私有），房间号和成员都不动。
        final room = message['room'];
        if (room is Map) {
          _applyRoomSnapshot(Map<String, Object?>.from(room));
          notifyListeners();
        }
      case 'queue':
        _roomQueue = _parseQueue(message['queue']);
        _applyRoomQueue();
        notifyListeners();
      case 'sync':
        _onSync(message);
      case 'chat':
        final raw = message['message'];
        if (raw is Map) {
          _pushChat(
            TogetherChatMessage.fromJson(Map<String, Object?>.from(raw)),
          );
        }
      case 'kicked':
        // 只会发给被踢的本人，服务端随后就关连接。先落 errorMessage 再退，
        // 这样 leave 会把重连计划一并取消，不会自己又挤回去。
        _errorMessage = message['reason']?.toString() ?? '你已被房主移出房间';
        unawaited(leave(dissolve: false));
      case 'host-left':
        _pushChat(TogetherChatMessage.system('房主暂时离开了'));
      case 'closed':
        _pushChat(TogetherChatMessage.system('房主已结束一起听'));
        unawaited(leave(dissolve: false));
      case 'error':
        _errorMessage = message['message']?.toString() ?? '一起听出错了';
        unawaited(leave(dissolve: false));
      case 'pong':
        break;
    }
  }

  void _onWelcome(Map<String, Object?> message) {
    final room = message['room'];
    final self = message['self'];
    if (self is Map) {
      _self = TogetherMember.fromJson(Map<String, Object?>.from(self));
      _role = _self!.isHost ? TogetherRole.host : TogetherRole.guest;
    }
    if (room is Map) {
      _applyRoomSnapshot(Map<String, Object?>.from(room));
    }
    final history = message['chat'];
    if (history is List) {
      _chat
        ..clear()
        ..addAll(
          history.whereType<Map>().map(
            (item) =>
                TogetherChatMessage.fromJson(Map<String, Object?>.from(item)),
          ),
        );
    }
    _reconnectAttempts = 0;
    _setConnection(TogetherConnection.connected);
    _completeHandshake(_roomCode != null);
    if (isHost) {
      // 开房时把当前正在放的歌和整个队列立刻同步出去，别让先进来的人对着
      // 空房间。重连接管原房间时也要重发——服务端那份可能已经被清了。
      _lastSyncedTrackKey = null;
      _lastSyncedQueueSignature = null;
      _sendSync(force: true);
      _sendQueueIfChanged();
      _startHeartbeat();
    } else {
      // 先落队列再套播放状态：playTrack 会基于当前队列推导新队列，
      // 顺序反了的话房主的列表会被本机那份挤掉。
      _applyRoomQueue();
      final room = message['room'];
      if (room is Map) {
        _applyRoomState(Map<String, Object?>.from(room));
      }
    }
    notifyListeners();
  }

  /// 服务端的房间快照（welcome 与 room 帧共用同一份结构）。
  void _applyRoomSnapshot(Map<String, Object?> data) {
    _roomCode = data['code']?.toString();
    _roomPrivate = data['isPrivate'] == true;
    _roomAllowGuestControl = data['allowGuestControl'] == true;
    _members = _parseMembers(data['members']);
    _roomTrack = TogetherTrack.fromJson(data['track']);
    // 只有 welcome 带队列；room 帧（改可见性）不带，别把已有队列清空。
    if (data.containsKey('queue')) _roomQueue = _parseQueue(data['queue']);
  }

  List<TogetherTrack> _parseQueue(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map(TogetherTrack.fromJson)
        .whereType<TogetherTrack>()
        .toList(growable: false);
  }

  void _onMembers(Map<String, Object?> message) {
    _members = _parseMembers(message['members']);
    final joined = message['joined'];
    if (joined is Map) {
      final name = joined['name']?.toString() ?? '听众';
      _pushChat(TogetherChatMessage.system('$name 加入了房间'));
    }
    final kicked = message['kicked'];
    if (kicked is Map) {
      final name = kicked['name']?.toString() ?? '听众';
      _pushChat(TogetherChatMessage.system('$name 被房主移出了房间'));
    }
    notifyListeners();
  }

  List<TogetherMember> _parseMembers(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => TogetherMember.fromJson(Map<String, Object?>.from(item)))
        .toList(growable: false);
  }

  void _onSync(Map<String, Object?> message) {
    _roomTrack = TogetherTrack.fromJson(message['track']);
    // `by` 表示这帧是别人点歌带出来的。房主平时不跟任何人走（自己就是源头，
    // 服务端也不会把他自己的 sync 回给他），但听众点的歌房主要跟着换。
    final by = message['by'];
    final drivenByOther =
        by is Map && by['id']?.toString() != _self?.id;
    if (isHost && !drivenByOther) {
      notifyListeners();
      return;
    }
    _applyRoomState(message);
    notifyListeners();
  }

  /// 把房间状态套到本机播放器上（听众；房主只在听众点歌时走这里）。
  Future<void> _applyRoomState(Map<String, Object?> state) async {
    final playback = _playback;
    if (playback == null) return;
    final track = TogetherTrack.fromJson(state['track']);
    if (track == null) return;
    final positionMs = (state['positionMs'] as num?)?.toInt() ?? 0;
    final isPlaying = state['isPlaying'] == true;
    final target = Duration(milliseconds: positionMs.clamp(0, 1 << 31));

    final current = playback.state.currentTrack;
    _applyingRemote = true;
    try {
      if (current == null || current.key != track.key) {
        // 换歌：用听众自己的音源解析同一首歌，从房间进度接着播。
        await playback.playTrack(track.toTrack(), startAt: target);
        if (!isPlaying) await playback.togglePlay();
        return;
      }
      // 同一首：只做偏差纠正，差得不多就别 seek，否则听感一顿一顿。
      final drift = playback.state.position - target;
      if (drift.abs() > _driftTolerance) {
        await playback.seek(target);
      }
      if (playback.state.isPlaying != isPlaying) {
        await playback.togglePlay();
      }
    } catch (error) {
      debugPrint('[Together] 同步播放失败: $error');
    } finally {
      _applyingRemote = false;
      if (isHost) {
        // 房主跟着听众点的歌换过来了，记下这份状态，免得紧接着的播放通知
        // 又把同一首原样广播一遍。
        _lastSyncedTrackKey = playback.state.currentTrack?.key;
        _lastSyncedPlaying = playback.state.isPlaying;
      }
    }
  }

  /// 把房间队列套到本机播放列表上（仅听众）。
  ///
  /// 只换列表、不碰当前播放——当前播什么由 sync 决定，两件事分开做，
  /// 免得每次队列变动都把正在放的歌打断。
  void _applyRoomQueue() {
    final playback = _playback;
    if (playback == null || isHost) return;
    final tracks = _roomQueue
        .map((track) => track.toTrack())
        .toList(growable: false);
    // 第一次被覆盖前先把本机那份收好（重连时不会重复采样，此时里面已经是
    // 房主的队列了）。
    _queueBeforeJoin ??= playback.state.queue;
    _applyingRemote = true;
    try {
      playback.setQueue(tracks);
    } finally {
      _applyingRemote = false;
    }
  }

  /// 退出房间后把听众自己的播放列表还回去。
  ///
  /// 只换列表，不动正在放的那首——它已经在响了，跟着一起切反而更突兀；
  /// 想换歌用户自己点就是了。
  void _restoreLocalQueue() {
    final playback = _playback;
    final previous = _queueBeforeJoin;
    _queueBeforeJoin = null;
    if (playback == null || previous == null) return;
    _applyingRemote = true;
    try {
      playback.setQueue(previous);
    } finally {
      _applyingRemote = false;
    }
  }

  // ───────────────────────── 房主广播 ─────────────────────────

  void _onPlaybackChanged() {
    final playback = _playback;
    if (playback == null) return;
    if (!isActive) {
      // 开关开着且真的播起来了 → 自动开一个房间（房间号由服务端生成）。
      if (_settings.enabled && playback.state.currentTrack != null) {
        unawaited(autoHostIfNeeded());
      }
      return;
    }
    if (_applyingRemote) return;
    if (!isHost) {
      _resyncGuestIfDiverged();
      return;
    }
    final track = playback.state.currentTrack;
    final key = track?.key;
    if (key != _lastSyncedTrackKey || playback.state.isPlaying != _lastSyncedPlaying) {
      _sendSync();
    }
    _sendQueueIfChanged();
  }

  /// 队列变了就整份重发。单独一帧而不是塞进 sync：sync 每次播放/暂停/拖动都
  /// 发，队列却可能几百首，绑在一起等于每次操作都重传整个列表。
  void _sendQueueIfChanged() {
    final playback = _playback;
    if (playback == null || !isHost) return;
    final queue = playback.state.queue;
    final capped = queue.length > _queueLimit
        ? queue.sublist(0, _queueLimit)
        : queue;
    final signature = capped.map((track) => track.key).join('|');
    if (signature == _lastSyncedQueueSignature) return;
    _lastSyncedQueueSignature = signature;
    _client.send({
      't': 'queue',
      'queue': capped
          .map((track) => TogetherTrack.fromTrack(track).toJson())
          .toList(growable: false),
    });
  }

  /// 听众本地跑偏了（一曲放完自动续播下一首、或自己点了切歌）就立刻要一次
  /// 全量状态，不用干等房主 15 秒一次的心跳把人拉回来。
  void _resyncGuestIfDiverged() {
    final playback = _playback;
    final expected = _roomTrack;
    if (playback == null || expected == null) return;
    final current = playback.state.currentTrack;
    if (current == null || current.key == expected.key) {
      _pullRequestedFor = null;
      return;
    }
    // 同一次跑偏只要一次，否则每帧状态变化都会发一遍。
    if (_pullRequestedFor == current.key) return;
    _pullRequestedFor = current.key;
    _client.send({'t': 'pull'});
  }

  void _onPositionChanged() {
    final playback = _playback;
    if (playback == null) return;
    final position = playback.positionListenable.value;
    final delta = position - _lastKnownPosition;
    _lastKnownPosition = position;
    // 正常播放每个 tick 只走几百毫秒；跳变这么大只可能是用户拖了进度条。
    if (isHost && !_applyingRemote && delta.abs() > const Duration(seconds: 2)) {
      _sendSync();
    }
  }

  void _sendSync({bool force = false}) {
    final playback = _playback;
    if (playback == null || !isHost) return;
    final track = playback.state.currentTrack;
    if (track == null && !force) return;
    _lastSyncedTrackKey = track?.key;
    _lastSyncedPlaying = playback.state.isPlaying;
    _client.send({
      't': 'sync',
      'track': track == null ? null : TogetherTrack.fromTrack(track).toJson(),
      'positionMs': playback.state.position.inMilliseconds,
      'isPlaying': playback.state.isPlaying,
    });
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) {
      if (!isHost) return;
      _sendSync(force: true);
    });
  }

  // ───────────────────────── 点歌 ─────────────────────────

  /// 听众点歌：请求把房间切到 [track]（房主放开了点歌才认）。
  ///
  /// 不直接动本机播放——等服务端把 sync 广播回来，房主和所有听众一起换，
  /// 免得点歌的人先跳一步、别人慢半拍。房主换歌走普通播放路径，不经这里。
  bool requestPlay(Track track) {
    if (!isActive || isHost || !_roomAllowGuestControl) return false;
    _client.send({
      't': 'play',
      'track': TogetherTrack.fromTrack(track).toJson(),
    });
    return true;
  }

  // ───────────────────────── 成员管理 ─────────────────────────

  /// 把某位听众移出房间（仅房主）。踢自己不算数——房主要走 [leave]。
  ///
  /// 服务端会给对方发一帧 `kicked` 再断开，并把新的成员表广播给房里所有人，
  /// 所以这里不本地改 [members]，等服务端回来的那份为准。
  void kick(String memberId) {
    if (!isHost || memberId.isEmpty || memberId == _self?.id) return;
    _client.send({'t': 'kick', 'memberId': memberId});
  }

  // ───────────────────────── 弹幕 ─────────────────────────

  void sendChat(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !isActive) return;
    _client.send({'t': 'chat', 'text': trimmed});
  }

  void _pushChat(TogetherChatMessage message) {
    _chat.add(message);
    if (_chat.length > _chatLimit) {
      _chat.removeRange(0, _chat.length - _chatLimit);
    }
    notifyListeners();
  }

  // ───────────────────────── 连接维护 ─────────────────────────

  void _onDisconnected() {
    if (_role == TogetherRole.none) return;
    _setConnection(TogetherConnection.closed);
    // 切后台、换 Wi-Fi 都会断一下：带着原房间号退避重连，房主还能接管回原房间
    // （服务端留了宽限期），听众也不用重新找房。
    if (_reconnectAttempts >= 3) {
      _pushChat(TogetherChatMessage.system('一起听已断开'));
      unawaited(leave(dissolve: false));
      return;
    }
    _reconnectAttempts += 1;
    _reconnect?.cancel();
    _reconnect = Timer(Duration(seconds: 2 * _reconnectAttempts), () async {
      if (_role == TogetherRole.none) return;
      final wasHost = isHost;
      final code = _roomCode;
      final ok = await _client.connect(
        asHost: wasHost,
        code: code,
        isPrivate: _settings.isPrivate,
        allowGuestControl: _settings.allowGuestControl,
        token: _account?.token,
      );
      if (!ok) _onDisconnected();
    });
  }

  void _setConnection(TogetherConnection value) {
    if (_connection == value) return;
    _connection = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _reconnect?.cancel();
    _playback?.removeListener(_onPlaybackChanged);
    _playback?.positionListenable.removeListener(_onPositionChanged);
    _settings.removeListener(_onSettingsChanged);
    unawaited(_messages?.cancel());
    unawaited(_client.dispose());
    super.dispose();
  }
}

/// 便于 UI 直接拿到「当前该显示的曲目」——听众看房间的，房主看自己的。
extension TogetherTrackView on TogetherController {
  Track? get displayTrack => roomTrack?.toTrack();
}
