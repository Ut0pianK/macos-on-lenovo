#!/bin/bash
sleep 90
for i in $(seq 1 6); do ioreg -rn AppleSmartBattery | perl -ne '$a=$1 if /"InstantAmperage" = (\d+)/; $v=$1 if /"Voltage" = (\d+)/; END{if(length($a)>=19){$m=551616-substr($a,-6); $m+=1e6 if $m<0; $a=-$m} printf "%.1f ", -$a*$v/1e6}'; sleep 5; done > /Users/user/tweak-backup-2026-11-13/power/idle-watts.txt
pmset -g batt >> /Users/user/tweak-backup-2026-11-13/power/idle-watts.txt
/usr/bin/powermetrics -i 5000 -n 2 --samplers cpu_power,gpu_power,interrupts,tasks > /Users/user/tweak-backup-2026-11-13/power/idle-pm.txt 2>&1
chmod 644 /Users/user/tweak-backup-2026-11-13/power/idle-*.txt; touch /Users/user/tweak-backup-2026-11-13/power/idle.done
