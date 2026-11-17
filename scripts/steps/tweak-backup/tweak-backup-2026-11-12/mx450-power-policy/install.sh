#!/bin/sh
set -e
D=/Users/user/tweak-backup-2026-11-12/mx450-power-policy
mkdir -p /usr/local/etc/mx450
install -m 644 -o root -g wheel "$D/allow-ac.txt" /usr/local/etc/mx450/allow-ac.txt
install -m 644 -o root -g wheel "$D/allow-battery.txt" /usr/local/etc/mx450/allow-battery.txt
[ -f /usr/local/etc/mx450/mode ] || echo auto > /usr/local/etc/mx450/mode
chown user:staff /usr/local/etc/mx450/mode; chmod 644 /usr/local/etc/mx450/mode
install -m 755 -o root -g wheel "$D/mx450-power-policy.sh" /usr/local/libexec/mx450-power-policy.sh
install -m 755 -o root -g wheel "$D/mx450-policy" /usr/local/bin/mx450-policy
install -m 644 -o root -g wheel "$D/local.mx450-power-policy.plist" /Library/LaunchDaemons/local.mx450-power-policy.plist
launchctl bootout system/local.mx450-power-policy 2>/dev/null || true
launchctl bootstrap system /Library/LaunchDaemons/local.mx450-power-policy.plist
echo installed
