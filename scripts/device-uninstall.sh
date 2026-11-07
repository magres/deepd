#!/system/bin/sh
# deepd device-side uninstaller: removes deepd, restores the previous
# hdmi_control_enabled value if the installer changed it. Runs as root.

set -e
LOG=/data/local/tmp/deepd-install.log
DAEMON=/system/bin/deepd.sh
CONF=/system/etc/deepd.conf
RC=/system/etc/init/deepd.rc

exec 2>>"$LOG"
set -x

mount -o remount,rw / 2>/dev/null || true
mount -o remount,rw /system 2>/dev/null || true

stop deepd 2>/dev/null || true
rm -f "$DAEMON" "$CONF" "$RC"

if [ -f /data/local/tmp/deepd-cec.bak ]; then
	prev=$(cat /data/local/tmp/deepd-cec.bak 2>/dev/null)
	if [ -n "$prev" ] && [ "$prev" != "null" ]; then
		settings put global hdmi_control_enabled "$prev"
	fi
	rm -f /data/local/tmp/deepd-cec.bak
fi

sync
echo UNINSTALL-OK
exit 0
