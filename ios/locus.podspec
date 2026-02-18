#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'locus'
  s.version          = '2.1.1'
  s.summary          = 'Background geolocation SDK for Flutter.'
  s.description      = <<-DESC
    Background geolocation SDK for Flutter. Native tracking, geofencing, 
    activity recognition, and HTTP sync for Android and iOS.
                       DESC
  s.homepage         = 'https://github.com/weorbis/locus'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'WeOrbis' => 'info@weorbis.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/LocusPlugin.{h,m}',
                   'Classes/SwiftLocusPlugin*.swift',
                   'Classes/Core/**/*',
                   'Classes/Geofence/**/*',
                   'Classes/Motion/**/*',
                   'Classes/Storage/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '14.0'
  s.frameworks = 'CoreLocation', 'CoreMotion'
  s.library = 'sqlite3'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.9'
end
