#!/bin/sh
CM=/usr/local/bin/conservation-mode
CONF=/usr/local/etc/charge-limit.conf
LOG=/var/log/charge-limit.log
say() { echo "$(date '+%F %T') $*" >> "$LOG"; }

bye() { "$CM" on >/dev/null 2>&1; say "종료 신호 → 보존 모드 on"; exit 0; }
trap bye TERM INT

say "시작"
while :; do
    limit=$(tr -cd '0-9' < "$CONF" 2>/dev/null | cut -c1-3)
    case "$limit" in ''|0*) limit=80;; esac
    [ "$limit" -gt 100 ] && limit=100
    [ "$limit" -lt 61 ] && limit=61
    resume=$((limit - 5))
    pct=$(pmset -g batt | grep -Eo '[0-9]+%' | head -1 | tr -d '%')
    mode=$("$CM" status 2>/dev/null)
    if [ -n "$pct" ]; then
        if [ "$limit" -ge 100 ]; then
            [ "$mode" = on ] && { "$CM" off >/dev/null; say "제한 없음 → 보존 모드 off (${pct}%)"; }
        elif [ "$pct" -ge "$limit" ] && [ "$mode" != on ]; then
            "$CM" on >/dev/null; say "${pct}% ≥ ${limit}% → 보존 모드 on (충전 중지)"
        elif [ "$pct" -le "$resume" ] && [ "$mode" != off ]; then
            "$CM" off >/dev/null; say "${pct}% ≤ ${resume}% → 보존 모드 off (충전 재개)"
        fi
    fi
    sleep 30 & wait $!
done
