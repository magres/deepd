#!/system/bin/sh
# deepd — deep sleep for Amlogic Android TV box.
#
# The firmware's sleep path leaves the SoC awake: on this class of
# boxes "sleep" only suspends the display, USB and CEC (early suspend),
# while the CPU stays live, the front panel keeps showing and adb/Wi-Fi
# keep serving. This daemon waits for the Android framework to go
# asleep on its own (CEC standby, power key, sleep timeout...) and then
# triggers a real suspend-to-RAM: `echo mem > /sys/power/state`.
# After the kernel resumes, it wakes the framework back with
# KEYCODE_WAKEUP, so button / network / remote wakes always show the UI.
#
# Optional "TV-off watchdog": if the box is awake while the TV reports
# no HDMI signal (HPD down) for tv_off_grace seconds, put the framework
# back to sleep. Useful with air-mouse remotes whose gyro bursts wake
# the box the moment TV power is toggled; disabled by default because
# "TV is off" detection is TV-model-specific (HPD must actually drop).
#
# Runs as root from an init service (see deepd.rc). Optional settings
# are read from /system/etc/deepd.conf; the daemon pauses while
# /data/local/tmp/deepd.pause exists.

LOG=/data/local/tmp/deepd.log
CONF=/system/etc/deepd.conf
PAUSE=/data/local/tmp/deepd.pause

conf() {
    grep -E "^[[:space:]]*$1[[:space:]]*=" "$CONF" 2>/dev/null | head -1 |
        sed 's/^[^=]*=//' | tr -d "'\"[:space:]"
}

int_or() {
    # int_or DEFAULT VALUE -> returns DEFAULT unless VALUE is a plain number
    case "$2" in
        ""|*[!0-9]*) echo "$1" ;;
        *) echo "$2" ;;
    esac
}

GRACE=$(int_or 6 "$(conf grace)")
COOLDOWN=$(int_or 20 "$(conf cooldown)")
TV_OFF_GRACE=$(int_or 0 "$(conf tv_off_grace)")
HPD=$(conf hpd_state_path)
DEBUG=$(int_or 0 "$(conf debug)")

log() {
    echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"
}

dbg() {
    [ "$DEBUG" = "1" ] && log "$*"
    return 0
}

is_asleep() {
    dumpsys power 2>/dev/null | grep -q "mWakefulness=Asleep"
}

hpd_state() {
    [ -n "$HPD" ] && [ -r "$HPD" ] && cat "$HPD" 2>/dev/null | tr -d '[:space:]'
}

log "start"
log "mem available in /sys/power/state?"
grep -qw mem /sys/power/state 2>/dev/null || { log "no mem suspend support, exiting"; exit 1; }
log "grace=${GRACE}s cooldown=${COOLDOWN}s tv_off_grace=${TV_OFF_GRACE}s hpd=$HPD"

cool_until=0
tv_off_since=0

while :; do
    sleep "$GRACE"
    [ -e "$PAUSE" ] && continue

    if is_asleep; then
        now=$(date +%s)
        if [ "$now" -lt "$cool_until" ]; then
            continue
        fi
        log "framework asleep -> suspend to mem"
        echo mem > /sys/power/state 2>/dev/null
        log "resumed"
        # wake the framework explicitly so button/network wakes show the UI
        input keyevent 224 2>/dev/null
        cool_until=$(( $(date +%s) + COOLDOWN ))
        continue
    fi

    # TV-off watchdog (optional, TV-model-specific — see deepd.conf)
    if [ "$TV_OFF_GRACE" -gt 0 ] 2>/dev/null; then
        me=$(date +%s)
        dbg "tick: awake, hpd=$(hpd_state)"
        if [ "$(hpd_state)" = "0" ]; then
            # back-date the first detection so the sleep happens as soon
            # as the triggering input burst (air-mouse press) is over
            [ "$tv_off_since" = "0" ] && tv_off_since=$(( me - TV_OFF_GRACE ))
            if [ $(( me - tv_off_since )) -ge "$TV_OFF_GRACE" ]; then
                log "TV off (hpd=0) for ${TV_OFF_GRACE}s, box awake -> SLEEP"
                input keyevent 223 2>/dev/null
                tv_off_since=0
            fi
        else
            tv_off_since=0
        fi
    fi
done
