#!/bin/sh

LOG=/var/log/turbo-ac.log
MARK=/var/db/turbo-off.pending
K=/Library/Extensions/DisableTurboBoost.kext
ID=com.rugarciap.DisableTurboBoost
CONF=/usr/local/etc/turbo-ac.conf
TEMP=/usr/local/bin/cputemp
POLL=5

log() { echo "$(/bin/date '+%F %T') $*" >> "$LOG"; }
loaded() { /usr/bin/kmutil showloaded 2>/dev/null | /usr/bin/grep -q "$ID"; }
on_ac() {
    /usr/sbin/ioreg -r -n AppleSmartBattery -d 1 2>/dev/null |
        /usr/bin/grep -q '"ExternalConnected" = Yes'
}
conf() {
    v=$(/usr/bin/sed -n "s/^$1=\([0-9][0-9]*\).*/\1/p" "$CONF" 2>/dev/null | /usr/bin/head -1)
    case "$v" in ''|*[!0-9]*) v=$2;; esac
    [ "$v" -lt "$3" ] && v=$3; [ "$v" -gt "$4" ] && v=$4
    echo "$v"
}
turbo_off() {
    if loaded; then log "$1 -> turbo OFF (already)"; return; fi
    /usr/bin/touch "$MARK"; /bin/sync
    out=$(/usr/bin/kmutil load -p "$K" 2>&1); rc=$?
    /bin/sleep 2
    /bin/rm -f "$MARK"; /bin/sync
    log "$1 -> turbo OFF (load rc=$rc ${out})"
}
turbo_on() {
    if loaded; then
        out=$(/usr/bin/kmutil unload -b "$ID" 2>&1); rc=$?
        log "$1 -> turbo ON (unload rc=$rc ${out})"
    else log "$1 -> turbo ON (already)"; fi
}

if [ -f "$MARK" ]; then
    log "previous load did not finish (crash?) -> doing nothing. remove $MARK to retry"
    exit 0
fi

log "started (pid $$)"
last=""
hot=0
hotn=0; cooln=0; held=0
while :; do
    HOT=$(conf HOT 65 50 95); COOL=$(conf COOL 55 40 90); HOLD=$(conf HOLD 300 30 3600)
    HOT_SEC=$(conf HOT_SEC 20 5 600); COOL_SEC=$(conf COOL_SEC 60 5 1800)
    [ "$COOL" -ge "$HOT" ] && COOL=$((HOT - 5))
    if [ "$(conf ALWAYS_OFF 0 0 1)" = 1 ]; then
        want=off; why="always-off"; hot=0; hotn=0
    elif on_ac; then
        t=$("$TEMP" 2>/dev/null); case "$t" in ''|*[!0-9]*) t=0;; esac
        if [ "$hot" = 0 ]; then
            if [ "$t" -ge "$HOT" ]; then hotn=$((hotn + POLL)); else hotn=0; fi
            if [ "$hotn" -ge "$HOT_SEC" ]; then hot=1; held=0; cooln=0; why="AC ${t}C >= ${HOT}C"; fi
        else
            held=$((held + POLL))
            if [ "$t" -gt 0 ] && [ "$t" -le "$COOL" ]; then cooln=$((cooln + POLL)); else cooln=0; fi
            if [ "$held" -ge "$HOLD" ] && [ "$cooln" -ge "$COOL_SEC" ]; then hot=0; hotn=0; why="AC ${t}C <= ${COOL}C"; fi
        fi
        if [ "$hot" = 1 ]; then want=off; else want=on; [ -z "${why:-}" ] && why="AC"; fi
    else
        want=off; why="battery"; hot=0; hotn=0
    fi
    if [ "$want" != "$last" ]; then
        if [ "$want" = on ]; then turbo_on "$why"; else turbo_off "$why"; fi
        last=$want
    fi
    why=""
    /bin/sleep "$POLL"
done
