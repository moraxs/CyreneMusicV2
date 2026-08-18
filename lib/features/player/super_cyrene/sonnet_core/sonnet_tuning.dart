class SonnetTuning {
  const SonnetTuning({
    this.cameraTracking = true,
    this.chromaticAberration = true,
    this.ghostEchoes = true,
    this.particleDecor = true,
    this.hudBackground = true,
    this.fixedGeometry = true,
    this.spatial3d = true,
    this.guides = true,
    this.frameDecor = true,
    this.cameraBreath = true,
    this.musicStaff = true,
    this.creditsPoster = true,
    this.glitchTransitions = true,
  });

  final bool cameraTracking;
  final bool chromaticAberration;
  final bool ghostEchoes;
  final bool particleDecor;
  final bool hudBackground;
  final bool fixedGeometry;
  final bool spatial3d;
  final bool guides;
  final bool frameDecor;
  final bool cameraBreath;
  final bool musicStaff;
  final bool creditsPoster;
  final bool glitchTransitions;

  static const defaults = SonnetTuning();
}
