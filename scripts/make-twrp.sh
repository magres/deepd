#!/usr/bin/env bash
# Builds TWRP flashable zips into dist/:
#   deepd-twrp-install-amlogic-android5-9-<TAG>.zip
#   deepd-twrp-uninstall-amlogic-android5-9-<TAG>.zip
# Usage: make-twrp.sh [TAG]   (TAG default: ${TAG:-dev})
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "$HERE/.." && pwd)"
TAG="${1:-${TAG:-dev}}"
DIST="$TOP/dist"
RECOVERY="$TOP/twrp/META-INF/com/google/android"

command -v zip >/dev/null || { echo "zip not found"; exit 1; }
command -v unzip >/dev/null || { echo "unzip not found"; exit 1; }

rm -rf "$DIST"
mkdir -p "$DIST"

build_zip() {
    name=$1
    out=$2
    stage="$(mktemp -d)"
    mkdir -p "$stage/META-INF/com/google/android"
    if [ "$name" = install ]; then
        cp "$RECOVERY/update-binary" "$stage/META-INF/com/google/android/update-binary"
        cp "$RECOVERY/updater-script" "$stage/META-INF/com/google/android/updater-script"
        cp "$TOP/deepd.sh" "$TOP/deepd.conf" "$TOP/deepd.rc" "$stage/"
    else
        cp "$RECOVERY/uninstall-update-binary" "$stage/META-INF/com/google/android/update-binary"
        cp "$RECOVERY/updater-script" "$stage/META-INF/com/google/android/updater-script"
    fi
    (cd "$stage" && zip -qr "$out" .)
    rm -rf "$stage"
    echo "built: $out"
}

build_zip install   "$DIST/deepd-twrp-install-amlogic-android5-9-$TAG.zip"
build_zip uninstall "$DIST/deepd-twrp-uninstall-amlogic-android5-9-$TAG.zip"
ls -l "$DIST"
