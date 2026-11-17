#!/bin/sh
set -e
D=/Users/user/tweak-backup-2026-11-12/charge-limit
mkdir -p /usr/local/bin /usr/local/libexec /usr/local/etc
install -m 755 -o root -g wheel "$D/conservation-mode" /usr/local/bin/conservation-mode
install -m 755 -o root -g wheel "$D/charge-limit" /usr/local/bin/charge-limit
install -m 755 -o root -g wheel "$D/charge-limit.sh" /usr/local/libexec/charge-limit.sh
[ -f /usr/local/etc/charge-limit.conf ] || echo 80 > /usr/local/etc/charge-limit.conf
chown user:staff /usr/local/etc/charge-limit.conf; chmod 644 /usr/local/etc/charge-limit.conf
install -m 644 -o root -g wheel "$D/local.charge-limit.plist" /Library/LaunchDaemons/local.charge-limit.plist
launchctl bootout system/local.charge-limit 2>/dev/null || true
launchctl bootstrap system /Library/LaunchDaemons/local.charge-limit.plist
echo installed
