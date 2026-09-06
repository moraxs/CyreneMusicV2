import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music_reborn/application/auth/account_session_controller.dart';
import 'package:cyrene_music_reborn/application/playback/playback_controller.dart';
import 'package:cyrene_music_reborn/application/stores/together_settings_store.dart';
import 'package:cyrene_music_reborn/application/together/together_controller.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_repository.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_session_store.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/domain/models/user.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_player_gateway.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_source_resolver.dart';
import 'package:cyrene_music_reborn/domain/together/together_models.dart';
import 'package:cyrene_music_reborn/infrastructure/core/url_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../playback/playback_controller_test.dart'
    show FakeAudioGateway, FakePlaybackSnapshotStore;

/// 一起听的客户端侧：房主把播放状态广播出去，听众收到后驱动本机播放器。
///
/// 用一个假的 WebSocket 服务端顶替后端（协议本身由 backend/tests 覆盖），
/// 这里只验证 Flutter 侧的收发与播放器联动。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // WebSocket 握手走 HttpClient，测试绑定默认把它 mock 成「一律 400」。
  HttpOverrides.global = null;

  late _FakeTogetherServer server;
  late PlaybackController playback;
  late FakeAudioGateway gateway;
  late AccountSessionController account;

  const track = Track(
    id: '123',
    name: '房主的歌',
    artists: '歌手',
    album: '专辑',
    picUrl: '',
    source: MusicSource.netease,
    duration: Duration(minutes: 3),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = await _FakeTogetherServer.start();
    UrlService.instance
      ..setSourceType(BackendSourceType.custom)
      ..setCustomBaseUrl('http://127.0.0.1:${server.port}');
    gateway = FakeAudioGateway();
    playback = PlaybackController(
      audio: gateway,
      store: FakePlaybackSnapshotStore(),
      sourceResolver: _EchoResolver(),
    );
    account = AccountSessionController(_NoopAuthRepository(), _NoopStore());
    await TogetherSettingsStore.instance.init();
    TogetherController.instance.bind(playback: playback, account: account);
  });

  tearDown(() async {
    await TogetherController.instance.leave(dissolve: false);
    // 偏好是单例，不复位会漏到下一条用例里（init 只跑一次）。
    await TogetherSettingsStore.instance.setEnabled(false);
    await TogetherSettingsStore.instance.setPrivate(false);
    playback.dispose();
    account.dispose();
    await server.close();
  });

  test('开房：连接带上 host 角色与私有标记，欢迎帧落地房间号', () async {
    await TogetherSettingsStore.instance.setPrivate(true);
    server.greeting = {
      't': 'welcome',
      'self': {'id': 'm1', 'name': '我', 'isHost': true},
      'room': {
        'code': 'A7K2M9',
        'isPrivate': true,
        'members': [
          {'id': 'm1', 'name': '我', 'isHost': true},
        ],
      },
      'chat': <Object?>[],
    };
    expect(await TogetherController.instance.host(), isTrue);

    expect(server.lastQuery?['role'], 'host');
    expect(server.lastQuery?['private'], '1');

    final controller = TogetherController.instance;
    // host() 返回 true 的那一刻房间号就得在：调用方拿它去显示/复制，
    // 中间态会显示成空白房间号。
    expect(controller.roomCode, 'A7K2M9');
    expect(controller.isHost, isTrue);
    expect(controller.roomPrivate, isTrue);
    expect(controller.connection, TogetherConnection.connected);
    expect(controller.listeners, 1);
  });

  test('开房：等不到欢迎帧就按失败收尾，不留没有房间号的空会话', () async {
    server.greeting = null; // 服务端只握手不发 welcome
    expect(await TogetherController.instance.host(), isFalse);
    expect(TogetherController.instance.isActive, isFalse);
    expect(TogetherController.instance.roomCode, isNull);
    expect(TogetherController.instance.errorMessage, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('房主播放/切歌/拖动都会广播 sync', () async {
    server.greeting = {
      't': 'welcome',
      'self': {'id': 'm1', 'name': '我', 'isHost': true},
      'room': {'code': 'ABCDEF', 'members': <Object?>[]},
      'chat': <Object?>[],
    };
    expect(await TogetherController.instance.host(), isTrue);
    expect(TogetherController.instance.isHost, isTrue);
    server.received.clear();

    await playback.playTrack(track);
    await _until(() => server.received.any((m) => m['t'] == 'sync'));

    final sync = server.received.lastWhere((m) => m['t'] == 'sync');
    final synced = Map<String, Object?>.from(sync['track']! as Map);
    expect(synced['id'], '123');
    expect(synced['name'], '房主的歌');
    expect(synced['source'], 'netease');

    // 播放态变化也要广播，否则听众那边不会跟着暂停/继续。
    server.received.clear();
    gateway.statuses.add(PlaybackStatus.playing);
    await _until(
      () => server.received.any((m) => m['t'] == 'sync' && m['isPlaying'] == true),
    );

    // 拖动进度：位置跳变超过 2 秒会补发一帧。
    server.received.clear();
    gateway.positions.add(const Duration(seconds: 90));
    await _until(() => server.received.any((m) => m['t'] == 'sync'));
    expect(server.received.last['t'], 'sync');
  });

  test('听众：收到 sync 后用自己的音源播同一首歌并对齐进度', () async {
    server.greeting = {
      't': 'welcome',
      'self': {'id': 'm2', 'name': '听众', 'isHost': false},
      'room': {
        'code': 'ABCDEF',
        'members': <Object?>[],
        'track': {
          'id': '123',
          'name': '房主的歌',
          'artists': '歌手',
          'album': '专辑',
          'picUrl': '',
          'source': 'netease',
          'durationMs': 180000,
        },
        'positionMs': 42000,
        'isPlaying': true,
      },
      'chat': <Object?>[],
    };
    expect(await TogetherController.instance.join('ABCDEF'), isTrue);
    expect(server.lastQuery?['role'], 'guest');
    expect(server.lastQuery?['code'], 'ABCDEF');

    // currentTrack 先落地、seek 在音源解析之后才发生，等到 seek 为止。
    await _until(() => gateway.seeks.isNotEmpty);
    expect(playback.state.currentTrack!.id, '123');
    // 从房间进度接着播，而不是从头开始。
    expect(gateway.seeks.first, const Duration(milliseconds: 42000));
    // 听众绝不能把状态播回去，否则会和房主打架。
    expect(server.received.any((m) => m['t'] == 'sync'), isFalse);
  });

  test('听众：同一首歌只在偏差过大时纠偏', () async {
    server.greeting = _guestWelcome;
    expect(await TogetherController.instance.join('ABCDEF'), isTrue);
    expect(TogetherController.instance.roomCode, 'ABCDEF');

    await playback.playTrack(track);
    gateway.positions.add(const Duration(seconds: 30));
    await _until(() => playback.state.position.inSeconds == 30);
    gateway.seeks.clear();

    // 差 1 秒：忍着，别 seek（否则听感一顿一顿）。
    server.push(_syncFrame(positionMs: 31000));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(gateway.seeks, isEmpty);

    // 差 10 秒：纠偏。
    server.push(_syncFrame(positionMs: 40000));
    await _until(() => gateway.seeks.isNotEmpty);
    expect(gateway.seeks.last, const Duration(milliseconds: 40000));
  });

  test('弹幕：发送走 WebSocket，收到的进本地列表', () async {
    server.greeting = _guestWelcome;
    expect(await TogetherController.instance.join('ABCDEF'), isTrue);

    TogetherController.instance.sendChat('  这首好听  ');
    await _until(() => server.received.any((m) => m['t'] == 'chat'));
    final chat = server.received.lastWhere((m) => m['t'] == 'chat');
    expect(chat['text'], '这首好听'); // 首尾空白会被裁掉

    server.push({
      't': 'chat',
      'message': {
        'id': 'c1',
        'memberId': 'm3',
        'name': '别人',
        'text': '+1',
        'positionMs': 1000,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      },
    });
    await _until(() => TogetherController.instance.chat.isNotEmpty);
    expect(TogetherController.instance.chat.last.text, '+1');
    expect(TogetherController.instance.chat.last.name, '别人');
  });

  test('房主解散房间：听众被踢回未参与状态', () async {
    server.greeting = _guestWelcome;
    expect(await TogetherController.instance.join('ABCDEF'), isTrue);
    expect(TogetherController.instance.isActive, isTrue);

    server.push({'t': 'closed', 'reason': '房主已结束一起听'});
    await _until(() => !TogetherController.instance.isActive);
    expect(TogetherController.instance.roomCode, isNull);
    expect(TogetherController.instance.role, TogetherRole.none);
  });

  test('房间不存在：错误帧落到 errorMessage 且不留在房里', () async {
    // 真实服务端进不去的房间是直接回一帧 error 就关连接，join 要按失败返回，
    // 不能因为「socket 连上了」就报成功。
    server.greeting = {
      't': 'error',
      'code': 'room_not_found',
      'message': '房间不存在或已解散',
    };
    expect(await TogetherController.instance.join('ZZZZZZ'), isFalse);
    expect(TogetherController.instance.errorMessage, '房间不存在或已解散');
    expect(TogetherController.instance.isActive, isFalse);
  });

  test('开关关闭时播放不会自动开房', () async {
    await TogetherSettingsStore.instance.setEnabled(false);
    await playback.playTrack(track);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(TogetherController.instance.isActive, isFalse);
    expect(server.connections, 0);
  });

  test('开关打开时一播歌就自动开房', () async {
    server.greeting = {
      't': 'welcome',
      'self': {'id': 'm1', 'name': '我', 'isHost': true},
      'room': {'code': 'ABCDEF', 'members': <Object?>[]},
      'chat': <Object?>[],
    };
    await TogetherSettingsStore.instance.setEnabled(true);
    await playback.playTrack(track);
    await _until(() => server.connections > 0);
    expect(server.lastQuery?['role'], 'host');
    await _until(() => TogetherController.instance.roomCode == 'ABCDEF');
  });

  test('房主改「私有房间」开关：当前房间即时跟着改，不重开', () async {
    server.greeting = {
      't': 'welcome',
      'self': {'id': 'm1', 'name': '我', 'isHost': true},
      'room': {'code': 'ABCDEF', 'isPrivate': false, 'members': <Object?>[]},
      'chat': <Object?>[],
    };
    expect(await TogetherController.instance.host(), isTrue);
    expect(TogetherController.instance.roomPrivate, isFalse);
    server.received.clear();

    await TogetherSettingsStore.instance.setPrivate(true);
    await _until(() => server.received.any((m) => m['t'] == 'visibility'));
    expect(server.received.last['isPrivate'], isTrue);
    // 改可见性不该重开房间：房间号会变、房里的人得重新加一次。
    expect(server.connections, 1);

    server.push({
      't': 'room',
      'room': {'code': 'ABCDEF', 'isPrivate': true, 'members': <Object?>[]},
    });
    await _until(() => TogetherController.instance.roomPrivate);
    expect(TogetherController.instance.roomCode, 'ABCDEF');
  });

  test('听众不会因为本地开关变化去改房间可见性', () async {
    server.greeting = _guestWelcome;
    expect(await TogetherController.instance.join('ABCDEF'), isTrue);
    server.received.clear();

    await TogetherSettingsStore.instance.setPrivate(true);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(server.received.any((m) => m['t'] == 'visibility'), isFalse);
  });

  test('房主：队列变化会整份广播，重复通知不会重发', () async {
    server.greeting = {
      't': 'welcome',
      'self': {'id': 'm1', 'name': '我', 'isHost': true},
      'room': {'code': 'ABCDEF', 'members': <Object?>[], 'queue': <Object?>[]},
      'chat': <Object?>[],
    };
    expect(await TogetherController.instance.host(), isTrue);
    server.received.clear();

    const second = Track(
      id: '456',
      name: '第二首',
      artists: '歌手',
      album: '专辑',
      picUrl: '',
      source: MusicSource.netease,
    );
    await playback.playTrack(track, queue: const [track, second]);
    await _until(() => server.received.any((m) => m['t'] == 'queue'));
    final queued = server.received.lastWhere((m) => m['t'] == 'queue');
    final ids = (queued['queue']! as List)
        .map((item) => (item as Map)['id'])
        .toList();
    expect(ids, ['123', '456']);

    // 只是播放/暂停不该把整个队列再推一遍。
    server.received.clear();
    gateway.statuses.add(PlaybackStatus.playing);
    await _until(() => server.received.any((m) => m['t'] == 'sync'));
    expect(server.received.any((m) => m['t'] == 'queue'), isFalse);
  });

  test('听众：房间队列覆盖本机播放列表', () async {
    // 本机先有一份自己的队列，进房后应当被房主那份顶掉。
    await playback.playTrack(track, queue: const [track]);
    server.greeting = {
      't': 'welcome',
      'self': {'id': 'm2', 'name': '听众', 'isHost': false},
      'room': {
        'code': 'ABCDEF',
        'members': <Object?>[],
        'queue': [
          {'id': '777', 'name': '房主的第一首', 'source': 'netease'},
          {'id': '888', 'name': '房主的第二首', 'source': 'netease'},
        ],
      },
      'chat': <Object?>[],
    };
    expect(await TogetherController.instance.join('ABCDEF'), isTrue);

    await _until(() => playback.state.queue.length == 2);
    expect(playback.state.queue.map((t) => t.id).toList(), ['777', '888']);
    expect(
      TogetherController.instance.roomQueue.map((t) => t.id).toList(),
      ['777', '888'],
    );

    // 房主中途改队列，听众跟着换，且不会把队列播回去。
    server.received.clear();
    server.push({
      't': 'queue',
      'queue': [
        {'id': '999', 'name': '换了', 'source': 'netease'},
      ],
    });
    await _until(() => playback.state.queue.length == 1);
    expect(playback.state.queue.single.id, '999');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(server.received.any((m) => m['t'] == 'queue'), isFalse);
  });

  test('房主改「允许听众点歌」开关会推给房间', () async {
    server.greeting = {
      't': 'welcome',
      'self': {'id': 'm1', 'name': '我', 'isHost': true},
      'room': {
        'code': 'ABCDEF',
        'members': <Object?>[],
        'allowGuestControl': false,
      },
      'chat': <Object?>[],
    };
    expect(await TogetherController.instance.host(), isTrue);
    expect(TogetherController.instance.roomAllowGuestControl, isFalse);
    server.received.clear();

    await TogetherSettingsStore.instance.setAllowGuestControl(true);
    await _until(() => server.received.any((m) => m['t'] == 'permissions'));
    expect(server.received.last['allowGuestControl'], isTrue);

    server.push({
      't': 'room',
      'room': {
        'code': 'ABCDEF',
        'members': <Object?>[],
        'allowGuestControl': true,
      },
    });
    await _until(() => TogetherController.instance.roomAllowGuestControl);
  });

  test('听众点歌：没放开时不发帧，放开后只发请求不动本机播放', () async {
    server.greeting = _guestWelcome; // 默认没放开点歌
    expect(await TogetherController.instance.join('ABCDEF'), isTrue);
    server.received.clear();

    expect(TogetherController.instance.requestPlay(track), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(server.received.any((m) => m['t'] == 'play'), isFalse);

    server.push({
      't': 'room',
      'room': {
        'code': 'ABCDEF',
        'members': <Object?>[],
        'allowGuestControl': true,
      },
    });
    await _until(() => TogetherController.instance.roomAllowGuestControl);

    expect(TogetherController.instance.requestPlay(track), isTrue);
    await _until(() => server.received.any((m) => m['t'] == 'play'));
    final sent = server.received.lastWhere((m) => m['t'] == 'play');
    expect((sent['track']! as Map)['id'], '123');
    // 点歌不抢跑：等服务端把 sync 广播回来大家一起换。
    expect(playback.state.currentTrack, isNull);
  });

  test('房主：听众点的歌会让房主本机跟着换，并留下系统日志', () async {
    server.greeting = {
      't': 'welcome',
      'self': {'id': 'm1', 'name': '我', 'isHost': true},
      'room': {
        'code': 'ABCDEF',
        'members': <Object?>[],
        'allowGuestControl': true,
      },
      'chat': <Object?>[],
    };
    expect(await TogetherController.instance.host(), isTrue);
    server.received.clear();

    server.push({
      't': 'sync',
      'track': {
        'id': '777',
        'name': '听众点的歌',
        'artists': '歌手',
        'album': '专辑',
        'picUrl': '',
        'source': 'netease',
        'durationMs': 180000,
      },
      'positionMs': 0,
      'isPlaying': true,
      'by': {'id': 'm2', 'name': '路人'},
    });
    await _until(() => playback.state.currentTrack?.id == '777');

    // 跟着换完之后房主可能补一帧真实播放态（播放器起播是异步的），但绝不能
    // 反手把自己原来那首播回去——那就成了房主和听众互相打架。
    await Future<void>.delayed(const Duration(milliseconds: 150));
    for (final sync in server.received.where((m) => m['t'] == 'sync')) {
      final synced = sync['track'];
      if (synced == null) continue; // 开房那帧「还什么都没放」
      expect((synced as Map)['id'], '777');
    }

    server.push({
      't': 'chat',
      'message': {
        'id': 'c9',
        'memberId': 'm2',
        'name': '路人',
        'text': '路人 播放了 听众点的歌',
        'positionMs': 0,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'system': true,
      },
    });
    await _until(() => TogetherController.instance.chat.isNotEmpty);
    expect(TogetherController.instance.chat.last.isSystem, isTrue);
    expect(TogetherController.instance.chat.last.text, contains('播放了'));
  });

  test('房主自己的 sync 回声不会被当成别人点歌', () async {
    server.greeting = {
      't': 'welcome',
      'self': {'id': 'm1', 'name': '我', 'isHost': true},
      'room': {'code': 'ABCDEF', 'members': <Object?>[]},
      'chat': <Object?>[],
    };
    expect(await TogetherController.instance.host(), isTrue);

    // by 是自己 → 不套用（服务端本不会回声，这里是防御）。
    server.push({
      't': 'sync',
      'track': {'id': '777', 'name': '别动我', 'source': 'netease'},
      'positionMs': 0,
      'isPlaying': true,
      'by': {'id': 'm1', 'name': '我'},
    });
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(playback.state.currentTrack, isNull);
  });

  test('听众退出房间：本机队列还原成进房前那份', () async {
    const mine = Track(
      id: 'mine-1',
      name: '我自己的歌',
      artists: '歌手',
      album: '专辑',
      picUrl: '',
      source: MusicSource.netease,
    );
    await playback.playTrack(track, queue: const [track, mine]);
    final before = playback.state.queue.map((t) => t.id).toList();

    server.greeting = {
      't': 'welcome',
      'self': {'id': 'm2', 'name': '听众', 'isHost': false},
      'room': {
        'code': 'ABCDEF',
        'members': <Object?>[],
        'queue': [
          {'id': '777', 'name': '房主的歌', 'source': 'netease'},
        ],
      },
      'chat': <Object?>[],
    };
    expect(await TogetherController.instance.join('ABCDEF'), isTrue);
    await _until(() => playback.state.queue.length == 1);

    await TogetherController.instance.leave();
    await _until(() => playback.state.queue.length == before.length);
    expect(playback.state.queue.map((t) => t.id).toList(), before);
  });

  test('被踢出去也会还原本机队列', () async {
    await playback.playTrack(track, queue: const [track]);
    server.greeting = {
      't': 'welcome',
      'self': {'id': 'm2', 'name': '听众', 'isHost': false},
      'room': {
        'code': 'ABCDEF',
        'members': <Object?>[],
        'queue': [
          {'id': '777', 'name': '房主的歌', 'source': 'netease'},
          {'id': '888', 'name': '房主的另一首', 'source': 'netease'},
        ],
      },
      'chat': <Object?>[],
    };
    expect(await TogetherController.instance.join('ABCDEF'), isTrue);
    await _until(() => playback.state.queue.length == 2);

    server.push({'t': 'kicked', 'memberId': 'm2', 'reason': '房主把你移出了房间'});
    await _until(() => !TogetherController.instance.isActive);
    await _until(() => playback.state.queue.length == 1);
    expect(playback.state.queue.single.id, '123');
  });

  test('房主结束房间不会动自己的队列', () async {
    server.greeting = {
      't': 'welcome',
      'self': {'id': 'm1', 'name': '我', 'isHost': true},
      'room': {'code': 'ABCDEF', 'members': <Object?>[], 'queue': <Object?>[]},
      'chat': <Object?>[],
    };
    expect(await TogetherController.instance.host(), isTrue);
    await playback.playTrack(track, queue: const [track]);
    await _until(() => server.received.any((m) => m['t'] == 'queue'));

    await TogetherController.instance.leave();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(playback.state.queue.map((t) => t.id).toList(), ['123']);
  });

  test('房主踢人：发出 kick 帧，成员表以服务端回来的为准', () async {
    server.greeting = {
      't': 'welcome',
      'self': {'id': 'm1', 'name': '我', 'isHost': true},
      'room': {
        'code': 'ABCDEF',
        'members': [
          {'id': 'm1', 'name': '我', 'isHost': true},
          {'id': 'm2', 'name': '路人', 'avatar': 'https://cdn.test/a.png'},
        ],
      },
      'chat': <Object?>[],
    };
    expect(await TogetherController.instance.host(), isTrue);
    expect(TogetherController.instance.members.length, 2);
    // 头像要原样带过来，成员页直接拿它渲染真实头像。
    expect(TogetherController.instance.members.last.avatar, 'https://cdn.test/a.png');
    server.received.clear();

    TogetherController.instance.kick('m2');
    await _until(() => server.received.any((m) => m['t'] == 'kick'));
    expect(server.received.last['memberId'], 'm2');
    // 还没等到服务端确认，本地成员表不动。
    expect(TogetherController.instance.members.length, 2);

    server.push({
      't': 'members',
      'members': [
        {'id': 'm1', 'name': '我', 'isHost': true},
      ],
      'kicked': {'id': 'm2', 'name': '路人'},
    });
    await _until(() => TogetherController.instance.members.length == 1);
    expect(
      TogetherController.instance.chat.last.text,
      contains('路人'),
    );
  });

  test('房主之外的人调用 kick 不会发出任何东西', () async {
    server.greeting = _guestWelcome;
    expect(await TogetherController.instance.join('ABCDEF'), isTrue);
    server.received.clear();

    TogetherController.instance.kick('m1');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(server.received.any((m) => m['t'] == 'kick'), isFalse);
  });

  test('被房主移出：退出房间并留下提示', () async {
    server.greeting = _guestWelcome;
    expect(await TogetherController.instance.join('ABCDEF'), isTrue);

    server.push({
      't': 'kicked',
      'memberId': 'm2',
      'reason': '房主把你移出了房间',
    });
    await _until(() => !TogetherController.instance.isActive);
    expect(TogetherController.instance.errorMessage, '房主把你移出了房间');
    expect(TogetherController.instance.roomCode, isNull);
    expect(TogetherController.instance.role, TogetherRole.none);
  });

  test('已经在房里时重复 host 不会再开一个房间', () async {
    server.greeting = {
      't': 'welcome',
      'self': {'id': 'm1', 'name': '我', 'isHost': true},
      'room': {'code': 'ABCDEF', 'members': <Object?>[]},
      'chat': <Object?>[],
    };
    expect(await TogetherController.instance.host(), isTrue);
    expect(await TogetherController.instance.host(), isTrue);
    expect(server.connections, 1);
    expect(TogetherController.instance.roomCode, 'ABCDEF');
  });
}

/// 听众侧的标准欢迎帧（房间号 ABCDEF、还没开始播）。
const Map<String, Object?> _guestWelcome = {
  't': 'welcome',
  'self': {'id': 'm2', 'name': '听众', 'isHost': false},
  'room': {'code': 'ABCDEF', 'members': <Object?>[]},
  'chat': <Object?>[],
};

Map<String, Object?> _syncFrame({required int positionMs}) => {
  't': 'sync',
  'track': {
    'id': '123',
    'name': '房主的歌',
    'artists': '歌手',
    'album': '专辑',
    'picUrl': '',
    'source': 'netease',
    'durationMs': 180000,
  },
  'positionMs': positionMs,
  'isPlaying': true,
  'serverTime': DateTime.now().millisecondsSinceEpoch,
};

/// 轮询等待条件成立，超时即失败（比固定 sleep 稳）。
Future<void> _until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('等待条件超时');
}

/// 顶替后端的假 WebSocket 服务端。
class _FakeTogetherServer {
  _FakeTogetherServer(this._server);

  final HttpServer _server;
  final received = <Map<String, Object?>>[];
  final _firstConnection = Completer<void>();
  WebSocket? _socket;
  Map<String, String>? lastQuery;
  int connections = 0;

  /// 连上就主动发的第一帧（真实服务端在 open 里就把 welcome 发出来了）。
  /// 房间不存在时它是一帧 error，客户端据此判定加入失败。
  Map<String, Object?>? greeting;

  int get port => _server.port;
  Future<void> get firstConnection => _firstConnection.future;

  static Future<_FakeTogetherServer> start() async {
    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final server = _FakeTogetherServer(httpServer);
    httpServer.listen((request) async {
      if (request.uri.path != '/together/ws') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      server.lastQuery = request.uri.queryParameters;
      server.connections += 1;
      final socket = await WebSocketTransformer.upgrade(request);
      server._socket = socket;
      final greeting = server.greeting;
      if (greeting != null) socket.add(jsonEncode(greeting));
      if (!server._firstConnection.isCompleted) {
        server._firstConnection.complete();
      }
      socket.listen((data) {
        if (data is! String) return;
        final decoded = jsonDecode(data);
        if (decoded is Map) {
          server.received.add(Map<String, Object?>.from(decoded));
        }
      });
    });
    return server;
  }

  void push(Map<String, Object?> frame) => _socket?.add(jsonEncode(frame));

  Future<void> close() async {
    await _socket?.close();
    await _server.close(force: true);
  }
}

/// 听众侧解析：直接把曲目当成可播放的（真实解析在别处测）。
class _EchoResolver implements AudioSourceResolver {
  @override
  Future<ResolvedAudioSources> resolve(Track track, {Set<String>? exclude}) async =>
      ResolvedAudioSources([
        PlaybackCandidate(
          track: track.copyWith(
            playbackUrl: Uri.parse('https://cdn.test/${track.id}.mp3'),
          ),
          sourceId: 'test',
        ),
      ]);
}

class _NoopAuthRepository implements AuthRepository {
  @override
  Future<AuthResponse> login(String account, String password) async =>
      const AuthResponse(success: false);

  @override
  Future<bool> validateToken(String token) async => false;

  @override
  Future<AuthResponse> register(
    String email,
    String username,
    String password,
    String code,
  ) async => const AuthResponse(success: false);

  @override
  Future<AuthResponse> sendRegisterCode(String email, String username) async =>
      const AuthResponse(success: false);

  @override
  Future<({bool success, bool enabled})> checkRegistrationStatus() async =>
      (success: true, enabled: true);
}

class _NoopStore implements AuthSessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<AuthSession?> read() async => null;

  @override
  Future<void> write(AuthSession value) async {}
}
