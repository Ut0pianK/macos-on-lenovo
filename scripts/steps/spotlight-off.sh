#!/bin/zsh
U=$(id -u ${SUDO_USER:-$USER})
SYS=(com.apple.metadata.mds com.apple.metadata.mds.index com.apple.metadata.mds.index.readonly
     com.apple.metadata.mds.scan com.apple.metadata.mds.spindump com.apple.msrpc.mdssvc)
GUI=(com.apple.Spotlight com.apple.corespotlightd com.apple.corespotlightservice com.apple.managedcorespotlightd
     com.apple.spotlightknowledged com.apple.spotlightknowledged.updater com.apple.spotlightknowledged.importer
     com.apple.metadata.mdbulkimport com.apple.mdworker.shared com.apple.mdworker.single.arm64
     com.apple.mdworker.single.x86_64 com.apple.mdworker.sizing com.apple.mdworker.mail com.apple.mdworker.application)
sudo mdutil -a -i off
sudo mdutil -X /System/Volumes/Data
for l in $GUI; do for d in gui user; do sudo launchctl disable $d/$U/$l; sudo launchctl bootout $d/$U/$l 2>/dev/null; done; done
for l in $SYS; do sudo launchctl disable system/$l; sudo launchctl bootout system/$l 2>/dev/null; done
