#!/bin/bash
D=/Users/user/deep-idle-analysis; O=$D/l1ss-test.txt; F=/Users/user/deep-idle-analysis/.l1ss-io.tmp
st() { /usr/bin/python3 -I $D/pmcstat.py 2>/dev/null | grep -E "^L1SS|02:00.0|03:00.0|00:1c.0|00:1d.0"; }
rm -f $D/l1ss-test.done; echo "# $(date '+%F %T') 시작" > $O
io() {
  local t0=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  dd if=/dev/zero of=$F bs=1m count=64 2>/dev/null && sync && dd if=$F of=/dev/null bs=1m 2>/dev/null; local rc=$?
  local t1=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  echo "$(date '+%T') io($1) rc=$rc $(perl -e "printf '%.2fs', $t1-$t0")" >> $O; sync
}
io "켜기 전"
sysctl -w debug.wexl1ss=1 >> $O 2>&1; sleep 20; echo "--- SD 리더만 켬" >> $O; st >> $O; sync
sysctl -w debug.wexl1ss=3 >> $O 2>&1; sleep 5; echo "--- NVMe 까지 켬" >> $O; st >> $O; sync
for w in 2 10 30 30 45; do sleep $w; io "쉼 ${w}s 뒤"; done
echo "--- 최종" >> $O; st >> $O
/usr/bin/log show --last 4m --predicate 'process == "kernel" AND (eventMessage CONTAINS[c] "nvme" OR eventMessage CONTAINS[c] "AER" OR eventMessage CONTAINS[c] "link down" OR eventMessage CONTAINS "IOPCI")' --style compact 2>/dev/null | grep -v "log run" | tail -8 | cut -c1-180 >> $O
rm -f $F; echo "# $(date '+%F %T') 끝 (wexl1ss=$(sysctl -n debug.wexl1ss))" >> $O
chown user:staff $O; touch $D/l1ss-test.done; chown user:staff $D/l1ss-test.done
launchctl remove local.deepidle-l1ss
