#!/bin/bash
sleep 20
/usr/bin/powermetrics -i 3000 -n 2 --samplers cpu_power,gpu_power,interrupts,tasks > /Users/user/tweak-backup-2026-11-13/power/clean-pm.txt 2>&1
perl -e 'alarm 3; exec @ARGV' /usr/bin/ktrace trace -f S0x0140,S0x0109 > /Users/user/tweak-backup-2026-11-13/power/clean-kt.txt 2>&1
chmod 644 /Users/user/tweak-backup-2026-11-13/power/clean-pm.txt /Users/user/tweak-backup-2026-11-13/power/clean-kt.txt; touch /Users/user/tweak-backup-2026-11-13/power/clean.done
