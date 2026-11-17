#!/bin/bash
pkill -9 -f "deep-idle-analysis/master.sh" 2>/dev/null; pkill -9 -f "power/cpustat.pl" 2>/dev/null; sleep 1
sysctl -w debug.wexpsr1=1 >/dev/null 2>&1
launchctl remove local.deepidle-master 2>/dev/null
launchctl submit -l local.deepidle-master -- /bin/bash /Users/user/deep-idle-analysis/master.sh
exit 0
