# Infinity-X Android 17 for Google Pixel 3 (blueline)

This port is rebased on the current **LineageOS 24.0 hardware sources**, not the
old experimental Infinity-X port. The three mirrors are intentionally replaced,
including deletion of old-only files. The only device-tree differences are
`AndroidProducts.mk` and the new `infinity_blueline.mk`, which is derived
from the original `lineage_blueline.mk` with ROM build-target substitution.
The kernel tree is now the LineageOS 24.0 boot baseline plus KernelSU Next manual hooks (no SUSFS). The vendor tree is a
LineageOS snapshot except for removing `.lfsconfig` so blobs can be stored on GitHub LFS.
GitHub workflow metadata is separate from ROM source.


The build helper applies an idempotent compatibility fix to Infinity-X's
`frameworks/av/camera/ICameraClient.cpp` for the legacy camera preview FD marker
(`0x100`) before compilation. This preserves Infinity-X's FD callback behavior
without modifying the LineageOS-derived device, kernel, or vendor mirrors.

The build helper also runs `scripts/prepare-camera-jni.py`, an idempotent
Android 17 compatibility fix for obsolete Qualcomm camera JNI fields and commands.
It guards optional extended face fields with C++20 detection (returning zero when
unavailable), and retains historical command IDs. It does not change the
camera_face_t ABI, device, kernel, vendor, or LineageOS boot dependencies.
The JNI patch is syntax-tested but the full ROM build and on-device behavior are unverified.

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
while the helper omits optional Pixel ThemePicker and Pixel Sounds. The GMS helper now removes optional Google app modules from makefiles while
retaining Play services, Play Store, framework, sign-in, sync and setup packages.
The Android 17 Pixel 3 retrofit super partition stays at its physical size:
4,072,669,184 bytes. Verify packaged partition image sizes in the build log:
the previous 4,562,857,984-byte image set was too large by 490,188,800 bytes.
No successful ROM build or boot test has been performed after this change.
KernelSU Next is checked out as a pinned kernel submodule during build.
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

## 2026-11-19 blueline Google-logo first-boot diagnostics

The Infinity-X Android 17 hardware trees were compared by Git blob SHA against
the proven LineageOS 24.0 baseline. Device hardware blobs are identical except
the Infinity product selection and CI; the proprietary vendor blobs are
identical; the kernel differs in KernelSU Next hooks/configuration. This does
NOT establish which change prevents boot without device-side logs.

**Use the diagnostic branch in this repository and the matching pinned device
commit in blueline.xml.** The built output remains Infinity-X. The first trial
uses the previously booted LineageOS kernel commit
`484dddd90e130900b4f0cf0ccb5b148b263f7fb4` instead of the modified
KernelSU kernel. This is an A/B kernel isolation test, not a confirmed boot fix.

```bash
# Existing Infinity-X source checkout:
cd ~/infinityx-blueline
git -C .repo/local_manifests fetch origin fix/blueline-firstboot-diagnostics-20261119
git -C .repo/local_manifests switch -C fix/blueline-firstboot-diagnostics-20261119 FETCH_HEAD
repo sync -c --fail-fast --no-clone-bundle --no-tags -j4

# To authorize just your development PC before Android UI starts, securely
# transfer that PC's ~/.android/adbkey.pub to ServerHive first.
# If that file is not supplied, USB debugging is still enabled but the
# normal on-screen computer authorization remains necessary.
PIXEL3_ADB_PUBLIC_KEY="$HOME/pixel3-adbkey.pub" \
PIXEL3_FIRSTBOOT_BASELINE=true \
INFINITY_BUILD_VARIANT=userdebug \
USE_RBE=true WITH_GAPPS=true PIXEL3_GAPPS_LITE=true PIXEL3_DEV_USB_ADB=true \
bash .repo/local_manifests/build.sh
```

The script copies only the *public* ADB key to
`out/hecker-adb/blueline.pub`. It will not modify the public GitHub
repository to contain your key. Keep the private `adbkey` on your computer.
`ro.adb.secure` stays enabled for userdebug; the included key authorizes
only a matching host. Without `PIXEL3_ADB_PUBLIC_KEY`, omit that environment
variable entirely and authorize normally once the UI is available. Do not
ship these diagnostics as a release ROM.

After a baseline-kernel first boot succeeds, test the normal KernelSU kernel:

```bash
cd ~/infinityx-blueline
PIXEL3_ADB_PUBLIC_KEY="$HOME/pixel3-adbkey.pub" \
PIXEL3_FIRSTBOOT_BASELINE=false \
INFINITY_BUILD_VARIANT=userdebug USE_RBE=true WITH_GAPPS=true \
PIXEL3_GAPPS_LITE=true PIXEL3_DEV_USB_ADB=true \
bash .repo/local_manifests/build.sh
```

The build helper detects switching between the pinned Lineage and KernelSU
kernel revisions and invalidates the cached kernel objects. If **both**
kernels stall before boot animation, repeat the baseline with
`WITH_GAPPS=false PIXEL3_GAPPS_LITE=false` to isolate GApps from core
Infinity-X userspace. Do not change or wipe the data partition just to
test kernel switching.

**Log collection:** Once Android exposes ADB:

```bash
bash .repo/local_manifests/scripts/collect-firstboot-logs.sh
```

The script collects all logcat buffers, dmesg, properties and pstore when
accessible. If it remains on the Google logo and `adb devices` shows
nothing, the boot has not reached a usable ADB stage: use a previously
working recovery boot to inspect `/sys/fs/pstore` and collect any
`console-ramoops` entries. ADB properties cannot help if init never
starts. If `adb devices` says `unauthorized`, confirm that the public key
used at build time matches the private ADB key on the USB-connected PC.

These changes have been source-reviewed but have not been compiled or tested
on physical hardware by the assistant.
