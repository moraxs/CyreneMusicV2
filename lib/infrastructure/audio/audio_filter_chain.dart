import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// libmpv `af` 属性的唯一写入方。
///
/// 均衡器与 DSP 音效都要往音频链注入 FFmpeg 滤镜，而 `af` 是「一整串」属性——
/// 谁后写谁就会把对方的滤镜整段冲掉。所以两边都不直接碰 `af`，只向本类登记
/// 自己那一段，由本类按固定顺序拼接后一次性写入。
///
/// 槽位顺序即信号链顺序：音色/均衡在前，动态处理与限幅在后（限幅必须垫底，
/// 否则前级增益会先削顶）。
class AudioFilterChain {
  AudioFilterChain._();

  static final AudioFilterChain instance = AudioFilterChain._();

  /// 均衡器槽位（10 段 `equalizer` 滤镜）。
  static const String equalizerSlot = 'equalizer';

  /// DSP 音效槽位（bass/treble/… 等定制构建才有的滤镜）。
  static const String dspSlot = 'dsp';

  static const List<String> _order = [equalizerSlot, dspSlot];

  Player? _player;
  final Map<String, List<String>> _segments = {};

  /// 上次真正写下去的滤镜串，用于跳过重复写入（滑条拖动会高频触发）。
  String? _lastWritten;

  /// 写入串行化：拖动滑条时若并发下发，libmpv 收到的顺序不保证与调用顺序
  /// 一致，可能停在中间态。同一时刻只允许一次写入，期间来的新状态记为 dirty，
  /// 写完再补一次。
  bool _writing = false;
  bool _dirty = false;

  /// 当前 libmpv 构建拒绝了 DSP 段（缺少这些滤镜）。置位后 DSP 片段不再参与
  /// 拼接，UI 可据此提示用户「本机 libmpv 不支持」。
  final ValueNotifier<bool> dspRejected = ValueNotifier(false);

  /// 当前后端是否支持 `af`（仅 media_kit 的 NativePlayer；preview 下为 false）。
  bool get isAttached => _player?.platform is NativePlayer;

  /// 绑定底层播放器，并把已登记的片段补写下去。
  Future<void> attach(Player player) async {
    _player = player;
    await _flush();
  }

  /// 登记 [slot] 的滤镜片段并立即应用；传空列表即清空该槽位。
  Future<void> setSegments(String slot, List<String> segments) async {
    _segments[slot] = List.of(segments, growable: false);
    await _flush();
  }

  Future<void> _flush() async {
    if (_writing) {
      _dirty = true;
      return;
    }
    final platform = _player?.platform;
    if (platform is! NativePlayer) return;

    _writing = true;
    try {
      // ctx 要等 libmpv 实例建好才有效。
      await platform.waitForPlayerInitialization;
      if (platform.disposed || platform.ctx == nullptr) return;
      do {
        _dirty = false;
        final chain = _compose();
        if (chain == _lastWritten) continue;
        final code = _writeAf(platform, chain);
        if (code >= 0) {
          _lastWritten = chain;
          continue;
        }
        debugPrint(
          '[AudioFilterChain] 写入 af 被 libmpv 拒绝'
          '（${_errorText(platform, code)}）：$chain',
        );
        _fallbackWithoutDsp(platform, code);
      } while (_dirty);
    } finally {
      _writing = false;
    }
  }

  String _compose() => [
    for (final slot in _order)
      if (slot != dspSlot || !dspRejected.value) ...?_segments[slot],
  ].join(',');

  /// 直接走 FFI 而不用 [NativePlayer.setProperty]：后者调用
  /// `mpv_set_property_string` 后把返回码丢掉，也不抛异常——mpv 拒绝滤镜链时
  /// 它悄无声息，我们就无从判断 DSP 段究竟有没有生效。这里要的就是那个返回码。
  int _writeAf(NativePlayer platform, String chain) {
    final name = 'af'.toNativeUtf8();
    final data = chain.toNativeUtf8();
    try {
      return platform.mpv.mpv_set_property_string(
        platform.ctx,
        name.cast(),
        data.cast(),
      );
    } finally {
      calloc.free(name);
      calloc.free(data);
    }
  }

  String _errorText(NativePlayer platform, int code) {
    try {
      return platform.mpv
          .mpv_error_string(code)
          .cast<Utf8>()
          .toDartString();
    } catch (_) {
      return 'mpv error $code';
    }
  }

  /// `af` 是一整串，任何一段不被接受就整串写失败——DSP 滤镜依赖定制 libmpv
  /// 构建，是最可能的元凶，却会把本来没问题的均衡器一起废掉。所以整串失败时
  /// 摘掉 DSP 再试一次：成功即坐实是 DSP 的问题，置位 [dspRejected] 让后续
  /// 拼接直接跳过它（同时给 UI 一个提示的依据），均衡器照常工作。
  void _fallbackWithoutDsp(NativePlayer platform, int code) {
    final dsp = _segments[dspSlot];
    if (dspRejected.value || dsp == null || dsp.isEmpty) return;
    final withoutDsp = [
      for (final slot in _order)
        if (slot != dspSlot) ...?_segments[slot],
    ].join(',');
    if (_writeAf(platform, withoutDsp) < 0) {
      debugPrint('[AudioFilterChain] 退回「仅均衡器」仍失败，均衡器也无法应用');
      return;
    }
    _lastWritten = withoutDsp;
    dspRejected.value = true;
    debugPrint(
      '[AudioFilterChain] 当前 libmpv 构建不接受 DSP 滤镜'
      '（${_errorText(platform, code)}），已停用 DSP 段；均衡器保持可用。',
    );
  }
}
