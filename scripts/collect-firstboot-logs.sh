#!/usr/bin/env bash
# Collect first-boot information once Infinity-X exposes an authenticated ADB.
# Run on the computer whose public ADB key was included in the test build.
set -u -o pipefail

if ! command -v adb >/dev/null 2>&1; then
    echo "Android platform-tools (adb) is required" >&2
    exit 2
fi
STAMP=$(date -u +%Y%m%d-%H%M%S)
DEST=${1:-"$HOME/infinity-blueline-firstboot-$STAMP"}
mkdir -p "$DEST"

adb devices -l > "$DEST/adb-devices.txt"
if ! timeout 8 adb get-state >/dev/null 2>&1; then
    cat "$DEST/adb-devices.txt"
    echo "ADB is not accessible. If the phone stops at the Google logo before"
    echo "adbd/USB initialization, use recovery to inspect persistent console"
    echo "logs under /sys/fs/pstore instead; ADB settings cannot fix that stage."
    exit 3
fi

adb shell getprop > "$DEST/properties.txt" 2>&1 || true
adb logcat -b all -d -v threadtime > "$DEST/logcat-all.txt" 2>&1 || true
adb shell dmesg > "$DEST/dmesg.txt" 2>&1 || true
adb shell 'cat /proc/last_kmsg' > "$DEST/last-kmsg.txt" 2>&1 || true

# Authorized userdebug builds can usually restart adbd as root.
adb root > "$DEST/adb-root.txt" 2>&1 || true
if timeout 12 adb wait-for-device >/dev/null 2>&1; then
    adb pull /sys/fs/pstore "$DEST/pstore" > "$DEST/pstore-pull.txt" 2>&1 || true
fi

printf 'Collected diagnostics into %s\n' "$DEST"
echo "Please share logcat-all.txt, dmesg.txt, properties.txt, and any pstore files."
