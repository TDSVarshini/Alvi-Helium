Pod::Spec.new do |s|
  s.name             = 'qring_sdk'
  s.version          = '0.1.0'
  s.summary          = 'Flutter bridge for the QC Wireless smart-ring SDK (QCBandSDK).'
  s.description      = 'Wraps QCBandSDK.framework (static, arm64 device only) behind the qring_sdk method/event channels.'
  s.homepage         = 'https://alvi.ca'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'ALVI Intellects Inc.' => 'care@truerenewables.in' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{h,m}'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.static_framework = true
  s.frameworks = 'CoreBluetooth', 'CoreLocation', 'UIKit', 'Foundation', 'Security', 'CFNetwork'

  # QCBandSDK is a static library in a .framework wrapper with an arm64
  # device slice only. It is not added as vendored_frameworks (that would link
  # it for the Simulator too and fail); instead headers are always visible and
  # the library is linked into the app for iphoneos builds only. The plugin
  # compiles a stub on the Simulator (see QringSdkPlugin.m).
  s.preserve_paths = 'Frameworks/QCBandSDK.framework'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'FRAMEWORK_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/Frameworks"',
  }
  # -ObjC: the SDK ships Objective-C categories.
  s.user_target_xcconfig = {
    'FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]' => '$(inherited) "${PODS_ROOT}/../.symlinks/plugins/qring_sdk/ios/Frameworks"',
    'OTHER_LDFLAGS[sdk=iphoneos*]' => '$(inherited) -ObjC -framework QCBandSDK',
  }
end
