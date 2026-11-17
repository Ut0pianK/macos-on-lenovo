#!/bin/bash
O=/Users/user/deep-idle-analysis/root-step2.txt; P=/Users/user/tweak-backup-2026-11-13/power
epp() { perl $P/cpustat.pl 1 | grep -o "EPP=0x[0-9a-f]*" | head -1; }
echo "# $(date '+%F %T')" > $O; ok=1
echo "처음: wexepp=$(sysctl -n debug.wexepp) $(epp)" >> $O
for v in 192 64 128; do
  sysctl -w debug.wexepp=$v >> $O 2>&1; sleep 2
  a=$(epp); sleep 1; b=$(epp); sleep 1; c=$(epp)
  echo "wexepp=$v → $a $b $c" >> $O
  want=$(printf 'EPP=0x%02x' $v); [ "$a" = "$want" ] || [ "$b" = "$want" ] || [ "$c" = "$want" ] || ok=0
done
echo "검증: $ok" >> $O
if [ $ok = 1 ]; then
  cp -p /usr/local/libexec/turbo-ac.sh /usr/local/libexec/turbo-ac.sh.bak-20261114-epp
  install -m 755 -o root -g wheel /Users/user/deep-idle-analysis/turbo-ac.sh.new /usr/local/libexec/turbo-ac.sh
  grep -q "^EPP_AC=" /usr/local/etc/turbo-ac.conf || printf 'EPP_AC=64\nEPP_BATT=192\n' >> /usr/local/etc/turbo-ac.conf
  launchctl kickstart -k system/local.turbo-ac; sleep 9
  echo "설치 후: wexepp=$(sysctl -n debug.wexepp) $(epp) | $(tail -2 /var/log/turbo-ac.log | tr '\n' ';')" >> $O
fi
chown user:staff $O
