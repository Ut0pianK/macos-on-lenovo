#!/bin/sh

LOG=/var/log/lid-shutdown.log
TESTFLAG=/var/run/lid-shutdown.test
POLL=2
CLOSED_POLLS=2
FORCE_AFTER=20

log() { echo "$(/bin/date '+%F %T') $*" >> "$LOG"; }

lid() {
    /usr/sbin/ioreg -r -k AppleClamshellState -d 1 2>/dev/null |
        /usr/bin/awk -F'= ' '/"AppleClamshellState"/ {print $2; exit}'
}

send() {
    u=$(/usr/bin/stat -f %Su /dev/console 2>/dev/null)
    uid=$(/usr/bin/id -u "$u" 2>/dev/null)
    [ -n "$uid" ] && [ "$uid" -ge 500 ] || return 99
    /bin/launchctl asuser "$uid" /usr/bin/sudo -u "$u" /usr/bin/osascript \
        -e "tell application \"loginwindow\" to «event aevt$1»"
}

log "started (pid $$)"
seen_open=0
closed=0

while :; do
    if [ -f "$TESTFLAG" ]; then
        /bin/rm -f "$TESTFLAG"
        out=$(send oapp 2>&1); rc=$?
        log "test event: rc=$rc ${out}"
    fi

    case "$(lid)" in
        No)  seen_open=1; closed=0 ;;
        Yes) [ "$seen_open" = 1 ] && closed=$((closed + 1)) ;;
    esac

    if [ "$closed" -ge "$CLOSED_POLLS" ]; then
        log "lid closed -> requesting shutdown"
        out=$(send shut 2>&1); rc=$?
        if [ "$rc" -ne 0 ]; then
            log "graceful request failed (rc=$rc ${out}) -> shutdown -h now"
            /sbin/shutdown -h now
        fi
        waited=0
        reopened=0
        while [ "$waited" -lt "$FORCE_AFTER" ]; do
            /bin/sleep "$POLL"
            waited=$((waited + POLL))
            if [ "$(lid)" = "No" ]; then reopened=1; break; fi
        done
        if [ "$reopened" = 0 ]; then
            log "still running after ${FORCE_AFTER}s with lid closed -> shutdown -h now"
            /sbin/shutdown -h now
        else
            log "lid reopened; not forcing"
        fi
        closed=0
    fi

    /bin/sleep "$POLL"
done
