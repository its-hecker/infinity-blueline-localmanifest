#!/usr/bin/env bash
# Experimental Project Infinity-X 17 / Android 17 Pixel 3 (blueline) build.
set -eo pipefail
ROOT=$(pwd -P)
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
MODE=${1:-build}
case "$MODE" in
  build|--check|--prepare-only) ;;
  *) echo "Usage: bash .repo/local_manifests/build.sh [--check|--prepare-only]" >&2; exit 2 ;;
esac
# Build with Google services integrated, without optional Pixel Sounds/ThemePicker.
# The core Pixel GMS source still contains its upstream app selection.
export WITH_GAPPS=${WITH_GAPPS:-true}
export PIXEL3_GAPPS_LITE=${PIXEL3_GAPPS_LITE:-true}
export PIXEL3_DEV_USB_ADB=${PIXEL3_DEV_USB_ADB:-true}
export PIXEL3_ENABLE_LIVEDISPLAY=${PIXEL3_ENABLE_LIVEDISPLAY:-false}
case "$WITH_GAPPS" in true|false) ;; *) echo "WITH_GAPPS must be true or false" >&2; exit 2 ;; esac
case "$PIXEL3_GAPPS_LITE" in true|false) ;; *) echo "PIXEL3_GAPPS_LITE must be true or false" >&2; exit 2 ;; esac
case "$PIXEL3_DEV_USB_ADB" in true|false) ;; *) echo "PIXEL3_DEV_USB_ADB must be true or false" >&2; exit 2 ;; esac
case "$PIXEL3_ENABLE_LIVEDISPLAY" in true|false) ;; *) echo "PIXEL3_ENABLE_LIVEDISPLAY must be true or false" >&2; exit 2 ;; esac
echo "Pixel 3 build options: GApps=$WITH_GAPPS; reduced extras=$PIXEL3_GAPPS_LITE; developer ADB=$PIXEL3_DEV_USB_ADB; LiveDisplay=$PIXEL3_ENABLE_LIVEDISPLAY"

if [[ ! -f build/envsetup.sh ]]; then
  echo "Run from the root of your Infinity-X 17 checkout." >&2
  exit 1
fi
required=(
  device/google/crosshatch/infinity_blueline.mk
  device/google/crosshatch/blueline/extract-files.py
  device/google/crosshatch/development/adb.mk
  vendor/google/blueline/blueline-vendor.mk
  vendor/infinity/config/common_full_phone.mk
  kernel/google/msm-4.9/Makefile
  hardware/qcom/audio/Android.bp
  hardware/qcom/sdm845/display/Android.bp
  hardware/qcom/sdm845/gps/Android.bp
  tools/extract-utils/extract_utils/main.py
  prebuilts/extract-tools/linux-x86/bin/patchelf-0_18
  prebuilts/clang/kernel/linux-x86/clang-r416183b/bin/clang
  prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-ld.gold
  prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-ld
)
missing=0
for file in "${required[@]}"; do
  if [[ ! -f "$file" ]]; then echo "Missing source/tool: $file" >&2; missing=1; fi
done
if [[ "$WITH_GAPPS" == true ]]; then
  for file in \
    vendor/pixel/gms/products/gms.mk \
    vendor/pixel/themepicker/products/themepicker.mk \
    vendor/pixel/sounds/products/sounds.mk; do
    if [[ ! -f "$file" ]]; then echo "GApps tree missing: $file" >&2; missing=1; fi
  done
fi
# Runtime prerequisites found in our recent LineageOS Pixel 3 bootlogs.
grep -Fq '/etc/ueventd.rc' device/google/crosshatch/device.mk || {
  echo "Missing Android 17 loaded ueventd path; Citadel will fail." >&2; missing=1;
}
grep -Fq '$(call soong_config_set_bool,libui,legacy_gralloc,true)' device/google/crosshatch/device-lineage.mk || {
  echo "Missing the legacy mapper from the bootable Pixel 3 baseline." >&2; missing=1;
}
if grep -Fq 'ro.hardware.hwcomposer=qcom' device/google/crosshatch/device.mk; then
  echo "Unexpected post-first-boot HWC selector in rollback source." >&2; missing=1;
fi
if grep -Fq 'on property:bpf.progs_loaded=1' device/google/crosshatch/init.hardware.rc; then
  echo "Unexpected post-first-boot netd startup override in rollback source." >&2; missing=1;
fi
grep -Fq 'installKeyLegacy' system/vold/KeyUtil.cpp || {
  echo "Missing Linux 4.9 fscrypt keyring fallback in system/vold." >&2; missing=1;
}
if (( missing )); then echo "Fix Pixel 3 source preflight before building." >&2; exit 1; fi
if [[ "$MODE" == "--check" ]]; then
  echo "Infinity-X Pixel 3 build inputs found. Compilation/boot NOT verified."
  exit 0
fi

python3 "$SCRIPT_DIR/scripts/prepare-vendor.py" "$ROOT"
if [[ "$WITH_GAPPS" == true && "$PIXEL3_GAPPS_LITE" == true ]]; then
  python3 "$SCRIPT_DIR/scripts/trim-gapps.py" "$ROOT"
fi
if [[ "$MODE" == "--prepare-only" ]]; then exit 0; fi

# Let ServerHive choose the build job count; preserve its existing RBE setup.
export USE_RBE=${USE_RBE:-true}
mkdir -p out/build-logs
LOG="$ROOT/out/build-logs/infinity-blueline-$(date -u +%Y%m%d-%H%M%S).log"
echo "Build log: $LOG"
(
  source build/envsetup.sh
  lunch infinity_blueline cp2a userdebug
  m kernelconfig
  python3 "$SCRIPT_DIR/scripts/check-kernel-config.py" "$ANDROID_PRODUCT_OUT/obj/KERNEL_OBJ/.config"
  m bacon
  # A bootable graphics stack needs HWC2, not just software UI rendering.
  hwc="$ANDROID_PRODUCT_OUT/vendor/lib64/hw/hwcomposer.qcom.so"
  if [[ ! -f "$hwc" ]]; then echo "Missing Qualcomm hardware composer: $hwc" >&2; exit 1; fi
  echo "Pixel 3 Qualcomm hardware composer module: PRESENT (runtime selection not yet verified)"
  # Android 17 now reads vendor permissions from vendor/etc/ueventd.rc.
  ueventd="$ANDROID_PRODUCT_OUT/vendor/etc/ueventd.rc"
  if [[ ! -f "$ueventd" ]] || ! grep -q '/dev/citadel0' "$ueventd" ||
       ! grep -q '/dev/qseecom' "$ueventd"; then
    echo "Missing Citadel/QSEE uevent permissions in $ueventd" >&2
    exit 1
  fi
  echo "Pixel 3 Citadel/QSEE device permission rules: PASS"
  echo "Android build complete. Verify GApps apps, partition sizes, filesystem unlock and device boot before release."
) 2>&1 | tee "$LOG"
