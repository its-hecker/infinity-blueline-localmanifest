# Project Infinity-X Android 17 — Pixel 3 (blueline)

Unofficial Infinity-X device port by Hecker, based on the LineageOS 24.0
Pixel 3 hardware configuration which has booted successfully.

## Source repositories
- [Device tree](https://github.com/its-hecker/infinity-blueline-devicetree)
- [Kernel](https://github.com/its-hecker/infinity-blueline-kernel)
- [Vendor](https://github.com/its-hecker/infinity-blueline-vendor)
- [Local manifest](https://github.com/its-hecker/infinity-blueline-localmanifest)

The three source repositories use automated GitHub Actions importers to copy
the known LineageOS-based Infinity-X port. Verify they have imported actual
source files before starting a sync. The imported trees preserve the existing
Pixel 3 Android 17 SELinux, legacy gralloc, Citadel and compatibility changes.

## New ServerHive checkout

```bash
mkdir -p ~/infinityx-blueline
cd ~/infinityx-blueline
repo init --no-repo-verify --git-lfs -u https://github.com/ProjectInfinity-X/manifest.git -b 17 -g default,-mips,-darwin,-notdefault
git clone -b main https://github.com/its-hecker/infinity-blueline-localmanifest.git .repo/local_manifests
repo sync -c --fail-fast --no-clone-bundle --no-tags -j4
USE_RBE=true WITH_GAPPS=true PIXEL3_GAPPS_LITE=true PIXEL3_DEV_USB_ADB=true bash .repo/local_manifests/build.sh
```

This produces an integrated-GApps ROM, not a separate GApps ZIP. The reduced
profile omits optional Pixel ThemePicker and Sounds makefile includes but keeps
the upstream vendor/pixel/gms/products/gms.mk. **It is not a bare Play
Services + Play Store bundle:** upstream GMS may include additional Pixel apps
and its final image size must be checked before flashing. Full upstream GApps:
set `PIXEL3_GAPPS_LITE=false`. Vanilla: `WITH_GAPPS=false`.

Run `bash .repo/local_manifests/build.sh --check` to verify paths after sync.
`--prepare-only` applies the already proven vendor fixups and reduces GApps,
without running a build. The script checks the generated kernel SELinux
configuration, Qualcomm HWC packaging, and uevent permissions.

Development builds default to early root USB ADB to capture boot failures.
**Do not distribute with `PIXEL3_DEV_USB_ADB=true`.** Set it to false for
secure userdebug builds; avoid reusing this debug product unchanged for a
public release.

Booting LineageOS does not establish that Infinity-X boots. The combined ROM,
Google services, file-based encryption, first boot, Wi-Fi, calls, camera and
partition size must still be verified on the Pixel 3.

Credits: Project Infinity-X, LineageOS, Google device maintainers, xbill9.
