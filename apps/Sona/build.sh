#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP=build/Sona.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -swift-version 5 \
  -target x86_64-apple-macos14.0 \
  -framework SwiftUI -framework AppKit -framework AVFoundation -framework Accelerate \
  -framework MediaPlayer -framework CoreServices -framework Carbon \
  Sources/*.swift -o "$APP/Contents/MacOS/Sona"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null
echo "빌드 완료: $APP"
if [ "${1:-}" = install ]; then
  rm -rf /Applications/Sona.app && cp -R "$APP" /Applications/ && echo "설치: /Applications/Sona.app"
fi
