#!/usr/bin/env python3
"""Reduce Infinity-X GApps to its core Pixel GMS product package.

The vendor/pixel/gms/products/gms.mk package set remains the upstream default,
but the optional Pixel ThemePicker and Sounds overlays are not inherited.
Idempotent: applied to the synced local checkout, not the upstream repository.
"""
from pathlib import Path
import sys

def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: trim-gapps.py <Android source root>", file=sys.stderr)
        return 2
    root = Path(sys.argv[1]).resolve()
    common = root / "vendor/infinity/config/common.mk"
    gms = root / "vendor/pixel/gms/products/gms.mk"
    if not gms.is_file() or not common.is_file():
        print("Missing Infinity common.mk or core GMS makefile", file=sys.stderr)
        return 1
    text = common.read_text()
    if "$(call inherit-product, vendor/pixel/gms/products/gms.mk)" not in text:
        print("Expected core Pixel GMS inherit-product not found", file=sys.stderr)
        return 1
    for path in ("vendor/pixel/themepicker/products/themepicker.mk",
                 "vendor/pixel/sounds/products/sounds.mk"):
        needle = "$(call inherit-product, " + path + ")"
        disabled = "# Pixel 3 reduced GApps: " + needle
        if needle in text and disabled not in text:
            # Only replace the entire makefile line, never part of another line.
            lines = text.splitlines(keepends=True)
            matches = [i for i, line in enumerate(lines) if line.strip() == needle]
            if len(matches) != 1:
                print(f"Expected one GApps inclusion for {path}, found {len(matches)}", file=sys.stderr)
                return 1
            lines[matches[0]] = disabled + "\n"
            text = "".join(lines)
        elif needle not in text:
            print(f"Cannot find required GApps inclusion: {path}", file=sys.stderr)
            return 1
    common.write_text(text)
    print("Pixel 3 reduced GApps enabled: upstream Pixel GMS retained; ThemePicker and Sounds excluded")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
