#!/bin/sh
set -e
D=/Users/user/tweak-backup-2026-11-12/turbo-thermal
mkdir -p /usr/local/etc
install -m 755 -o root -g wheel "$D/cputemp" /usr/local/bin/cputemp
[ -f /usr/local/etc/turbo-ac.conf ] || install -m 644 -o user -g staff "$D/turbo-ac.conf" /usr/local/etc/turbo-ac.conf
install -m 755 -o root -g wheel "$D/turbo-ac.sh" /usr/local/libexec/turbo-ac.sh
launchctl bootout system/local.turbo-ac 2>/dev/null || true
launchctl bootstrap system /Library/LaunchDaemons/local.turbo-ac.plist
echo installed
