#!/bin/bash
D=/Users/user/tweak-backup-2026-11-14/psr-idle; PL=/Library/LaunchDaemons/local.psr-idle.plist
case "${1:-}" in
install) install -m 755 $D/psr-idle.sh /usr/local/libexec/psr-idle.sh && install -m 644 -o root -g wheel $D/local.psr-idle.plist $PL && launchctl bootout system/local.psr-idle 2>/dev/null; launchctl bootstrap system $PL; sleep 4; tail -1 /var/log/psr1.log;;
remove) launchctl bootout system/local.psr-idle 2>/dev/null; mv $PL $D/local.psr-idle.plist.removed 2>/dev/null; sysctl -w debug.wexpsr1_idle=6 >/dev/null; echo removed;;
*) echo "install|remove"; exit 1;;
esac
