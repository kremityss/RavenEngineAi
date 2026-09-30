# RavenEngineAI

Native iOS control, vision, diagnostics, and ESP32-S3 companion project for Raven.

## Architecture
- SwiftUI iPhone dashboard
- ReplayKit Broadcast Upload extension scaffold
- Core ML / Vision engine scaffold
- RavenLink BLE + Wi-Fi transports
- Device / thermal / UI FPS diagnostics
- GitHub Actions unsigned IPA build

## Build
GitHub Actions builds on macOS with XcodeGen + Xcode and uploads an unsigned IPA for your own signing workflow.

Local macOS:
~~~bash
brew install xcodegen
xcodegen generate
xcodebuild -project RavenEngineAI.xcodeproj -scheme RavenEngineAI -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO
~~~

## Hardware
RavenLink firmware target: ESP32-S3 N16R8 (16 MB flash / 8 MB PSRAM).

## Branches
- main: native RavenEngineAI
- legacy-pre-native-ios: preserved old Theos/dylib project
