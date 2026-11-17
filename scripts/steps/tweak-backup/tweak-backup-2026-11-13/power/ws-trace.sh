#!/bin/bash
WS=$(pgrep -x WindowServer)
perl -e 'alarm 3; exec @ARGV' /usr/bin/ktrace trace -f S0x010a,S0x040c,S0x0109 > /Users/user/tweak-backup-2026-11-13/power/ws-kt.txt 2>&1
/usr/bin/sample $WS 3 1 -mayDie -file /Users/user/tweak-backup-2026-11-13/power/ws-sample.txt >/dev/null 2>&1
chmod 644 /Users/user/tweak-backup-2026-11-13/power/ws-kt.txt /Users/user/tweak-backup-2026-11-13/power/ws-sample.txt
