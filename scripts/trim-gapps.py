#!/usr/bin/env python3
"""Build a deliberately small Pixel GMS product set for Infinity-X on blueline.

Keep Play services, Play Store, Google Services Framework, sign-in and setup.
Strip optional Google apps (Chrome, Photos, Maps, YouTube, Gmail, etc.) at
*product makefile* level instead of deleting files from generated images.
Never enlarge the Pixel 3's physical retrofit super partition.

Edits are deterministic and idempotent, local to the synced working tree.
"""
from __future__ import annotations

from pathlib import Path
import re
import sys

# Package/module prefixes vary between Pixel GMS vendor versions. Match
# essential services, their overlays and split packages, not optional apps.
CORE_PREFIXES = (
    "Phonesky",
    "PrebuiltGmsCore",
    "GmsCore",
    "GoogleServicesFramework",
    "GoogleLoginService",
    "GoogleOneTimeInitializer",
    "GooglePartnerSetup",
    "PartnerSetup",
    "AndroidPlatformServices",
    "GoogleExtServices",
    "ExtShared",
    "ConfigUpdater",
    "GoogleRestore",
    "GoogleContactsSyncAdapter",
    "GoogleCalendarSyncAdapter",
    "SetupWizard",
    "PixelSetupWizard",
    "GoogleSetupWizard",
    "GmsConfig",
    "GoogleConfig",
    "GoogleServicesFrameworkOverlay",
    "GooglePlayServices",
    "GoogleBackupTransport",
)
PACKAGE = re.compile(r"^[A-Za-z0-9_.+/-]+$")
ASSIGNMENT = re.compile(
    r"^(\s*)(PRODUCT_PACKAGES(?:_DEBUG)?)\s*(\+=|:=|=)\s*(.*?)\s*$"
)


def needed(package: str) -> bool:
    return any(package == core or package.startswith(core + "_")
               or package.startswith(core + ".")
               or package.startswith(core + "Overlay")
               or (core in ("PrebuiltGmsCore", "GmsCore")
                   and package.startswith(core))
               for core in CORE_PREFIXES)


def prune_makefile(path: Path) -> tuple[int, int]:
    original = path.read_text(encoding="utf-8")
    lines = original.splitlines(keepends=True)
    rewritten = []
    i = 0
    seen = removed = 0

    while i < len(lines):
        line = lines[i]
        match = ASSIGNMENT.match(line.rstrip("\r\n"))
        if not match:
            rewritten.append(line)
            i += 1
            continue

        # A PRODUCT_PACKAGES make assignment may span backslash lines.
        block = [line]
        i += 1
        while block[-1].rstrip().endswith("\\") and i < len(lines):
            block.append(lines[i])
            i += 1

        # Preserve complex make expressions and conditionals verbatim. It is
        # unsafe to tokenize $(call ...), $(foreach ...), etc. as package names.
        payload = " ".join(
            part.split("#", 1)[0].rstrip().rstrip("\\").strip()
            for part in [match.group(4)] + block[1:]
        )
        if "$" in payload:
            rewritten.extend(block)
            continue

        packages = payload.split()
        if not all(PACKAGE.fullmatch(p) for p in packages):
            rewritten.extend(block)
            continue
        seen += len(packages)
        kept = [p for p in packages if needed(p)]
        removed += len(packages) - len(kept)

        indent, variable, operator = match.group(1, 2, 3)
        if kept:
            rewritten.append(f"{indent}{variable} {operator} \\\n")
            for n, package in enumerate(kept):
                tail = " \\\n" if n + 1 < len(kept) else "\n"
                rewritten.append(f"{indent}    {package}{tail}")
        else:
            rewritten.append(f"{indent}{variable} {operator}\n")

    updated = "".join(rewritten)
    if updated != original:
        path.write_text(updated, encoding="utf-8")
    return seen, removed


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: trim-gapps.py <Android source root>", file=sys.stderr)
        return 2

    root = Path(sys.argv[1]).resolve()
    common = root / "vendor/infinity/config/common.mk"
    gms_root = root / "vendor/pixel/gms"
    gms = gms_root / "products/gms.mk"

    if not common.is_file() or not gms.is_file():
        print("Missing Infinity common.mk or Pixel GMS products/gms.mk",
              file=sys.stderr)
        return 1

    text = common.read_text(encoding="utf-8")
    required = "$(call inherit-product, vendor/pixel/gms/products/gms.mk)"
    if required not in text:
        print("Expected core Pixel GMS inheritance not found", file=sys.stderr)
        return 1

    for name in ("themepicker", "sounds"):
        needle = ("$(call inherit-product, "
                  f"vendor/pixel/{name}/products/{name}.mk)")
        disabled = f"# Pixel 3 minimal GApps: {needle}"
        matches = [n for n, line in enumerate(text.splitlines(keepends=True))
                   if line.strip() == needle]
        if matches:
            if len(matches) != 1:
                print(f"Unexpected repeated inclusion: {name}", file=sys.stderr)
                return 1
            fragments = text.splitlines(keepends=True)
            fragments[matches[0]] = disabled + "\n"
            text = "".join(fragments)
        elif disabled not in text:
            # Optional products are not necessarily inherited by every
            # Infinity-X revision. Their absence already satisfies the
            # minimal GApps requirement; it is not a build failure.
            print(f"Optional Pixel {name} inclusion already absent; skipping.")
    common.write_text(text, encoding="utf-8")

    mk_files = sorted(gms_root.rglob("*.mk"))
    if not mk_files:
        print("No Pixel GMS makefiles found", file=sys.stderr)
        return 1

    # Check before modifying: the vendor tree must expose the actual Play Store
    # and Play services make modules. Do not silently ship a GApps-less build.
    packages_source = "\n".join(p.read_text(encoding="utf-8")
                                for p in mk_files)
    if not any(p in packages_source for p in
               ("Phonesky", "GoogleServicesFramework", "PrebuiltGmsCore",
                "GmsCore")):
        print("Cannot identify mandatory GMS packages; refusing to strip",
              file=sys.stderr)
        return 1

    total, removed = 0, 0
    for path in mk_files:
        seen, skipped = prune_makefile(path)
        total += seen
        removed += skipped

    if total == 0:
        print("No simple PRODUCT_PACKAGES declarations found in Pixel GMS; "
              "cannot guarantee minimal build", file=sys.stderr)
        return 1

    print(f"Pixel 3 minimal GApps: considered {total} modules, "
          f"removed {removed} optional modules; core GMS preserved.")
    print("Pixel 3 retrofit super limit is unchanged: 4,072,669,184 bytes. "
          "Actual image sizes must still be validated during the build.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
