#!/usr/bin/env bash
# deepd installer — Linux/macOS side.
#   ./install.sh 192.168.88.8            install (reboots the box at the end)
#   ./install.sh 192.168.88.8 --uninstall
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "$HERE/.." && pwd)"

ARGS=(); ACTION=install
while [ $# -gt 0 ]; do
	case "$1" in
		--uninstall) ACTION=uninstall ;;
		*) ARGS+=("$1") ;;
	esac
	shift
done
IP="${ARGS[0]:-}"
[ -n "$IP" ] || { echo "usage: ./install.sh <android-box-ip> [--uninstall]"; exit 2; }
case "$IP" in *:*) ;; *) IP="$IP:5555";; esac

ADB=""
for cand in "$TOP/platform-tools/adb" "$TOP/platform-tools/adb.exe" "$(command -v adb || true)"; do
	if [ -n "$cand" ] && [ -x "$cand" ]; then ADB="$cand"; break; fi
done
[ -n "$ADB" ] || {
	echo "adb not found."
	echo "  Скачать platform-tools (Google): https://developer.android.com/tools/releases/platform-tools"
	echo "  Распакуйте так, чтобы внутри папки репо была platform-tools/adb, или добавьте adb в PATH."
	exit 1
}
echo "== using adb: $ADB"

echo "== connecting to $IP ..."
"$ADB" connect "$IP" || true
sleep 1
"$ADB" connect "$IP" || true
"$ADB" devices | tail -3

SU=""
if ! "$ADB" shell id -u 2>/dev/null | grep -q 0; then
	if "$ADB" shell su -c 'id -u' 2>/dev/null | grep -q 0; then
		SU="su -c "
	else
		echo "ERROR: no root access from ADB."
		echo "  deepd needs root (adb root or a ROM with su)."
		exit 1
	fi
fi

R="/data/local/tmp/deepd-installer"
"$ADB" shell mkdir -p "$R" >/dev/null 2>&1 || true
for f in deepd.sh deepd.conf deepd.rc device-install.sh device-uninstall.sh; do
	src="$TOP/$f"
	[ -f "$src" ] || src="$TOP/scripts/$f"
	"$ADB" push "$src" "$R/$f" >/dev/null
done
echo "== payload staged on device ($R)"

case "$ACTION" in
	install)
		echo "== installing..."
		"$ADB" shell ${SU}sh "$R/device-install.sh"
		echo "== rebooting (deepd will autostart; watch \$LOG for 'started')"
		"$ADB" shell ${SU}sync
		"$ADB" reboot || "$ADB" shell ${SU}reboot
		;;
	uninstall)
		echo "== uninstalling"
		"$ADB" shell ${SU}sh "$R/device-uninstall.sh"
		echo "== rebooting"
		"$ADB" shell ${SU}sync
		"$ADB" reboot || "$ADB" shell ${SU}reboot
		;;
esac
echo "DONE."
