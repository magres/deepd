#!/system/bin/sh
# deepd device-side installer. Runs as root on the box (invoked from a
# PC by scripts/install.sh via: sh /data/local/tmp/deepd-installer/device-install.sh)
#
# Expects the payload in /data/local/tmp/deepd-installer/:
#   deepd.sh           daemon script
#   deepd.conf         configuration
#   deepd.rc           init service definition
#
# Installs:
#   /system/bin/deepd.sh
#   /system/etc/deepd.conf
#   /system/etc/init/deepd.rc
#
# Also flips `settings put global hdmi_control_enabled 1` (HDMI-CEC in
# the framework) after saving the previous value for uninstall. Some
# firmwares ship with CEC disabled, which disables sleep-on-TV-standby.
# The previous value is stored in /data/local/tmp/deepd-cec.bak.
#
# Everything is reversible; nothing is modified but the files above
# plus the global setting.

set -e
SRC=/data/local/tmp/deepd-installer
LOG=/data/local/tmp/deepd-install.log
DAEMON=/system/bin/deepd.sh
CONF=/system/etc/deepd.conf
RC=/system/etc/init/deepd.rc

exec 2>>"$LOG"
set -x

mount -o remount,rw / 2>/dev/null || true
mount -o remount,rw /system 2>/dev/null || true

[ -f "$SRC/deepd.sh" ]  || { echo "ERROR: payload missing (deepd.sh)";  exit 1; }
[ -f "$SRC/deepd.conf" ] || { echo "ERROR: payload missing (conf)";     exit 1; }
[ -f "$SRC/deepd.rc" ]  || { echo "ERROR: payload missing (rc)";        exit 1; }

grep -qw mem /sys/power/state 2>/dev/null || {
	echo "ERROR: this kernel does not offer 'mem' in /sys/power/state;"
	echo "       deep suspend is not supported on this device."
	exit 1
}

stop deepd 2>/dev/null || true

cp "$SRC/deepd.sh" "$DAEMON"
chmod 755 "$DAEMON"
chown root:shell "$DAEMON" 2>/dev/null || true

cp "$SRC/deepd.conf" "$CONF"
chmod 644 "$CONF"
chown root:root "$CONF" 2>/dev/null || true

cp "$SRC/deepd.rc" "$RC"
chmod 644 "$RC"
chown root:root "$RC" 2>/dev/null || true

# framework HDMI-CEC master switch (backup the old value)
CECPREV=$(settings get global hdmi_control_enabled 2>/dev/null)
if [ "$CECPREV" != "1" ]; then
	echo "$CECPREV" > /data/local/tmp/deepd-cec.bak 2>/dev/null || true
	settings put global hdmi_control_enabled 1
	echo "NOTE: hdmi_control_enabled was '$CECPREV', set to 1 (needed for CEC sleep)"
fi

sync
echo INSTALL-OK
exit 0
