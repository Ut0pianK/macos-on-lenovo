#!/bin/bash
A=/usr/local/bin/alc-verb; LOG=~/Library/Logs/headset-ctia.log; L=/tmp/alc-verb.lock
rd() { $A 0x20 SET_COEF_INDEX $1 >/dev/null 2>&1; $A 0x20 GET_PROC_COEF 0 2>/dev/null | tail -1; }
wr() { $A 0x20 SET_COEF_INDEX $1 >/dev/null 2>&1; $A 0x20 SET_PROC_COEF $2 >/dev/null 2>&1; }
echo "$(date '+%F %T') 시작" >> $LOG
while :; do
  sleep 2
  [ -e ~/.alc-verb-pause ] && continue
  [ -d $L ] && [ $(( $(date +%s) - $(stat -f %m $L) )) -gt 30 ] && rmdir $L 2>/dev/null
  mkdir $L 2>/dev/null || continue
  s=$($A 0x21 GET_PIN_SENSE 0 2>/dev/null | tail -1)
  if [ $(( ${s:-0} & 0x80000000 )) -ne 0 ]; then
    v=$(rd 0x45)
    if [ "$v" != 0x0000d489 ]; then
      wr 0x45 0xd489; wr 0x1b 0x0c2b
      echo "$(date '+%F %T') 0x45 $v → d489" >> $LOG
    fi
  fi
  rmdir $L
done
