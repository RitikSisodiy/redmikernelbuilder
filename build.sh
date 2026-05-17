#!/bin/bash
#############################
# REQUIRED SETUP
KSU=ndef

DEFCONFIG=begonia_user_defconfig
KERNEL_SOURCE=https://github.com/AgentFabulous/begonia.git
KBRANCH="android-12.0"

CLANGDL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android11-qpr2-release/clang-r383902b1.tar.gz"
#############################

case $HOSTNAME in
  (fv-az*) ISACTIONS=1 ;;
  (*) ISACTIONS=0 ;;
esac

# =============================
# Docker config fragment
# =============================
apply_extra_config () {
    echo "[+] Creating Docker kernel config fragment..."

    mkdir -p common/configs

    cat > common/configs/docker.cfg <<'EOF'
CONFIG_IPC_NS=y
CONFIG_USER_NS=y
CONFIG_POSIX_MQUEUE=y

CONFIG_KEYS=y

CONFIG_CGROUP_DEVICE=y
CONFIG_CGROUP_PIDS=y
CONFIG_CGROUP_PERF=y
CONFIG_CGROUP_HUGETLB=y

CONFIG_BLK_CGROUP=y
CONFIG_BLK_DEV_THROTTLING=y

CONFIG_CFS_BANDWIDTH=y
CONFIG_NET_CLS_CGROUP=y
CONFIG_CGROUP_NET_PRIO=y

CONFIG_VETH=y
CONFIG_DUMMY=y
CONFIG_VXLAN=y
CONFIG_IPVLAN=y
CONFIG_MACVLAN=y

CONFIG_BRIDGE_VLAN_FILTERING=y

CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y
CONFIG_NETFILTER_XT_MATCH_IPVS=y

CONFIG_IP6_NF_NAT=y
CONFIG_IP6_NF_TARGET_MASQUERADE=y

CONFIG_NF_TABLES=y
CONFIG_NFT_CT=y
CONFIG_NFT_FIB=y
CONFIG_NFT_FIB_IPV4=y
CONFIG_NFT_FIB_IPV6=y
CONFIG_NFT_MASQ=y
CONFIG_NFT_NAT=y

CONFIG_IP_VS=y
CONFIG_IP_VS_NFCT=y
CONFIG_IP_VS_PROTO_TCP=y
CONFIG_IP_VS_PROTO_UDP=y
CONFIG_IP_VS_RR=y

CONFIG_BTRFS_FS=y
CONFIG_BTRFS_FS_POSIX_ACL=y

CONFIG_MEMCG_SWAP=y
CONFIG_MEMCG_SWAP_ENABLED=y

CONFIG_ANDROID_PARANOID_NETWORK=n
EOF
}

# =============================
# Verify fragment exists
# =============================
verify_fragment () {
    echo "[+] Checking docker.cfg..."

    if [ -f "common/configs/docker.cfg" ]; then
        echo "✔ docker.cfg present"
    else
        echo "❌ docker.cfg missing"
        exit 2
    fi
}

# =============================
# Verify final kernel config
# =============================
verify_final_config () {
    echo "[+] Verifying final kernel config..."

    CONFIG_PATH="out/.config"

    if [ ! -f "$CONFIG_PATH" ]; then
        CONFIG_PATH="common/.config"
    fi

    if [ ! -f "$CONFIG_PATH" ]; then
        echo "⚠ .config not found yet, skipping check"
        return 0
    fi

    check () {
        grep -q "^$1=y" "$CONFIG_PATH" && echo "✔ $1" || echo "❌ $1 missing"
    }

    echo "---- Docker / Container checks ----"
    check CONFIG_USER_NS
    check CONFIG_IPC_NS
    check CONFIG_CGROUPS
    check CONFIG_CGROUP_DEVICE
    check CONFIG_VETH
    check CONFIG_BRIDGE
    check CONFIG_NET_NS
    check CONFIG_MEMCG
    echo "-----------------------------------"
}

# =============================
getsource () {
    if [ ! -d "common" ]; then
        echo "[+] Cloning kernel source..."
        git clone --depth=1 -b $KBRANCH $KERNEL_SOURCE common
    fi
}

# =============================
gettools () {
    if [ ! -d "build" ]; then
        git clone --depth=1 https://android.googlesource.com/kernel/build -b master-kernel-build-2021 build
    fi

    if [ ! -d "prebuilts" ]; then
        git clone --depth=1 https://android.googlesource.com/kernel/prebuilts/build-tools -b master-kernel-build-2021 prebuilts/kernel-build-tools
        git clone --depth=1 https://android.googlesource.com/platform/prebuilts/build-tools -b master-kernel-build-2021 prebuilts/build-tools
    fi

    if [ ! -d "clang" ]; then
        mkdir -p clang
        curl -L -o clang/clang.tar.gz "$CLANGDL"
        tar -xzf clang/clang.tar.gz -C clang
    fi
}

# =============================
envcheck () {
    if [[ "$DEFCONFIG" == "ndef" ]]; then
        echo "ERROR: DEFCONFIG not set"
        exit 2
    fi

    echo "DEFCONFIG = $DEFCONFIG"
    echo "KERNEL = $KERNEL_SOURCE"

    if [ "$ISACTIONS" = "1" ]; then
        echo "CI mode detected"
    else
        read -p "Continue build? [Y/n] " a
        case "${a:-y}" in
            y|Y) ;;
            *) exit 1 ;;
        esac
    fi
}

# =============================
startbuild () {
    echo "================================="
    echo "Preparing build"
    echo "================================="

    cp build.config.veux common/
    cp "$DEFCONFIG" common/arch/arm64/configs/

    # ✔ APPLY CUSTOM CONFIG
    apply_extra_config
    verify_fragment

    # ⚠ IMPORTANT: expose config to build system
    export KCONFIG_EXT=common/configs/docker.cfg

    echo "================================="
    echo "Starting kernel build"
    echo "================================="

    DEFCONFIG="$DEFCONFIG" BUILD_CONFIG=common/build.config.veux build/build.sh

    verify_final_config
}

# =============================
finalize () {
    if [ -f "out/android11-5.4/dist/Image" ]; then
        echo "[+] Build successful"

        cp out/android11-5.4/dist/Image AnyKernel3/
        cp out/android11-5.4/dist/*.ko AnyKernel3/modules/system/lib/modules/

        if [ "$ISACTIONS" = "1" ]; then
            echo "CI mode: artifact will be uploaded by GitHub Actions"
        else
            cd AnyKernel3
            zip -r9 Kernel.zip .
            mv Kernel.zip ..
            cd ..
        fi
    else
        echo "❌ Build failed"
        exit 2
    fi
}

# =============================
case "$1" in
    envcheck) envcheck ;;
    getsource) envcheck && getsource ;;
    gettools) gettools ;;
    startbuild) envcheck && startbuild ;;
    finalize) finalize ;;
    *)
        envcheck && getsource && gettools && startbuild && finalize
    ;;
esac
