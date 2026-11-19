#!/usr/bin/env bash
# Infinity-X 17 / Android 17 for Pixel 3, using the LineageOS 24.0 boot baseline.
set -e -o pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
MODE=${1:-build}
case "$MODE" in
    build|--check|--prepare-only) ;;
    *) echo "Usage: bash .repo/local_manifests/build.sh [--check|--prepare-only]" >&2; exit 2 ;;
esac
if (( $# > 1 )); then
    echo "Only one mode argument is accepted." >&2
    exit 2
fi

if [[ ! -f build/envsetup.sh ]]; then
    echo "Run this command from the root of the Infinity-X source checkout." >&2
    exit 1
fi
TOP=$(pwd -P)

# Set and validate build flags before any vendor modifications.
export USE_RBE=${USE_RBE:-true}
export WITH_GAPPS=${WITH_GAPPS:-true}
export PIXEL3_GAPPS_LITE=${PIXEL3_GAPPS_LITE:-true}
export PIXEL3_DEV_USB_ADB=${PIXEL3_DEV_USB_ADB:-true}
INFINITY_BUILD_VARIANT=${INFINITY_BUILD_VARIANT:-userdebug}
case "$WITH_GAPPS:$PIXEL3_GAPPS_LITE:$PIXEL3_DEV_USB_ADB" in
  true:true:true|true:true:false|true:false:true|true:false:false|false:true:true|false:true:false|false:false:true|false:false:false) ;;
  *) echo "WITH_GAPPS, PIXEL3_GAPPS_LITE, PIXEL3_DEV_USB_ADB must be true or false" >&2; exit 2 ;;
esac
case "$INFINITY_BUILD_VARIANT" in
  eng|userdebug) ;;
  *) echo "INFINITY_BUILD_VARIANT must be eng or userdebug" >&2; exit 2 ;;
esac
export INFINITY_BUILD_VARIANT

required=(
    device/google/crosshatch/infinity_blueline.mk
    vendor/infinity/config/common_full_phone.mk
    device/google/crosshatch/blueline/extract-files.py
    vendor/google/blueline/blueline-vendor.mk
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
for path in "${required[@]}"; do
    if [[ ! -f "$path" ]]; then
        echo "Missing source/tool: $path" >&2
        missing=1
    fi
done
if [[ "${WITH_GAPPS:-true}" == true ]] && [[ ! -f vendor/pixel/gms/products/gms.mk ]]; then
    echo "Missing integrated Pixel GMS product tree" >&2
    missing=1
fi
if (( missing )); then
    echo "Complete repo sync with blueline.xml before building." >&2
    exit 1
fi
if [[ -n ${INFINITY_BUILD_JOBS:-} && ! ${INFINITY_BUILD_JOBS} =~ ^[1-9][0-9]*$ ]]; then
    echo "INFINITY_BUILD_JOBS must be a positive integer, or unset for default jobs." >&2
    exit 2
fi
if [[ "$MODE" == --check ]]; then
    echo "Pixel 3 source and tool paths are present. No compilation or hardware test was run."
    exit 0
fi

# Repo sync does not initialize nested Git submodules. The kernel deliberately
# pins the exact KernelSU Next commit as a real Git submodule (not latest).
echo "Initializing pinned KernelSU Next submodule (without SUSFS)"
git -C kernel/google/msm-4.9 submodule sync -- KernelSU
git -C kernel/google/msm-4.9 submodule update --init KernelSU
test -f kernel/google/msm-4.9/drivers/kernelsu/Kconfig ||
    { echo "KernelSU Next submodule or driver symlink missing" >&2; exit 1; }

python3 "$SCRIPT_DIR/scripts/prepare-camera-fd.py" "$TOP"
python3 "$SCRIPT_DIR/scripts/prepare-camera-jni.py" "$TOP"
python3 "$SCRIPT_DIR/scripts/prepare-vendor.py" "$TOP"
if [[ "$WITH_GAPPS" == true && "$PIXEL3_GAPPS_LITE" == true ]]; then
    python3 "$SCRIPT_DIR/scripts/trim-gapps.py" "$TOP"
fi
if [[ "$MODE" == --prepare-only ]]; then
    exit 0
fi

# ServerHive's RBE configuration and credentials remain in effect.
mkdir -p out/build-logs
BUILD_LOG="$TOP/out/build-logs/infinity-blueline-$(date -u +%Y%m%d-%H%M%S).log"
echo "Build log: $BUILD_LOG"
(
    # Android's envsetup scripts are not compatible with nounset.
    source build/envsetup.sh
    lunch infinity_blueline cp2a "$INFINITY_BUILD_VARIANT"
    # Validate the resolved Kconfig before compiling or packaging the kernel.
    m kernelconfig
    python3 "$SCRIPT_DIR/scripts/check-kernel-config.py" "$ANDROID_PRODUCT_OUT/obj/KERNEL_OBJ/.config"
    if [[ -n ${INFINITY_BUILD_JOBS:-} ]]; then
        m bacon "-j${INFINITY_BUILD_JOBS}"
    else
        # Let Android choose its default parallelism; no fixed -j8 cap.
        m bacon
    fi

) 2>&1 | tee "$BUILD_LOG"
