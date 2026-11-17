#!/bin/bash
D=/Library/Preferences/FeatureFlags/Domain
[ -e "$D/SpotlightUI.plist" ] && { echo "이미 있음 — 중단"; exit 1; }
cp /Users/user/tweak-backup-2026-11-12/launchpad/SpotlightUI.plist "$D/SpotlightUI.plist" && chown root:wheel "$D/SpotlightUI.plist" && chmod 644 "$D/SpotlightUI.plist" && echo applied
