#!/bin/bash
set -euo pipefail
A=/Applications/Helium.app; MODE=${1:-gpu}
V="$A/Contents/Frameworks/Helium Framework.framework/Versions/157.0.8103.50"
W=$(mktemp -d ${TMPDIR:-/tmp})
ents() {
  local f="$W/$(echo "$1" | md5).plist"
  codesign -d --entitlements - --xml "$1" 2>/dev/null > "$f" || true
  [ -s "$f" ] || echo '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict/></plist>' > "$f"
  if [ "$2" = 1 ]; then /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$f" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :com.apple.security.cs.disable-library-validation true" "$f"; fi
  plutil -lint "$f" >/dev/null; echo "$f"
}
sig() {
  local e; e=$(ents "$1" "$2")
  codesign --force --sign - --options runtime --entitlements "$e" --timestamp=none "$1"
  echo "signed: ${1#$A/} (dlv=$2)"
}
gpu() { case "$1" in *"Helium Helper (Aperitif).app"|*"Helium Helper (GPU).app"|*"Helium Helper (Aperitif GPU).app") echo 1;; *) [ "$MODE" = all ] && echo 1 || echo 0;; esac; }
xattr -cr "$A"
for l in "$V/Libraries/"*.dylib; do sig "$l" 0; done
S="$V/Frameworks/Sparkle.framework/Versions/B"
sig "$S/Autoupdate" "$( [ "$MODE" = all ] && echo 1 || echo 0)"; sig "$S/Updater.app" "$( [ "$MODE" = all ] && echo 1 || echo 0)"; sig "$V/Frameworks/Sparkle.framework" 0
for h in web_app_shortcut_copier chrome_crashpad_handler app_mode_loader; do sig "$V/Helpers/$h" "$( [ "$MODE" = all ] && echo 1 || echo 0)"; done
for h in "$V/Helpers/"*.app; do sig "$h" "$(gpu "$h")"; done
sig "$A/Contents/Frameworks/Helium Framework.framework" 0
sig "$A" "$( [ "$MODE" = all ] && echo 1 || echo 0)"
codesign --verify --deep --strict "$A" && echo "verify OK"
