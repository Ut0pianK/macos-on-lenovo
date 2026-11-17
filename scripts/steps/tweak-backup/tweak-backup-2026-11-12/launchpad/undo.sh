#!/bin/bash
F=/Library/Preferences/FeatureFlags/Domain/SpotlightUI.plist
[ -f "$F" ] && mv "$F" /Users/user/tweak-backup-2026-11-12/launchpad/SpotlightUI.plist.removed && echo undone
