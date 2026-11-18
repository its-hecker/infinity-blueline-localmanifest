# Infinity-X Android 17 for Google Pixel 3 (blueline)

This port is rebased on the current **LineageOS 24.0 hardware sources**, not the
old experimental Infinity-X port. The three mirrors are intentionally replaced,
including deletion of old-only files. The only device-tree differences are
`AndroidProducts.mk` and the new `infinity_blueline.mk`, which is derived
from the original `lineage_blueline.mk` with ROM build-target substitution.
The kernel tree is a verbatim LineageOS snapshot. The vendor tree is a
LineageOS snapshot except for removing `.lfsconfig` so blobs can be stored on GitHub LFS.
GitHub workflow metadata is separate from ROM source.


The build helper applies an idempotent compatibility fix to Infinity-X's
`frameworks/av/camera/ICameraClient.cpp` for the legacy camera preview FD marker
(`0x100`) before compilation. This preserves Infinity-X's FD callback behavior
without modifying the LineageOS-derived device, kernel, or vendor mirrors.

## Exact LineageOS branch heads used
- Device: `its-hecker/android_device_google_crosshatch` `lineage-24.0` at `f30f51da5b8f9a50d031f409b96b5d4a2eb35d68`
- Kernel: `its-hecker/android_kernel_google_msm-4.9` `lineage-24.0` at `484dddd90e130900b4f0cf0ccb5b148b263f7fb4`
- Vendor: `its-hecker/proprietary_vendor_google_blueline` `lineage-24.0` at `21b4fe5e00a992900436c56821916f6a056550a6`

## Build

```bash
mkdir -p ~/infinityx-blueline
cd ~/infinityx-blueline
repo init --no-repo-verify --git-lfs -u https://github.com/ProjectInfinity-X/manifest.git -b 17 -g default,-mips,-darwin,-notdefault
git clone -b main https://github.com/its-hecker/infinity-blueline-localmanifest.git .repo/local_manifests
repo sync -c --fail-fast --no-clone-bundle --no-tags -j4
USE_RBE=true WITH_GAPPS=true PIXEL3_GAPPS_LITE=true PIXEL3_DEV_USB_ADB=true bash .repo/local_manifests/build.sh
```

GApps are **integrated**, using Infinity-X's `vendor/pixel/gms/products/gms.mk`
while the helper omits optional Pixel ThemePicker and Pixel Sounds. The core GMS
makefile may include more apps than Play Services and Play Store: this has not
yet been verified to be the smallest possible GApps set.
`WITH_GAPPS=false` builds without GApps.

The local manifest matches the LineageOS 24.0 build dependencies, including
the **same xbill9 system/core, vold, bpf, zygote and Connectivity forks**,
plus pinned legacy SDM845 audio, display, GPS and GNU kernel toolchains.
Those changes are boot-critical for the legacy Pixel 3 on Android 17.

`--check` checks preconditions; `--prepare-only` runs the vendor fixup and
the GApps trim without compilation. Userdebug is used for initial development.
The port keeps LineageOS's device init/USB setup unchanged; secure releases
must disable `PIXEL3_DEV_USB_ADB` and verify actual ro.adb.secure settings.

**Status:** source rebasing and GitHub CI validation do not demonstrate an
Infinity-X image compiles or boots. Test the phone, data decryption, camera,
Wi-Fi, telephony, and fixed legacy partition sizes before distributing.
