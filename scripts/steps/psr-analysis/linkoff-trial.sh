#!/bin/bash
D=/Users/user/psr-analysis; O=$D/linkoff-trial.txt; CTL=${1:-0xA20}
st() { /usr/bin/python3 -I $D/psrstat.py 2>/dev/null | grep -E "PSR_CTL |PSR_STATUS|PSR_PERF|스위치=|켬 [0-9]|분포" | tr '\n' ';'; }
cyc() { sudo -u user pmset displaysleepnow; sleep 8; sudo -u user caffeinate -u -t 2; sleep 4; }
rm -f $D/linkoff-trial.done; echo "# $(date '+%F %T') 시작 loctl=$CTL" > $O
echo "전: $(st)" >> $O
sysctl -w debug.wexpsr1_max=${2:-30} debug.wexpsr1_loctl=$(($CTL)) debug.wexpsr1_linkoff=1 >> $O 2>&1
cyc; echo "$(date +%T) 재훈련 뒤: $(st)" >> $O
i=0; seen=0
while [ $i -lt $(( ${2:-30} + 70 )) ]; do
  sleep 1; i=$((i+1)); s=$(/usr/bin/python3 -I $D/psrstat.py 2>/dev/null | grep -E "스위치=")
  case "$s" in *"단계=동작"*) seen=1; [ $((i % 5)) = 0 ] && echo "$(date +%T) 동작 중: $(st)" >> $O;; *) [ $seen = 1 ] && break;; esac
done
echo "$(date +%T) 창 끝(i=$i, 동작 관찰=$seen): $(st)" >> $O
sysctl -w debug.wexpsr1_linkoff=0 debug.wexpsr1_loctl=544 debug.wexpsr1_max=0 debug.wexpsr1=1 >> $O 2>&1
cyc; echo "$(date +%T) 복구 재훈련 뒤: $(st)" >> $O
echo "# $(date '+%F %T') 끝" >> $O; chown user:staff $O; touch $D/linkoff-trial.done; chown user:staff $D/linkoff-trial.done
launchctl remove local.psr-linkoff-trial
