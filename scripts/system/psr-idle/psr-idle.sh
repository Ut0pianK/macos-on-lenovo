#!/bin/bash
IDLE=2; LOG=/var/log/psr1.log
n=0; until sysctl -n debug.wexpsr1_idle >/dev/null 2>&1 || [ $n -ge 60 ]; do sleep 2; n=$((n+1)); done
sysctl -n debug.wexpsr1_idle >/dev/null 2>&1 || { echo "$(date '+%F %T') [psr-idle] sysctl 없음(드라이버가 PSR 조정을 지원하지 않는 빌드) — 건너뜀" >> $LOG; exit 0; }
[ "$(sysctl -n debug.wexpsr1 2>/dev/null)" = 1 ] || { sysctl -w debug.wexpsr1_idle=$IDLE >/dev/null; echo "$(date '+%F %T') [psr-idle] idle=$IDLE (PSR1 꺼져 있어 값만 설정)" >> $LOG; exit 0; }
sysctl -w debug.wexpsr1_idle=$IDLE debug.wexpsr1=0 >/dev/null; sleep 1; sysctl -w debug.wexpsr1=1 >/dev/null
echo "$(date '+%F %T') [psr-idle] idle=$(sysctl -n debug.wexpsr1_idle) 적용" >> $LOG
