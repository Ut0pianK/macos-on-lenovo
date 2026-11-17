#!/bin/bash
D=~/deep-idle-analysis; P=~/tweak-backup-2026-11-13/power; : > $D/ab-poller.txt; rm -f $D/ab-poller.done
for s in pause run pause run; do
  if [ $s = pause ]; then touch ~/.alc-verb-pause; else rm -f ~/.alc-verb-pause; fi
  sleep 20
  c=$(perl $P/cpustat.pl 130 | awk '/PC8/{p8=$2} /PC2/{p2=$2} /패키지/{w=$2} END{printf "PC2 %s%% PC8 %s%% pkg %sW", p2, p8, w}')
  echo "$s: $c | 배터리 $(perl $P/w.pl | sed 's/.*inst=\([0-9.]*W\).*/\1/')" >> $D/ab-poller.txt
done
rm -f ~/.alc-verb-pause; touch $D/ab-poller.done
