import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/audio_sources/audio_source_preferences_controller.dart';
import '../../application/auth/account_session_controller.dart';
import '../../domain/models/audio_source_config.dart';
import '../../domain/models/cyrene_config.dart';
import 'listening_card_service.dart';

/// Cyrene Premium 自动补发同步器。
///
/// 实现「自动下发」语义：登录恢复后静默拉取 `/card/status`，若持卡且本机
/// official-omniparse 源 apiKey 为空（或距上次拉取超过 24h），则静默
/// `fetchCardConfig` + `updateOmniParse` 覆盖默认音源。
///
/// 这样「A 设备付款、B 设备登录即自动获得配置」成立；同时服务端轮换 apiKey
/// 后，客户端最多 24h 内自动更新。所有失败静默吞掉，不打扰用户。
///
/// 24h 节流键 `card_config_fetched_at` 存 SharedPreferences。
class ListeningCardSync {
  ListeningCardSync({
    required this.account,
    required this.audioSources,
  });

  final AccountSessionController account;
  final AudioSourcePreferencesController audioSources;

  static const _officialOmniParseId = 'official-omniparse';
  static const _fetchedAtKey = 'card_config_fetched_at';
  static const _throttle = Duration(hours: 24);

  bool _disposed = false;
  bool _running = false;
  bool _lastLoggedIn = false;

  /// 启动：监听登录态变化，登录成功后触发一次静默补发。
  void start() {
    account.addListener(_onAccountChanged);
    _lastLoggedIn = account.state.isLoggedIn;
    if (_lastLoggedIn) {
      _sync();
    }
  }

  void _onAccountChanged() {
    if (_disposed) return;
    final loggedIn = account.state.isLoggedIn;
    // 仅在「从未登录→已登录」跃迁时触发，避免登录态每次抖动都拉取。
    if (loggedIn && !_lastLoggedIn) {
      _sync();
    }
    _lastLoggedIn = loggedIn;
  }

  Future<void> _sync() async {
    if (_disposed || _running) return;
    final token = account.token;
    if (token == null || token.isEmpty) return;

    _running = true;
    try {
      // 持卡状态查询是轻量 GET，且是 hasListeningCard 的前端权威来源
      // （/card/status 含后端 lazy backfill）。必须放在节流闸门之前——否则
      // 已持卡且本机已有 apiKey 的用户会被 24h 节流早退跳过，导致个人中心
      // /我的页永远显示「普通用户」（hasListeningCard 恒为 false）。
      final status = await ListeningCardService.instance.getCardStatus(token);
      if (_disposed || status == null) return;

      // 始终回写持卡状态到本机 User 并落盘，使个人中心/我的页的徽章与
      // 「赞助状态」行反映 Cyrene Premium，无需退出重登。覆盖换机/旧版本
      // 购买等本机快照仍为 false 的场景。
      if (status.hasCard) {
        await account.patchUser(
          (u) => u.copyWith(
            hasListeningCard: true,
            listeningCardSince: status.grantedAt ?? u.listeningCardSince,
          ),
        );
      }

      if (_disposed || !status.hasCard) return;

      // 节流仅作用于昂贵的 fetchCardConfig + _applyConfig（下发并落库音源
      // apiKey）。本机已配 apiKey 且 24h 内拉过则跳过，仅服务端轮换场景
      // 需每日重拉。
      final sources = audioSources.state.sources;
      final localHasApiKey = _localHasApiKey(sources);
      final prefs = await SharedPreferences.getInstance();
      final fetchedAt = prefs.getString(_fetchedAtKey);
      if (localHasApiKey && fetchedAt != null) {
        final last = DateTime.tryParse(fetchedAt);
        if (last != null && DateTime.now().difference(last) < _throttle) {
          return;
        }
      }

      final config = await ListeningCardService.instance.fetchCardConfig(token);
      if (_disposed || config == null) return;

      await _applyConfig(config);
      await prefs.setString(_fetchedAtKey, DateTime.now().toIso8601String());
    } catch (e) {
      // 静默吞掉：不打扰用户，下次启动/登录再试。
      debugPrint('[ListeningCardSync] 静默补发失败: $e');
    } finally {
      _running = false;
    }
  }

  bool _localHasApiKey(List<AudioSourceConfig> sources) {
    for (final s in sources) {
      if (s.id == _officialOmniParseId) {
        return s.apiKey.isNotEmpty;
      }
    }
    return false;
  }

  /// 覆盖 official-omniparse；不存在则新增。复用 controller 落库。
  ///
  /// 新增时显式传入稳定 id `official-omniparse`，使后续下发、状态查询、
  /// _hasLocalApiKey 判定都能按此 id 命中，且不会因重复下发产生多个官方源。
  Future<void> _applyConfig(CyreneConfig config) async {
    final sources = audioSources.state.sources;
    AudioSourceConfig? existing;
    for (final s in sources) {
      if (s.id == _officialOmniParseId) {
        existing = s;
        break;
      }
    }
    if (existing != null) {
      await audioSources.updateOmniParse(
        id: _officialOmniParseId,
        name: config.name.isEmpty ? existing.name : config.name,
        url: config.url.isEmpty ? existing.url : config.url,
        apiKey: config.apiKey,
      );
    } else {
      await audioSources.addOmniParse(
        id: _officialOmniParseId,
        name: config.name.isEmpty ? 'OmniParse' : config.name,
        url: config.url,
        apiKey: config.apiKey,
      );
    }
  }

  void dispose() {
    _disposed = true;
    account.removeListener(_onAccountChanged);
  }
}
