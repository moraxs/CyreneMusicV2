import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../../application/stores/fullscreen_settings_store.dart';
import '../../../presentation/cyrene/cyrene_overlays.dart';
import '../../../presentation/cyrene/cyrene_page.dart';

/// 弹出 SuperCyrene「纹理玻璃」参数微调面板。
Future<void> showSuperCyreneTexturedGlassParamsSheet(
    BuildContext context) async {
  final store = FullscreenSettingsStore.instance;
  await showCyreneSheet<void>(
    context: context,
    title: '纹理玻璃参数',
    endAction: ListenableBuilder(
      listenable: store,
      builder: (context, _) => MiuixButton(
        onPressed: store.texturedGlassParamsIsDefault
            ? null
            : store.resetTexturedGlassParams,
        child: const Text('重置'),
      ),
    ),
    builder: (context, dismiss) => ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: CyreneMenuGroup(
            children: [
              MiuixSliderPreference(
                title: '条纹宽度',
                value: store.texturedGlassFluteWidth,
                min: 8,
                max: 32,
                valueText: '${store.texturedGlassFluteWidth.round()} dp',
                onValueChange: store.setTexturedGlassFluteWidth,
              ),
              MiuixSliderPreference(
                title: '折射强度',
                value: store.texturedGlassRefractionStrength,
                min: 0,
                max: 2,
                valueText:
                    '${store.texturedGlassRefractionStrength.toStringAsFixed(2)}x',
                onValueChange: store.setTexturedGlassRefractionStrength,
              ),
              MiuixSliderPreference(
                title: '光泽亮度',
                value: store.texturedGlassLightingIntensity,
                min: 0,
                max: 2,
                valueText:
                    '${store.texturedGlassLightingIntensity.toStringAsFixed(2)}x',
                onValueChange: store.setTexturedGlassLightingIntensity,
              ),
              MiuixSliderPreference(
                title: '凹槽阴影',
                value: store.texturedGlassGrooveDepth,
                min: 0,
                max: 2,
                valueText:
                    '${store.texturedGlassGrooveDepth.toStringAsFixed(2)}x',
                onValueChange: store.setTexturedGlassGrooveDepth,
              ),
              MiuixSliderPreference(
                title: '棱镜色散',
                value: store.texturedGlassDispersion,
                min: 0,
                max: 2,
                valueText:
                    '${store.texturedGlassDispersion.toStringAsFixed(2)}x',
                onValueChange: store.setTexturedGlassDispersion,
              ),
            ],
          ),
        );
      },
    ),
  );
}
