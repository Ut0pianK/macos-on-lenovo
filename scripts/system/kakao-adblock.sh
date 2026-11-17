#!/bin/bash
set -u
H=/etc/hosts; BK=/etc/hosts.backup-20261114-kakao; TAG="# kakao-adblock"
[ "$(id -u)" = 0 ] || { echo "root 필요"; exit 1; }
strip() { grep -v "$TAG" $H > $H.tmp && cat $H.tmp > $H; rm -f $H.tmp; }
case "${1:-}" in
apply)
  [ -e $BK ] || cp -p $H $BK || exit 1
  strip
  for h in serv.ds.kakao.com display.ad.daum.net; do printf '0.0.0.0 %s %s\n::      %s %s\n' $h "$TAG" $h "$TAG" >> $H; done ;;
undo) strip ;;
*) echo "사용법: $0 apply|undo"; exit 1;;
esac
dscacheutil -flushcache; killall -HUP mDNSResponder 2>/dev/null
echo "hosts: $(grep -c "$TAG" $H) 줄"; exit 0
