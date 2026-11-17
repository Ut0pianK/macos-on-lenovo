#!/bin/zsh
set -e
PLIST=~/Library/LaunchAgents/local.keyboard-remap.plist
LABEL=local.keyboard-remap

if [[ "$1" == "uninstall" ]]; then
  launchctl bootout gui/$(id -u)/$LABEL 2>/dev/null || true
  rm -f $PLIST
  hidutil property --set '{"UserKeyMapping":[]}' >/dev/null
  echo "해제 완료: 키 매핑을 원래대로 되돌렸습니다."
  exit 0
fi

MAP='{"UserKeyMapping":[
{"HIDKeyboardModifierMappingSrc":0x7000000E6,"HIDKeyboardModifierMappingDst":0x70000006D},
{"HIDKeyboardModifierMappingSrc":0x700000090,"HIDKeyboardModifierMappingDst":0x70000006D},
{"HIDKeyboardModifierMappingSrc":0x700000091,"HIDKeyboardModifierMappingDst":0x70000006D},
{"HIDKeyboardModifierMappingSrc":0x7000000E0,"HIDKeyboardModifierMappingDst":0x7000000E3},
{"HIDKeyboardModifierMappingSrc":0x7000000E3,"HIDKeyboardModifierMappingDst":0x7000000E0},
{"HIDKeyboardModifierMappingSrc":0x7000000E4,"HIDKeyboardModifierMappingDst":0x7000000E7},
{"HIDKeyboardModifierMappingSrc":0x7000000E7,"HIDKeyboardModifierMappingDst":0x7000000E4}
]}'

mkdir -p ~/Library/LaunchAgents
cat > $PLIST <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL</string>
<key>ProgramArguments</key><array>
<string>/usr/bin/hidutil</string><string>property</string><string>--set</string>
<string>$MAP</string>
</array>
<key>RunAtLoad</key><true/>
</dict></plist>
EOF
plutil -lint $PLIST
launchctl bootout gui/$(id -u)/$LABEL 2>/dev/null || true
launchctl bootstrap gui/$(id -u) $PLIST
echo "등록 완료: 재부팅 후에도 키 매핑이 유지됩니다."
