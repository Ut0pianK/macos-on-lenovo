#!/bin/bash
set -euo pipefail
A=/Applications/Helium.app; B=/Users/user/tweak-backup-2026-11-13/helium
pgrep -f "$A/Contents/MacOS/Helium" >/dev/null && { echo "Helium 을 먼저 종료"; exit 1; }
V=$(ls -d "$A/Contents/Frameworks/Helium Framework.framework/Versions/"[0-9]* | head -1)/Helpers
xattr -cr "$A"
for h in "Helium Helper (Aperitif).app" "Helium Helper (GPU).app" "Helium Helper (Aperitif GPU).app"; do
  f="$B/ents-$(echo "$h" | tr ' ()' '___').plist"
  codesign -d --entitlements - --xml "$V/$h" 2>/dev/null > "$f" || true
  [ -s "$f" ] || echo '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict/></plist>' > "$f"
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$f" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :com.apple.security.cs.disable-library-validation true" "$f"
  codesign --force --sign - --options runtime --entitlements "$f" --timestamp=none "$V/$h" 2>&1 | grep -v "replacing existing signature" || true
  echo "$h: $(codesign -dv "$V/$h" 2>&1 | grep -o 'flags=[^ ]*')"
done
