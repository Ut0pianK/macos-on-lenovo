#!/bin/bash
perl -e 'alarm 3; exec @ARGV' /usr/bin/ktrace trace -f S0x0140 > /Users/user/tweak-backup-2026-11-13/power/callout.txt 2>&1
kextstat > /Users/user/tweak-backup-2026-11-13/power/kextstat.txt 2>&1; chmod 644 /Users/user/tweak-backup-2026-11-13/power/callout.txt /Users/user/tweak-backup-2026-11-13/power/kextstat.txt
