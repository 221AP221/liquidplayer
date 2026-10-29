# VLCKit istəyə bağlıdır: onsuz da layihə qurulur (bax README).
# Əvvəlcə `xcodegen generate`, sonra `pod install`, sonra .xcworkspace-i aç.
platform :ios, '18.0'
project 'LiquidPlayer.xcodeproj'

target 'LiquidPlayer' do
  use_frameworks!
  pod 'MobileVLCKit', '~> 3.6.0'

  target 'LiquidPlayerTests' do
    inherit! :search_paths
  end
end
