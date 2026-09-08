#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint media_kit_libs_macos_audio.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  # 同 media_kit_libs_ios_audio：上游丢掉了 make 的返回码，校验和对不上时会
  # 静默产出一个不含 Mpv.framework 的包，启动即白屏。让它停在构建期。
  raise "media_kit_libs_macos_audio: `make` failed — libmpv xcframeworks were not fetched" unless system("make")

  s.name             = 'media_kit_libs_macos_audio'
  s.version          = '1.0.4'
  s.summary          = 'macOS dependency package for package:media_kit'
  s.description      = <<-DESC
  macOS dependency package for package:media_kit.
                       DESC
  s.homepage         = 'https://github.com/media-kit/media-kit.git'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Hitesh Kumar Saini' => 'saini123hitesh@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.vendored_frameworks = 'Frameworks/*.xcframework'

  s.platform = :osx, '10.9'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
