#!/bin/sh

TOOL=/usr/local/bin/hidpi-mode
LOG="$HOME/Library/Logs/hidpi-keep.log"
DELAY="${HIDPI_KEEP_DELAY:-20}"

say() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

[ -x "$TOOL" ] || { say "hidpi-mode 없음, 종료"; exit 0; }

sleep "$DELAY"

W=""; H=""; R=""
for f in "$HOME"/Library/Preferences/ByHost/com.apple.windowserver.*.plist; do
    case "$f" in *displays*) continue ;; esac
    [ -f "$f" ] || continue
    W=$(/usr/libexec/PlistBuddy -c "Print :DisplaySets:0:0:Width" "$f" 2>/dev/null)
    H=$(/usr/libexec/PlistBuddy -c "Print :DisplaySets:0:0:Height" "$f" 2>/dev/null)
    R=$(/usr/libexec/PlistBuddy -c "Print :DisplaySets:0:0:Resolution" "$f" 2>/dev/null)
    [ -n "$W" ] && break
done
if [ -z "$W" ] || [ -z "$H" ]; then
    f=/Library/Preferences/com.apple.windowserver.plist
    W=$(/usr/libexec/PlistBuddy -c "Print :DisplayAnyUserSets:0:0:Width" "$f" 2>/dev/null)
    H=$(/usr/libexec/PlistBuddy -c "Print :DisplayAnyUserSets:0:0:Height" "$f" 2>/dev/null)
    R=$(/usr/libexec/PlistBuddy -c "Print :DisplayAnyUserSets:0:0:Resolution" "$f" 2>/dev/null)
fi
case "$W$H" in ''|*[!0-9]*) W=1536; H=960; R=2 ;; esac
case "$R" in 2|2.*) KIND=HiDPI ;; *) KIND=1x ;; esac

norm() { awk '{ print $1, $3, ($4 == "HiDPI") ? "HiDPI" : "1x" }'; }

i=0
while [ $i -lt 12 ]; do
    LIST=$("$TOOL" 2>/dev/null)
    CUR=$(echo "$LIST" | grep -- '<- current' | norm)
    if [ "$CUR" = "$W $H $KIND" ]; then
        say "유지됨: $CUR"
        exit 0
    fi
    if echo "$LIST" | norm | grep -qx "$W $H $KIND"; then
        if [ "$KIND" = "HiDPI" ]; then OUT=$("$TOOL" "$W" "$H" 2>&1); else OUT=$("$TOOL" "$W" "$H" 1x 2>&1); fi
        say "현재 [$CUR] ≠ 저장값 [$W $H $KIND] → 재적용: $OUT"
        sleep 3
    else
        say "저장값 [$W $H $KIND] 모드가 아직 목록에 없음 (현재 [$CUR]), 대기"
        sleep 5
    fi
    i=$((i + 1))
done
say "포기: 저장값 [$W $H $KIND]을 적용하지 못함"
exit 0
