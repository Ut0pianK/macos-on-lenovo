#!/bin/bash
D=~/deep-idle-analysis; P=~/tweak-backup-2026-11-13/power; cd $D; rm -f done
seg() {
  local n=$1 s=$2
  ( perl $P/cpustat.pl $s > $n-cpustat.txt 2>&1 ) &
  ( top -l 2 -s $((s-5)) -n 25 -o power -stats pid,command,cpu,power,idlew,th 2>/dev/null | awk '/^PID/{c++} c==2' > $n-top.txt ) &
  local i=0; : > $n-watts.txt
  while [ $i -lt $((s/5)) ]; do perl $P/w.pl >> $n-watts.txt; sleep 5; i=$((i+1)); done
  wait
  pmset -g assertions > $n-assertions.txt 2>&1
  ioreg -r -c NVAccel -d1 -w0 | grep -o '"PerformanceStatistics" = {[^}]*}' > $n-nv.txt
  python3 -I ~/psr-analysis/psrstat.py 2>/dev/null | tail -5 > $n-psr.txt
}
date '+%F %T 시작' > log.txt; pmset -g batt | head -2 >> log.txt
sleep 20
seg on 90
pmset displaysleepnow; sleep 25; date '+%T 화면 끔 구간 시작' >> log.txt
seg off 120
caffeinate -u -t 3; date '+%T 화면 켬' >> log.txt
touch done
