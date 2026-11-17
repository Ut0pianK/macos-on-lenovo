#!/bin/bash
D=/Users/user/deep-idle-analysis; P=/Users/user/tweak-backup-2026-11-13/power; O=$D/dc6-trial.txt; LV=${1:-2}; N=${2:-30}
rm -f $D/dc6-trial.done; echo "# $(date '+%F %T') 시작 DC 단계=$LV ${N}초" > $O
sudo -u user pmset displaysleepnow; sleep 12
echo "화면 끔: $(/usr/bin/python3 -I $D/dcstat.py | tail -1)" >> $O
echo "기준(DC 꺼짐): $(perl $D/psys.pl 10)  $(perl $P/cpustat.pl 1 >/dev/null 2>&1)" >> $O
sysctl -w debug.wexdc=$LV >> $O 2>&1; sleep 3
c=$(perl $P/cpustat.pl $N | awk '/PC8/{c=$2} /PC9/{d=$2} /PC10/{e=$2} /패키지/{w=$2} END{printf "PC8 %s PC9 %s PC10 %s pkg %sW", c,d,e,w}')
echo "DC 허용 ${N}초: $c | $(perl $D/psys.pl 5)" >> $O
echo "허용 중: $(/usr/bin/python3 -I $D/dcstat.py | tail -1)" >> $O
sysctl -w debug.wexdc=0 >> $O 2>&1; sleep 1
/usr/bin/python3 -I $D/dcstat.py >> $O 2>&1
sudo -u user caffeinate -u -t 3; sleep 8
echo "화면 켬 뒤: $(/usr/bin/python3 -I /Users/user/psr-analysis/psrstat.py | grep -E 'PIPECONF|엔진' | tr '\n' ' ')" >> $O
/usr/bin/log show --last 1m --predicate 'process == "kernel" AND (eventMessage CONTAINS "DBUF" OR eventMessage CONTAINS "link training" OR eventMessage CONTAINS "timeout")' --style compact 2>/dev/null | grep -v "log run" | tail -4 | cut -c1-160 >> $O
echo "# $(date '+%F %T') 끝" >> $O; chown user:staff $O; touch $D/dc6-trial.done; chown user:staff $D/dc6-trial.done
launchctl remove local.deepidle-dc6
