#!/bin/bash
O=/Users/user/psr-analysis/power-ab.txt; W=/Users/user/tweak-backup-2026-11-13/power/w.pl
perf() { ioreg -l -d1 -w0 | sed -n 's/.*"WhateverXePsrStat" = <\([0-9a-f]*\)>.*/\1/p' | cut -c65-72 | perl -ne 'chomp; print unpack("V", pack("H8", $_))'; }
echo "# $(date '+%F %T') 시작, $(pmset -g batt | head -1)" > $O
for seg in 1 0 1 0 1 0; do
  sysctl -w debug.wexpsr1=$seg >/dev/null; sleep 30
  p0=$(perf); n=0; sum=0; vals=""
  while [ $n -lt 18 ]; do
    w=$(perl $W | sed -n 's/.*inst=\([0-9.]*\)W.*/\1/p'); vals="$vals $w"; n=$((n+1)); sleep 5
  done
  p1=$(perf)
  echo "psr=$seg perf_ms=$((p1-p0)) watts:$vals" >> $O
done
sysctl -w debug.wexpsr1=1 >/dev/null
echo "# $(date '+%F %T') 끝, $(pmset -g batt | head -1)" >> $O
chown user:staff $O; touch /Users/user/psr-analysis/power-ab.done
