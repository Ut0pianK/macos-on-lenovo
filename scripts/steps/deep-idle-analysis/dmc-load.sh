#!/bin/bash
D=/Users/user/deep-idle-analysis; O=$D/dmc-load.txt
echo "# $(date '+%F %T')" > $O
echo "전: $(/usr/bin/python3 -I /Users/user/psr-analysis/psrstat.py | grep '엔진')" >> $O
sysctl -w debug.wexdmc=1 >> $O 2>&1; sleep 2
/usr/bin/python3 -I $D/dcstat.py >> $O 2>&1
echo "후: $(/usr/bin/python3 -I /Users/user/psr-analysis/psrstat.py | grep '엔진')" >> $O
sleep 20; echo "20초 뒤: $(/usr/bin/python3 -I $D/dcstat.py | tail -1)" >> $O
chown user:staff $O
