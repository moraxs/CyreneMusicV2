import 'dart:math' as math;

import 'package:cyrene_music_reborn/infrastructure/audio/dsp_effects_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 这些串会被原样喂给 libmpv 的 `af` 属性，一个非法选项名就会让整条链写入
/// 失败（且失败是静默的，只在 debugPrint 里）。所以在这里把 spec 的自洽性与
/// 编码结果锁住。
void main() {
  group('DspFilterSpec.build', () {
    test('默认参数下每个滤镜都编译成合法形状的 FFmpeg 滤镜串', () {
      for (final spec in DspEffectsService.filters) {
        final built = spec.build(spec.defaults);
        expect(built, startsWith('${spec.id}='));
        // mpv 用 `,` 分隔滤镜、`:` 分隔选项，值里再出现这两个字符就会截断整条链。
        expect(built.contains(','), isFalse, reason: built);
        final args = built.substring(spec.id.length + 1).split(':');
        expect(args, hasLength(spec.fixedArgs.length + spec.params.length));
        for (final arg in args) {
          expect(arg.split('=').length, 2, reason: '$built 中的 $arg');
        }
      }
    });

    test('参数名唯一，且不与固定选项撞名', () {
      for (final spec in DspEffectsService.filters) {
        final keys = spec.params.map((param) => param.key).toList();
        expect(keys.toSet(), hasLength(keys.length), reason: spec.id);
        expect(
          keys.toSet().intersection(spec.fixedArgs.keys.toSet()),
          isEmpty,
          reason: spec.id,
        );
      }
    });

    test('默认值落在各自区间内', () {
      for (final spec in DspEffectsService.filters) {
        for (final param in spec.params) {
          expect(
            param.defaultValue,
            inInclusiveRange(param.min, param.max),
            reason: '${spec.id}.${param.key}',
          );
        }
      }
    });
  });

  group('DspParamSpec.encode', () {
    test('dB 参数换算成线性振幅', () {
      const threshold = DspParamSpec(
        key: 'threshold',
        label: '阈值',
        min: -60,
        max: 0,
        defaultValue: -18,
        unit: 'dB',
        scale: DspParamScale.decibel,
      );
      expect(double.parse(threshold.encode(0)), closeTo(1.0, 1e-6));
      expect(double.parse(threshold.encode(-20)), closeTo(0.1, 1e-6));
      expect(
        double.parse(threshold.encode(-18)),
        closeTo(math.pow(10, -0.9).toDouble(), 1e-6),
      );
    });

    test('oddInteger 永远给出区间内的奇数', () {
      final gausssize = DspEffectsService.specOf(
        'dynaudnorm',
      ).params.firstWhere((param) => param.key == 'gausssize');
      expect(gausssize.scale, DspParamScale.oddInteger);
      for (var value = gausssize.min; value <= gausssize.max; value += 0.5) {
        final encoded = int.parse(gausssize.encode(value));
        expect(encoded.isOdd, isTrue, reason: '$value → $encoded');
        expect(
          encoded,
          inInclusiveRange(gausssize.min.round(), gausssize.max.round()),
        );
      }
    });

    test('越界值先夹紧再编码', () {
      final gain = DspEffectsService.specOf(
        'bass',
      ).params.firstWhere((param) => param.key == 'gain');
      expect(double.parse(gain.encode(999)), gain.max);
      expect(double.parse(gain.encode(-999)), gain.min);
    });
  });

  test('滤镜链以限幅收尾，兜住前级增益', () {
    expect(DspEffectsService.filters.last.id, 'alimiter');
  });
}
