#!/bin/bash
A=/usr/local/bin/alc-verb; LOG=~/Library/Logs/headset-ctia.log; L=/tmp/alc-verb.lock; WHY=${1:-manual}
rd() { $A 0x20 SET_COEF_INDEX $1 >/dev/null 2>&1; $A 0x20 GET_PROC_COEF 0 2>/dev/null | tail -1; }
wr() { $A 0x20 SET_COEF_INDEX $1 >/dev/null 2>&1; $A 0x20 SET_PROC_COEF $2 >/dev/null 2>&1; }
[ -e ~/.alc-verb-pause ] && exit 0
hp() {
  mkdir $L 2>/dev/null || return
  s=$($A 0x21 GET_PIN_SENSE 0 2>/dev/null | tail -1)
  if [ $(( ${s:-0} & 0x80000000 )) -ne 0 ]; then
    $A 0x57 SET_COEF_INDEX 0x04 >/dev/null 2>&1; v=$($A 0x57 GET_PROC_COEF 0 2>/dev/null | tail -1)
    n=$(printf '0x%04x' $(( (${v:-0} & 0xfff8) | $1 )))
    if [ $(( ${v:-0} )) -ne $(( n )) ]; then $A 0x57 SET_COEF_INDEX 0x04 >/dev/null 2>&1; $A 0x57 SET_PROC_COEF $n >/dev/null 2>&1; fi
  fi
  rmdir $L
}
case "$WHY" in hp-low) hp 1; exit 0;; hp-high) hp 4; exit 0;; esac
[ -d $L ] && [ $(( $(date +%s) - $(stat -f %m $L) )) -gt 30 ] && rmdir $L 2>/dev/null
mkdir $L 2>/dev/null || exit 0
s=$($A 0x21 GET_PIN_SENSE 0 2>/dev/null | tail -1)
if [ $(( ${s:-0} & 0x80000000 )) -ne 0 ]; then
  v=$(rd 0x45); b=$(rd 0x1b)
  if [ "$v" != 0x0000d489 ] || [ "$b" != 0x00000c2b ]; then
    wr 0x45 0xd489; wr 0x1b 0x0c2b
    echo "$(date '+%F %T') [$WHY] 0x45 $v 0x1b $b → d489/0c2b" >> $LOG
  fi
fi
rmdir $L
