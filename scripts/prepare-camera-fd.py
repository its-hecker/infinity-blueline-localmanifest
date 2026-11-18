#!/usr/bin/env python3
"""Keep Infinity-X's legacy camera preview-FD Binder path compiling on Android 17.

Infinity-X frameworks/av still uses CAMERA_FRAME_DATA_FD, a legacy enum value
(0x100) that is not declared in the current camera headers. Keep the original
file-descriptor marshalling logic intact, with a translation-unit-local marker.
This is an idempotent preparation step, not a device/vendor source change.
"""

from pathlib import Path
import sys


OLD_CONDITION = "ext1 == CAMERA_FRAME_DATA_FD"
NEW_CONDITION = "ext1 == kLegacyCameraFrameDataFd"
DECLARATION = "constexpr int32_t kLegacyCameraFrameDataFd = 0x100;"
NAMESPACE_ANCHOR = "namespace android {\nnamespace hardware {\n"


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: prepare-camera-fd.py <android-source-root>", file=sys.stderr)
        return 2

    source = Path(sys.argv[1]) / "frameworks/av/camera/ICameraClient.cpp"
    if not source.is_file():
        print(f"Missing Infinity-X camera source: {source}", file=sys.stderr)
        return 1

    original = source.read_text(encoding="utf-8")
    if DECLARATION in original:
        if original.count(NEW_CONDITION) != 2 or OLD_CONDITION in original:
            print("Camera compatibility fix is partially applied; inspect source.", file=sys.stderr)
            return 1
        print("Infinity-X camera FD compatibility: already applied")
        return 0

    count = original.count(OLD_CONDITION)
    if count == 0 and NEW_CONDITION not in original:
        print("Infinity-X camera FD compatibility: no legacy references; nothing to patch")
        return 0
    if count != 2 or NEW_CONDITION in original or original.count(NAMESPACE_ANCHOR) != 1:
        print("Unexpected Infinity-X camera source; refusing an unsafe patch.", file=sys.stderr)
        return 1

    addition = (
        NAMESPACE_ANCHOR
        + "\n// Legacy Qualcomm preview callback marker: ext2 carries a file descriptor.\n"
        + DECLARATION + "\n"
    )
    patched = original.replace(NAMESPACE_ANCHOR, addition, 1)
    patched = patched.replace(OLD_CONDITION, NEW_CONDITION)
    if patched.count(NEW_CONDITION) != 2 or patched.count(DECLARATION) != 1:
        print("Camera compatibility validation failed; source not modified.", file=sys.stderr)
        return 1

    source.write_text(patched, encoding="utf-8")
    print("Infinity-X camera FD compatibility: restored legacy 0x100 marker")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
