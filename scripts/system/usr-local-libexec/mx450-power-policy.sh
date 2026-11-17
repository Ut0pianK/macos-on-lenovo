#!/bin/sh
E=/usr/local/etc/mx450
L=/Library/GPUBundles/nvmtl-allow.txt
LOG=/var/log/mx450-power-policy.log
D=/usr/local/etc/mx450/deny-system.txt
ST=/usr/local/etc/mx450/deny-static.txt
build_static() {
    { find /System/Library /usr/libexec /usr/sbin /Library/Apple -type f -perm -111 \( -path "*/Contents/MacOS/*" -o -path "/usr/libexec/*" -o -path "/usr/sbin/*" \) 2>/dev/null | sed "s#.*/##"
    } | sort -u > "$ST.all"
    ls /Applications /System/Applications /System/Applications/Utilities 2>/dev/null | sed -n "s/\.app$//p" | sort -u > "$ST.apps"
    comm -23 "$ST.all" "$ST.apps" | grep -vx WindowServer | sed "s/^/-/" > "$ST.tmp" && mv -f "$ST.tmp" "$ST"; rm -f "$ST.all" "$ST.apps"
    say "시스템 이름 목록 $(wc -l < "$ST" | tr -d " ")개"
}
release_xpc() {
    for p in $(ioreg -l -w0 -p IOService | grep -A3 IOAccelNVRMBridge | sed -n "s/.*IOUserClientCreator\" = \"pid \([0-9]*\),.*/\1/p" | sort -u); do
        c=$(ps -o comm= -p "$p" 2>/dev/null)
        case "$c" in /System/*/XPCServices/*|/System/Library/*/XPCServices/*) kill "$p" 2>/dev/null; sleep 2; kill -9 "$p" 2>/dev/null; say "MX450 놓게 함: $c (pid $p)";; esac
    done
}
say() { echo "$(date '+%F %T') $*" >> "$LOG"; }
trap 'say "종료"; exit 0' TERM INT
say "시작"
n=0; prev=
[ -s "$ST" ] || build_static
build_static >/dev/null 2>&1 &
build_ac() {
    if [ $((n % 12)) = 0 ] || [ ! -s "$D" ]; then
        { cat "$D" 2>/dev/null; cat "$ST" 2>/dev/null
          ps -Ao comm | grep -E '^/(System/Library|usr/|Library/Apple)' | sed 's#.*/##; s#^#-#'
          printf '%s\n' -loginwindow -CursorUIViewService -TextInputSwitcher -TextInputMenuAgent -Dock -ControlCenter -NotificationCenter -SystemUIServer -WindowManager -Spotlight
        } | grep -vx -- '-WindowServer' | grep -E '^-[^ ]+$' | sort -u > "$D.tmp" && mv -f "$D.tmp" "$D"
    fi
    if grep -qx '\*' "$E/allow-apps.txt" 2>/dev/null; then
        echo "# mx450-power-policy: 충전기 — 전부 허용(allow-apps.txt 의 *) + 시스템 프로세스 거부"
        cat "$D"
        cat "$E/allow-ac.txt"
    else
        echo "# mx450-power-policy: 충전기 — allow-apps.txt 에 적힌 앱만 (MX450 앱 관리)"
        grep -v '^[[:space:]]*#' "$E/allow-apps.txt" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^[-!*]' | grep -v '^$' | sort -u
    fi
}
while :; do
    mode=$(tr -cd 'a-z' < "$E/mode" 2>/dev/null)
    case "$mode" in on) want=ac;; off) want=battery;; *) mode=auto
        if pmset -g batt | head -1 | grep -q "AC Power"; then want=ac; else want=battery; fi;; esac
    t=/Library/GPUBundles/.nvmtl-allow.tmp
    if [ "$want" = ac ]; then build_ac > "$t"; else cat "$E/allow-battery.txt" > "$t"; fi
    if [ -s "$t" ] && [ -d /Library/GPUBundles ] && ! cmp -s "$t" "$L"; then
        if chown root:wheel "$t" && chmod 644 "$t" && mv -f "$t" "$L"; then
            say "허용 목록 → $want (모드 $mode, 거부 $(wc -l < "$D" | tr -d ' ')개)"
        else say "!! 허용 목록 교체 실패"; fi
    else rm -f "$t"; fi
    [ "$prev" = ac ] && [ "$want" = battery ] && release_xpc
    prev=$want
    n=$((n + 1))
    sleep 5 & wait $!
done
