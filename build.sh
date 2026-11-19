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
export PIXEL3_FIRSTBOOT_BASELINE=${PIXEL3_FIRSTBOOT_BASELINE:-true}
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
case "$PIXEL3_FIRSTBOOT_BASELINE" in
  true|false) ;;
  *) echo "PIXEL3_FIRSTBOOT_BASELINE must be true or false" >&2; exit 2 ;;
esac

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

# Isolate early boot from KernelSU: build the exact kernel revision that was
# confirmed to boot LineageOS 24.0 on this Pixel 3. This ONLY changes the
# checked-out kernel for a single diagnostic build; device/vendor remain
# Infinity-X and the manifest keeps the normal KernelSU Next pin.
KERNEL_REPO=kernel/google/msm-4.9
LINEAGE_KERNEL_SHA=484dddd90e130900b4f0cf0ccb5b148b263f7fb4
INFINITY_KERNEL_SHA=fb8936639214988040ce9781f759f02ab5b94204
if [[ "$PIXEL3_FIRSTBOOT_BASELINE" == true ]]; then
    selected_kernel=$LINEAGE_KERNEL_SHA
    kernel_remote=https://github.com/its-hecker/android_kernel_google_msm-4.9.git
    echo "First-boot isolation: proven Lineage kernel (KernelSU Next OFF)"
else
    selected_kernel=$INFINITY_KERNEL_SHA
    kernel_remote=https://github.com/its-hecker/infinity-blueline-kernel.git
    echo "Normal Infinity-X kernel (KernelSU Next ON)"
fi
if [[ "$(git -C "$KERNEL_REPO" rev-parse HEAD)" != "$selected_kernel" ]]; then
    git -C "$KERNEL_REPO" fetch --no-tags "$kernel_remote" "$selected_kernel"
    git -C "$KERNEL_REPO" checkout --detach "$selected_kernel"
fi

# The kernel output directory can otherwise retain binaries/configuration
# from the opposite boot test even when source revisions have changed.
kernel_stamp="$TOP/out/.infinity_blueline_selected_kernel"
previous_kernel=$(cat "$kernel_stamp" 2>/dev/null || true)
if [[ "$previous_kernel" != "$selected_kernel" ]]; then
    echo "Kernel revision switched: removing cached blueline kernel objects"
    rm -rf "$TOP/out/target/product/blueline/obj/KERNEL_OBJ"
    rm -f "$TOP/out/target/product/blueline/boot.img"
    mkdir -p "$TOP/out"
    printf '%s\n' "$selected_kernel" > "$kernel_stamp"
fi
if [[ "$PIXEL3_FIRSTBOOT_BASELINE" == false ]]; then
    # Repo sync does not initialize nested Git submodules. KSU Next is pinned
    # to a real submodule commit, with no SUSFS in this build.
    echo "Initializing pinned KernelSU Next submodule (without SUSFS)"
    git -C "$KERNEL_REPO" submodule sync -- KernelSU
    git -C "$KERNEL_REPO" submodule update --init KernelSU
    test -f "$KERNEL_REPO/drivers/kernelsu/Kconfig" ||
        { echo "KernelSU Next submodule or driver symlink missing" >&2; exit 1; }
fi

# ADB defaults to authenticated. Only the matching public key supplied by
# the developer is copied into out/ (never into a tracked/public Git repo).
# Recovery and early adbd can use PRODUCT_ADB_KEYS to trust this host.
export PIXEL3_ADB_HOST_KEY=false
trusted_key="$TOP/out/hecker-adb/blueline.pub"
if [[ -n ${PIXEL3_ADB_PUBLIC_KEY:-} ]]; then
    if [[ "$PIXEL3_DEV_USB_ADB" != true || "$INFINITY_BUILD_VARIANT" != userdebug ]]; then
        echo "Host-key provisioning requires PIXEL3_DEV_USB_ADB=true and userdebug" >&2
        exit 2
    fi
    if [[ ! -f "$PIXEL3_ADB_PUBLIC_KEY" || ! -r "$PIXEL3_ADB_PUBLIC_KEY" ]]; then
        echo "Cannot read public ADB host key: $PIXEL3_ADB_PUBLIC_KEY" >&2
        exit 2
    fi
    if ! head -n 1 "$PIXEL3_ADB_PUBLIC_KEY" | grep -Eq '^[A-Za-z0-9+/=]{64,}[[:space:]]+'; then
        echo "Expected a valid adbkey.pub public key (never the private adbkey)" >&2
        exit 2
    fi
    mkdir -p "$(dirname "$trusted_key")"
    head -n 1 "$PIXEL3_ADB_PUBLIC_KEY" > "$trusted_key"
    chmod 0600 "$trusted_key"
    export PIXEL3_ADB_HOST_KEY=true
    echo "Authenticated ADB: only the supplied computer key is pre-authorized"
else
    rm -f "$trusted_key"
    echo "Authenticated ADB enabled; host must be approved on device"
fi

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
    # A/B boot testing toggles GApps as well as the kernel. Avoid shipping
    # previously installed Pixel GMS packages into a no-GApps test image.
    product_stamp="$TOP/out/.infinity_blueline_gapps_variant"
    product_variant="$WITH_GAPPS:$PIXEL3_GAPPS_LITE"
    old_product_variant=$(cat "$product_stamp" 2>/dev/null || true)
    if [[ "$old_product_variant" != "$product_variant" ]]; then
        echo "GApps configuration changed: running m installclean"
        m installclean
        printf '%s\n' "$product_variant" > "$product_stamp"
    fi
    # Validate the resolved Kconfig before compiling or packaging the kernel.
    m kernelconfig
    if [[ "$PIXEL3_FIRSTBOOT_BASELINE" == true ]]; then
        python3 "$SCRIPT_DIR/scripts/check-kernel-config.py" --no-kernelsu "$ANDROID_PRODUCT_OUT/obj/KERNEL_OBJ/.config"
    else
        python3 "$SCRIPT_DIR/scripts/check-kernel-config.py" "$ANDROID_PRODUCT_OUT/obj/KERNEL_OBJ/.config"
    fi
    if [[ -n ${INFINITY_BUILD_JOBS:-} ]]; then
        m bacon "-j${INFINITY_BUILD_JOBS}"
    else
        # Let Android choose its default parallelism; no fixed -j8 cap.
        m bacon
    fi

) 2>&1 | tee "$BUILD_LOG"
