#/bin/bash
#############################
#      REQUIRED SETUP
KSU=ndef # set to 1 to enable KernelSU; if not leave the same

DEFCONFIG=begonia_user_defconfig # set preferred existing defconfig in arch/arm64/configs
               # or if arch/arm64/configs does not contain it, specify 
               # a defconfig in THE SAME DIRECTORY WITH build.sh
               
KERNEL_SOURCE=https://github.com/AgentFabulous/begonia.git # set to a preferred remote URL (e.g https://github.com/torvalds/linux...)

KBRANCH="android-12.0" # if not changed, use default kernel branch
           # set to "-b <kernel branch name>" if you want to
CLANGDL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android11-qpr2-release/clang-r383902b1.tar.gz"
        # direct link to Clang toolchain
#############################

case $HOSTNAME in
  (fv-az*)  ISACTIONS=1 ;;
  (*)  ISACTIONS=0 ;;
esac

getsource () {
    if [ ! -d "common" ]; then
    echo ============================
    echo Downloading kernel source...
    set -x
    git clone --depth=1 $KERNEL_SOURCE $KBRANCH common
    set +x
    fi
}
gettools () {
    set -x
    if [ ! -d "build" ]; then
    echo ==================================
    echo Downloading back-end build scripts
    git clone --depth=1 https://android.googlesource.com/kernel/build -b master-kernel-build-2021 build
    fi
    if [ ! -d "prebuilts" ]; then
    echo ============================
    echo Downloading build essentials
    git clone --depth=1 https://android.googlesource.com/kernel/prebuilts/build-tools -b master-kernel-build-2021 prebuilts/kernel-build-tools
    git clone --depth=1 https://android.googlesource.com/platform/prebuilts/build-tools -b master-kernel-build-2021 prebuilts/build-tools
    fi
    if [ ! -d "clang" ]; then
    echo ===========================
    echo Downloading Clang toolchain
    if [ $ISACTIONS = 1 ]; then
    curl -s -o clang/clang.zip --create-dirs ${CLANGDL}
    else curl -o clang/clang.zip --create-dirs ${CLANGDL}
    fi
    cd clang
    tar -xzf clang.zip
    cd ..
    fi
    if [ ! -d "gcc" ]; then
    echo ====================
    echo Extracting assembler
    #source: https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9
    #        https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9
    mkdir gcc && cd gcc
    unzip -q ../lineageos-tc.zip
    cd ..
    fi
    echo ==================================
    #echo Installing additional dependencies
    #sudo apt update > /dev/null 2>&1
    #sudo apt install -y rsync
    set +x
}
startbuild () {
    set -x
    echo Copying configs
    cp build.config.veux common/
    cp $DEFCONFIG common/arch/arm64/configs/
    cp common/arch/arm64/configs/vendor/veux_QGKI.config common/arch/arm64/configs/perf_defconfig
    if [ $KSU = 1 ]; then
        echo Integrating KernelSU
        curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -
    fi
    set +x
    echo ================================================
    echo Build started on $HOSTNAME with $(nproc) threads
    echo Target:
    VSUFFIX="$(grep -m 1 "VERSION" common/Makefile | sed 's/.*= *//' | tr -d ' ').$(grep -m 1 "PATCHLEVEL" common/Makefile | sed 's/.*= *//' | tr -d ' ').$(grep -m 1 "SUBLEVEL" common/Makefile | sed 's/.*= *//' | tr -d ' ')"
    if [ $KSU = 1 ]; then VSUFFIX+="-KernelSU" ; fi
    echo "Android ${VSUFFIX} (commit $(cd common && git rev-parse HEAD))"
    echo $VSUFFIX > VERSION.txt
    echo ================================================
    echo Calling back-end script...
    set -x
    if [ $ISACTIONS = 1 ]; then
        echo "INFO: GitHub Actions host detected, build log won't be piped/redirected"
        echo "INFO: To retrieve logs, click the gear button next to "Search logs" then "Download log archive""
        DEFCONFIG="$DEFCONFIG" BUILD_CONFIG=common/build.config.veux build/build.sh
    elif grep -q "V=1" common/build.config.veux; then
        #Prevent console flooding in verbose mode
        DEFCONFIG="$DEFCONFIG" BUILD_CONFIG=common/build.config.veux build/build.sh > build.log 2> >(tee -a build.log >&2)
    else
        DEFCONFIG="$DEFCONFIG" BUILD_CONFIG=common/build.config.veux build/build.sh 2>&1 | tee build.log
    fi
    set +x
}
envcheck () {
    if [[ "$DEFCONFIG" == "ndef" ]]; then
    echo "ERROR: You didn't complete first-time setup"
    echo "Open the build.sh file and edit first lines"
    exit 2
    else
        echo DEFCONFIG is $DEFCONFIG
        echo Kernel source is set to $KERNEL_SOURCE
        if [[ $KSU == 1 ]]; then
            echo "KernelSU is enabled for this build"
            else
            echo "KernelSU is not enabled. If you have integrated KernelSU before, you might want to redownload source before building."
        fi
        echo .
        if [ $ISACTIONS != 1 ]; then
        read -p "Are these settings correct? [Y/n] " answer
        case ${answer:0:1} in
            y|Y )
            ;;
            * )
            echo "Go back and edit build.sh to your choice"
            exit 1
            ;;
        esac
        fi
    fi
}
finalize () {
    if [ -e "out/android11-5.4/dist/Image" ]; then
        set -x
        sed -i 's/unknownversion/$(cat VERSION.txt)/g'
        if [ $KSU = 1 ]; then sed -i 's/do.systemless=0/do.systemless=1/g'; fi
        cp out/android11-5.4/dist/Image AnyKernel3
        cp out/android11-5.4/dist/*.ko AnyKernel3/modules/system/lib/modules
        if [ $ISACTIONS = 1 ]; then echo Workflow will pack up zip file as artifact.
        else
            echo =========================
            echo Packing to updater zip...
            cd AnyKernel3
            zip -r5 AnyKernel3_veux-${VSUFFIX}_$(date +'%Y%m%d-%H%M').zip .
            mv *.zip .. && cd ..
        fi
        set +x
    else
        echo Build ended prematurely. Exiting...
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
            rm -rf common/ build/ prebuilts/ gcc/ out/ clang/ KernelSU/
            rm AnyKernel3/Image
            rm build.log
            ;;
        *)
            echo "Unknown option '$1'"
            exit 1
            ;;
    esac
else
    envcheck && getsource && gettools && startbuild && finalize
fi

