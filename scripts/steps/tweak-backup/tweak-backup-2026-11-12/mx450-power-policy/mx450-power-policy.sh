#!/bin/sh
E=/usr/local/etc/mx450
L=/Library/GPUBundles/nvmtl-allow.txt
LOG=/var/log/mx450-power-policy.log
say() { echo "$(date '+%F %T') $*" >> "$LOG"; }
trap 'say "종료"; exit 0' TERM INT
say "시작"
while :; do
    mode=$(tr -cd 'a-z' < "$E/mode" 2>/dev/null)
    case "$mode" in on) want=ac;; off) want=battery;; *) mode=auto
        if pmset -g batt | head -1 | grep -q "AC Power"; then want=ac; else want=battery; fi;; esac
    src="$E/allow-$want.txt"
    if [ -s "$src" ] && [ -d /Library/GPUBundles ] && ! cmp -s "$src" "$L"; then
        t=/Library/GPUBundles/.nvmtl-allow.tmp
        if cp "$src" "$t" && chown root:wheel "$t" && chmod 644 "$t" && mv -f "$t" "$L"; then
            say "허용 목록 → $want (모드 $mode)"
        else say "!! 허용 목록 교체 실패"; fi
    fi
    sleep 5 & wait $!
done
