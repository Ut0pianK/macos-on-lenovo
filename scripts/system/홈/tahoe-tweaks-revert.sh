#!/bin/zsh
for k in autohide-delay autohide-time-modifier mineffect launchanim expose-animation-duration show-recents; do defaults delete com.apple.dock $k 2>/dev/null; done
defaults delete -g NSAutomaticWindowAnimationsEnabled 2>/dev/null
defaults delete -g NSWindowResizeTime 2>/dev/null
defaults delete -g NSScrollAnimationEnabled 2>/dev/null
defaults delete com.apple.finder DisableAllAnimations 2>/dev/null
defaults delete com.apple.desktopservices DSDontWriteNetworkStores 2>/dev/null
defaults delete com.apple.desktopservices DSDontWriteUSBStores 2>/dev/null
killall Dock Finder
echo "Reverted."
