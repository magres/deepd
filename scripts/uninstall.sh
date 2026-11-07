#!/usr/bin/env bash
# deepd uninstaller — Linux/macOS side (calls the device-side script).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "$HERE/.." && pwd)"
IP="${1:-}"
# reuse install.sh for adb discovery and root handling
exec "$HERE/install.sh" "$IP" --uninstall
