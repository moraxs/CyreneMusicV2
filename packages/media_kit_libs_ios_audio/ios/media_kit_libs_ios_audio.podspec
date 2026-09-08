#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint media_kit_libs_ios_audio.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  # 上游这里是裸的 `system("make")`——Ruby 的 system 只返回 true/false，失败被
  # 直接丢掉。于是 make 挂掉（例如 Makefile 里的 SHA256 与 release 资产对不上）
  # 时 pod install 照常走完，Frameworks/ 是空的，下面的 vendored_frameworks 匹配
  # 不到东西，构建照样成功——但产物里没有 Mpv.framework，应用启动时
  # MediaKit.ensureInitialized() 抛异常、runApp 永远不执行，表现为白屏。
  # 所以这里必须让失败停在构建期。
  raise "media_kit_libs_ios_audio: `make` failed — libmpv xcframeworks were not fetched" unless system("make")

  s.name             = 'media_kit_libs_ios_audio'
  s.version          = '1.0.4'
  s.summary          = 'iOS dependency package for package:media_kit'
  s.description      = <<-DESC
  iOS dependency package for package:media_kit.
                       DESC
  s.homepage         = 'https://github.com/media-kit/media-kit.git'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Hitesh Kumar Saini' => 'saini123hitesh@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'

  s.vendored_frameworks = 'Frameworks/*.xcframework'

  s.platform = :ios, '9.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # Flutter.framework does not contain a i386 slice.
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.0'
end
