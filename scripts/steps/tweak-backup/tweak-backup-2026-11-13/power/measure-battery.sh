#!/bin/bash
D=/Users/user/tweak-backup-2026-11-13/power; OUT=$D/battery-measure.txt
for i in $(seq 1 180); do
  if ! pmset -g batt | grep -q "AC Power"; then
    l=$(sysctl -n vm.loadavg | awk '{print $2}'); awk "BEGIN{exit !($l<3)}" && break
  fi
  sleep 5
done
sleep 20
{ date '+%F %T'; pmset -g batt | sed -n 1,2p; sysctl -n vm.loadavg
  echo -n "watts: "; for i in $(seq 1 12); do ioreg -rn AppleSmartBattery | perl -ne '$a=$1 if /"InstantAmperage" = (\d+)/; $v=$1 if /"Voltage" = (\d+)/; END{if(length($a)>=19){$m=551616-substr($a,-6); $m+=1e6 if $m<0; $a=-$m} printf "%.1f ", -$a*$v/1e6}'; sleep 5; done; echo
  /usr/bin/powermetrics -i 5000 -n 2 --samplers cpu_power,gpu_power,tasks 2>&1 | grep -E 'package power|Package 0 C-state|DC6 Residency|^Name|^[A-Za-z].*[0-9]+\.[0-9]+ +[0-9]' | head -30
} > $OUT 2>&1
chmod 644 $OUT; touch $D/battery-measure.done
launchctl remove local.batterymeasure
