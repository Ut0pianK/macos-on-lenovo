#!/bin/bash
D=/Users/user/deep-idle-analysis; P=/Users/user/tweak-backup-2026-11-13/power; O=$D/master.txt
pmc() { ioreg -l -d1 -w0 | sed -n 's/.*"WhateverXePmcStat" = <\([0-9a-f]*\)>.*/\1/p' > $D/pmc-$1.hex; }
seg() {
  sleep 20
  c=$(perl $P/cpustat.pl 130 | awk '/PC2/{a=$2} /PC6/{b=$2} /PC8/{c=$2} /PC9/{d=$2} /PC10/{e=$2} /패키지/{w=$2} /EPB/{epb=$3} END{printf "PC2 %s PC6 %s PC8 %s PC9 %s PC10 %s pkg %sW EPB=%s", a,b,c,d,e,w,epb}')
  echo "$1: $c | 배터리 $(perl $P/w.pl | sed 's/.*inst=\([0-9.]*W\).*/\1/')" >> $O
}
rm -f $D/master.done; echo "# $(date '+%F %T') 시작 $(pmset -g batt | head -1)" > $O
E0=$(sysctl -n debug.wexepb 2>/dev/null)
pmc on
for e in 0 6 15 0 15 6; do sysctl -w debug.wexepb=$e >/dev/null 2>&1; seg "epb=$e"; done
sysctl -w debug.wexepb=6 >/dev/null 2>&1
for p in 0 1 0 1; do sysctl -w debug.wexpsr1=$p >/dev/null; seg "psr=$p(epb6)"; done
sudo -u user pmset displaysleepnow; sleep 45; pmc off
sysctl -w debug.wexpsr1=1 >/dev/null
seg "화면끔(epb6)"
caffeinate -u -t 3
echo "# $(date '+%F %T') 끝" >> $O
chown user:staff $O $D/pmc-*.hex; touch $D/master.done; chown user:staff $D/master.done
launchctl remove local.deepidle-master
