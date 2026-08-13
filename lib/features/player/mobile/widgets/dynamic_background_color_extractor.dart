import 'dart:math' as math;

import 'package:flutter/material.dart';

class DynamicBackgroundColorExtractor {
  static List<Color> extractColors({
    Color? vibrantColor,
    Color? mutedColor,
    Color? dominantColor,
    Color? lightVibrantColor,
    Color? darkVibrantColor,
    Color? lightMutedColor,
    Color? darkMutedColor,
  }) {
    final List<Color> result = [];
    
    // 候选池：按优先级排序
    final List<Color?> candidates = [
      vibrantColor,
      mutedColor,
      dominantColor,
      darkVibrantColor,
      lightVibrantColor,
      darkMutedColor,
      lightMutedColor,
    ];

    // 1. 基础筛选与去重
    for (final color in candidates) {
      if (color != null && !_isSimilarColor(color, result)) {
        result.add(color);
      }
    }
    
    // 3. 增强逻辑：如果颜色少于 3 个，通过色相旋转生成互补/邻近色，确保背景丰富度
    if (result.length < 3) {
      if (result.isEmpty) {
        result.addAll(getDefaultColors());
      } else {
        final baseColor = result[0];
        final hsl = HSLColor.fromColor(baseColor);
        
        // 如果只有一个颜色，生成三元色 (Triadic) + 更大的明度差异
        if (result.length == 1) {
          // 第二色：色相 +120°，明度略微调暗
          final color2 = hsl
              .withHue((hsl.hue + 120) % 360)
              .withSaturation(math.max(hsl.saturation, 0.55))
              .withLightness((hsl.lightness - 0.15).clamp(0.2, 0.75))
              .toColor();
          // 第三色：色相 +240°，明度略微调亮
          final color3 = hsl
              .withHue((hsl.hue + 240) % 360)
              .withSaturation(math.max(hsl.saturation, 0.55))
              .withLightness((hsl.lightness + 0.15).clamp(0.25, 0.8))
              .toColor();
          result.add(color2);
          result.add(color3);
        } 
        // 如果有两个颜色，生成一个互补色（色相 +180°）
        else if (result.length == 2) {
          final color3 = hsl
              .withHue((hsl.hue + 180) % 360)
              .withSaturation(math.max(hsl.saturation, 0.5))
              .withLightness((hsl.lightness + 0.1).clamp(0.25, 0.75))
              .toColor();
          result.add(color3);
        }
      }
    }
    
    // 4. 最终补齐到 5 个（通过更大的色相偏移和明度变化防止单调）
    int fillIndex = 0;
    while (result.length < 5) {
      final base = result[fillIndex % result.length];
      final hsl = HSLColor.fromColor(base);
      // 交替使用不同的偏移策略
      final hueOffset = (fillIndex % 2 == 0) ? 45.0 : -30.0;
      final lightnessOffset = (fillIndex % 2 == 0) ? 0.18 : -0.12;
      result.add(hsl
          .withHue((hsl.hue + hueOffset) % 360)
          .withLightness((hsl.lightness + lightnessOffset).clamp(0.15, 0.85))
          .toColor());
      fillIndex++;
    }
    
    return result.take(5).toList();
  }
  
  /// 色彩相似度判定 (基于 HSL 颜色空间)
  /// 使用色相、饱和度、明度三个维度综合判断，比 RGB 欧几里得距离更符合人眼感知
  static bool _isSimilarColor(Color color, List<Color> existingColors) {
    final hsl = HSLColor.fromColor(color);
    
    for (final existing in existingColors) {
      final existingHsl = HSLColor.fromColor(existing);
      
      // 计算色相差（考虑色环的循环特性，0° 和 360° 是同一个颜色）
      double hueDiff = (hsl.hue - existingHsl.hue).abs();
      if (hueDiff > 180) hueDiff = 360 - hueDiff;
      
      // 明度差
      final lightnessDiff = (hsl.lightness - existingHsl.lightness).abs();
      
      // 饱和度差
      final saturationDiff = (hsl.saturation - existingHsl.saturation).abs();
      
      // 判定规则：
      // - 色相差 < 25° 且 明度差 < 0.12 且 饱和度差 < 0.2 => 认为相似
      // - 任一维度超出阈值则认为不同
      if (hueDiff < 25 && lightnessDiff < 0.12 && saturationDiff < 0.2) {
        return true;
      }
    }
    return false;
  }

  static List<Color> getDefaultColors() => const [
    Color(0xFF60A5FA), Color(0xFF1E3A5F), Color(0xFF3B82F6),
    Color(0xFF6366F1), Color(0xFF1E1B4B),
  ];
}
