import 'package:cyrene_music_reborn/infrastructure/audio/audio_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// libmpv 加载失败曾经会让 `runApp` 永远不执行（iOS/macOS 白屏事故）。
/// 这里锁住降级契约：失败只被记录，绝不向上抛。
void main() {
  setUp(AudioEngine.resetForTesting);

  group('AudioEngine', () {
    test('markUnavailable 记录错误且不抛出', () {
      AudioEngine.markUnavailable(
        Exception('Cannot find Mpv.framework/Mpv'),
        StackTrace.current,
      );

      expect(AudioEngine.isAvailable, isFalse);
      expect(AudioEngine.error, isNotNull);
      expect(
        AudioEngine.errorSummary,
        contains('Cannot find Mpv.framework/Mpv'),
      );
    });

    test('errorSummary 只取首行并截断，长异常不会把 toast 撑爆', () {
      AudioEngine.markUnavailable(
        Exception('${'x' * 400}\n第二行不该出现'),
        StackTrace.current,
      );

      final summary = AudioEngine.errorSummary;
      expect(summary.length, lessThanOrEqualTo(161)); // 160 + 省略号
      expect(summary, endsWith('…'));
      expect(summary, isNot(contains('第二行不该出现')));
    });

    test('ensureInitialized 在 libmpv 缺失的环境下不抛异常', () {
      // 测试环境没有 libmpv，这一步必定走失败分支——正是要验证的路径：
      // 它必须安静地返回，而不是把异常抛给 _bootstrap。
      expect(AudioEngine.ensureInitialized, returnsNormally);
      expect(AudioEngine.isAvailable, isFalse);
    });

    test('ensureInitialized 幂等，第二次调用不会覆盖已记录的失败', () {
      AudioEngine.markUnavailable(Exception('首个错误'), StackTrace.current);
      AudioEngine.ensureInitialized();

      expect(AudioEngine.isAvailable, isFalse);
      expect(AudioEngine.errorSummary, contains('首个错误'));
    });
  });
}
