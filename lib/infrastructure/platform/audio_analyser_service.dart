/// 音频频谱分析服务（对应 Next.js demo/lib/services/audioAnalyserService.ts）。
///
/// 原实现基于 WebAudio AnalyserNode 提取实时频段能量。media_kit 尚未提供
/// 跨平台 FFT 数据流，这里保留同名 API 作为占位：返回全零，可视化竖条静止。
/// TODO: 接入平台 FFT（如 media_kit 的音频回调 / 原生通道）后填充真实数据。
class AudioAnalyserService {
  AudioAnalyserService._();

  static final AudioAnalyserService instance = AudioAnalyserService._();

  /// 取 [barCount] 条频段能量（0..1）。数据源未接入时全零。
  List<double> getBarData(int barCount) =>
      List<double>.filled(barCount, 0, growable: false);
}
