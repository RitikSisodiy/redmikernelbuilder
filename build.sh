#!/bin/bash
#############################
#      REQUIRED SETUP
KSU=ndef # set to 1 to enable KernelSU; if not leave as is

DEFCONFIG=begonia_user_defconfig
KERNEL_SOURCE=https://github.com/AgentFabulous/begonia.git

KBRANCH="android-12.0"

CLANGDL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android11-qpr2-release/clang-r383902b1.tar.gz"
#############################

case $HOSTNAME in
  (fv-az*) ISACTIONS=1 ;;
  (*) ISACTIONS=0 ;;
esac

getsource () {
    if [ ! -d "common" ]; then
        echo "============================"
        echo "Downloading kernel source..."
        set -x
        git clone --depth=1 $KERNEL_SOURCE -b $KBRANCH common
        set +x
    fi
}

gettools () {
    set -x

    if [ ! -d "build" ]; then
        echo "Downloading back-end build scripts"
        git clone --depth=1 https://android.googlesource.com/kernel/build -b master-kernel-build-2021 build
    fi

    if [ ! -d "prebuilts" ]; then
        echo "Downloading build essentials"
        git clone --depth=1 https://android.googlesource.com/kernel/prebuilts/build-tools -b master-kernel-build-2021 prebuilts/kernel-build-tools
        git clone --depth=1 https://android.googlesource.com/platform/prebuilts/build-tools -b master-kernel-build-2021 prebuilts/build-tools
    fi

    if [ ! -d "clang" ]; then
        echo "Downloading Clang toolchain"
        mkdir -p clang
        if [ $ISACTIONS = 1 ]; then
            curl -s -L -o clang/clang.tar.gz ${CLANGDL}
        else
            curl -L -o clang/clang.tar.gz ${CLANGDL}
        fi
        tar -xzf clang/clang.tar.gz -C clang
    fi

    if [ ! -d "gcc" ]; then
        echo "Extracting GCC toolchain"
        mkdir -p gcc
        unzip -q lineageos-tc.zip -d gcc
    fi

    set +x
}

startbuild () {
    set -x

    echo "Copying configs"
    cp build.config.veux common/
    cp $DEFCONFIG common/arch/arm64/configs/
    cp common/arch/arm64/configs/vendor/veux_QGKI.config common/arch/arm64/configs/perf_defconfig

    if [ $KSU = 1 ]; then
        echo "Integrating KernelSU"
        curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -
    fi

    set +x

    echo "========================================"
    echo "Build started on $HOSTNAME with $(nproc) threads"

    VSUFFIX="$(grep -m 1 "VERSION" common/Makefile | awk -F= '{print $2}' | tr -d ' ').
$(grep -m 1 "PATCHLEVEL" common/Makefile | awk -F= '{print $2}' | tr -d ' ').
$(grep -m 1 "SUBLEVEL" common/Makefile | awk -F= '{print $2}' | tr -d ' ')"

    if [ $KSU = 1 ]; then
        VSUFFIX="${VSUFFIX}-KernelSU"
    fi

    echo "Android ${VSUFFIX} (commit $(cd common && git rev-parse HEAD))"
    echo $VSUFFIX > VERSION.txt

    echo "========================================"
    echo "Calling back-end script..."

    if [ $ISACTIONS = 1 ]; then
        echo "CI mode detected"

        DEFCONFIG="$DEFCONFIG" BUILD_CONFIG=common/build.config.veux build/build.sh
    elif grep -q "V=1" common/build.config.veux; then
        DEFCONFIG="$DEFCONFIG" BUILD_CONFIG=common/build.config.veux build/build.sh > build.log 2>&1
    else
        DEFCONFIG="$DEFCONFIG" BUILD_CONFIG=common/build.config.veux build/build.sh 2>&1 | tee build.log
    fi

    set +x
}

envcheck () {
    if [[ "$DEFCONFIG" == "ndef" ]]; then
        echo "ERROR: You didn't complete first-time setup"
        exit 2
    fi

    echo "DEFCONFIG is $DEFCONFIG"
    echo "Kernel source is set to $KERNEL_SOURCE"

    if [[ $KSU == 1 ]]; then
        echo "KernelSU is enabled"
    else
        echo "KernelSU is not enabled"
    fi

    echo "."

    # ✅ FIX: no interactive prompt in CI
    if [ $ISACTIONS = 1 ]; then
        echo "CI detected: auto-accepting settings"
    else
        read -p "Are these settings correct? [Y/n] " answer
        case ${answer:0:1} in
            y|Y ) ;;
            * )
                echo "Go back and edit build.sh"
                exit 1
                ;;
        esac
    fi
}

finalize () {
    if [ -e "out/android11-5.4/dist/Image" ]; then
        set -x

        sed -i "s/unknownversion/$(cat VERSION.txt)/g" AnyKernel3/* 2>/dev/null

        if [ $KSU = 1 ]; then
            sed -i 's/do.systemless=0/do.systemless=1/g' AnyKernel3/* 2>/dev/null
        fi

        cp out/android11-5.4/dist/Image AnyKernel3/
        cp out/android11-5.4/dist/*.ko AnyKernel3/modules/system/lib/modules/

        if [ $ISACTIONS = 1 ]; then
            echo "GitHub Actions will upload artifact"
        else
            echo "Packing zip..."
            cd AnyKernel3
            zip -r5 AnyKernel3_veux-${VSUFFIX}_$(date +'%Y%m%d-%H%M').zip .
            mv *.zip ..
            cd ..
        fi

        set +x
    else
        echo "Build failed or incomplete"
        exit 2
    fi
}

if [ -n "$1" ]; then
    case "$1" in
        "envcheck") envcheck ;;
        "getsource") envcheck && getsource ;;
        "gettools") gettools ;;
        "startbuild") envcheck && startbuild ;;
        "finalize") finalize ;;
        "debug-cleanup")
            rm -rf common build prebuilts gcc out clang KernelSU
            rm -f AnyKernel3/Image build.log VERSION.txt
            ;;
        *)
            echo "Unknown option '$1'"
            exit 1
            ;;
    esac
else
    envcheck && getsource && gettools && startbuild && finalize
fi
