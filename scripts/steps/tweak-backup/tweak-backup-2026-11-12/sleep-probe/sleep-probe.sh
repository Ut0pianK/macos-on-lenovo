#!/bin/bash
L=/Users/user/tweak-backup-2026-11-12/sleep-probe/probe-$(date +%H%M%S).log
exec >> "$L" 2>&1
echo "===== sleep-probe $(date) ====="
pmset -g | grep -E "SleepDisabled|hibernatemode|standby "
pmset -a disablesleep 0; echo "disablesleep 0 rc=$?"
pmset relative wake 70; echo "wake 예약 rc=$?"
sync; sleep 10
echo "sleepnow $(date '+%T')"; sync
pmset sleepnow; echo "sleepnow rc=$?"
sleep 45
echo "스크립트 재개 $(date '+%T')"
pmset -a disablesleep 1; echo "disablesleep 1 rc=$?"
pmset -g log | grep -E " Sleep  | Wake  |DarkWake|Entering|Failure|Kernel Client|PMRD|slow|Timedout" | tail -25
echo "===== 끝 $(date '+%T') ====="
chown user:staff "$L"
