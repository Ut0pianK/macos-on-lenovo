#!/bin/bash
O=/Users/user/deep-idle-analysis/root-step1.txt; P=/Users/user/tweak-backup-2026-11-13/power; A=/usr/local/etc/mx450/allow-ac.txt
echo "# $(date '+%F %T')" > $O
if ! grep -q "^-ClaudeUsageBar$" $A; then
  cp -p $A $A.bak-20261114
  { echo "# rung 3: everyone; -Name denies"
    echo "# (2026-11-14) 늘 떠 있는 앱은 충전 중에도 MX450 을 받지 않는다: 한번 잡으면 배터리로 바꿔도 놓지 않아 MX450 이 못 꺼짐(유휴 5W → 10W)"
    printf '%s\n' "-ClaudeUsageBar" "-BatteryEstimate" "-iStat Menus Status" "-iStat Menus" "-iStatMenusDaemon" "-Terminal" "-Sona" "-KakaoTalk"
    grep -v "^# rung 3" $A; } > $A.new && mv -f $A.new $A && chmod 644 $A
fi
echo "--- allow-ac.txt" >> $O; cat $A >> $O
epp() { perl $P/cpustat.pl 2 | grep -o "EPP=0x[0-9a-f]*"; }
echo "--- epp_override 시험" >> $O
echo "처음: override=$(sysctl -n machdep.xcpm.epp_override) $(epp)" >> $O
for v in 192 64 255 1 0; do
  sysctl -w machdep.xcpm.epp_override=$v >> $O 2>&1; sleep 3
  echo "override=$v → $(epp) $(epp)" >> $O
done
chown user:staff $O
