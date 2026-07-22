#!/bin/bash
set -euo pipefail

# =============================================================================
# rpm/build.sh — Build RPM packages for Xiaomi Pad 6S Pro firmware/kernel
# =============================================================================
# 用法:
#   ./rpm/build.sh                    — 构建全部 4 个 RPM
#   ./rpm/build.sh firmware           — 仅构建固件 RPM
#   ./rpm/build.sh kernel 7.1.4       — 构建内核 RPM (需先运行 sheng-kernel_build.sh)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$(dirname "$SCRIPT_DIR")"
RPMBUILD_DIR="$WORKSPACE/rpmbuild"
RPM_OUTPUT="$WORKSPACE/rpm-output"

source "$WORKSPACE/lib/rootfs-common.sh"

mkdir -p "$RPM_OUTPUT"

build_rpm() {
    local spec="$1" pkg_name="$2"
    echo ""
    echo "=========================================="
    echo " 构建 RPM: $pkg_name"
    echo "=========================================="

    rm -rf "$RPMBUILD_DIR"
    mkdir -p "$RPMBUILD_DIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

    cp "$SCRIPT_DIR/${spec}" "$RPMBUILD_DIR/SPECS/"

    rpmbuild -bb \
        --define "_topdir $RPMBUILD_DIR" \
        --define "kernel_version ${KERNEL_VER:-0.0}" \
        "$RPMBUILD_DIR/SPECS/${spec}"

    find "$RPMBUILD_DIR/RPMS" -name "*.rpm" -exec cp {} "$RPM_OUTPUT/" \;
    echo "  -> $pkg_name 构建完成"
}

# ===========================================================================
# 固件 RPM: firmware-xiaomi-sheng
# ===========================================================================
build_firmware_rpm() {
    echo "下载固件源码..."
    download_firmware "firmware-xiaomi-sheng/usr/lib"
    build_rpm "firmware-xiaomi-sheng.spec" "firmware-xiaomi-sheng"
}

# ===========================================================================
# ALSA UCM2 RPM: alsa-xiaomi-sheng
# ===========================================================================
build_alsa_rpm() {
    echo "下载 ALSA UCM2 配置..."
    download_alsa_ucm "alsa-xiaomi-sheng/usr/share/alsa/ucm2"
    build_rpm "alsa-xiaomi-sheng.spec" "alsa-xiaomi-sheng"
}

# ===========================================================================
# 键盘认证 RPM: sheng-devauth
# ===========================================================================
build_devauth_rpm() {
    build_rpm "sheng-devauth.spec" "sheng-devauth"
}

# ===========================================================================
# 内核 RPM: linux-xiaomi-sheng
# ===========================================================================
build_kernel_rpm() {
    if [ ! -d "$WORKSPACE/linux-xiaomi-sheng/boot" ]; then
        echo "错误: 未找到内核构建产物，请先运行 sheng-kernel_build.sh" >&2
        return 1
    fi
    build_rpm "linux-xiaomi-sheng.spec" "linux-xiaomi-sheng"
}

# ===========================================================================
# 主入口
# ===========================================================================
cd "$WORKSPACE"

case "${1:-all}" in
    all)
        build_firmware_rpm
        build_alsa_rpm
        build_devauth_rpm
        if [ -d "linux-xiaomi-sheng/boot" ]; then
            build_kernel_rpm
        else
            echo "跳过内核 RPM (未找到 linux-xiaomi-sheng/ 构建产物)"
        fi
        ;;
    firmware)
        build_firmware_rpm
        ;;
    alsa)
        build_alsa_rpm
        ;;
    devauth)
        build_devauth_rpm
        ;;
    kernel)
        KERNEL_VER="${2:-0.0}"
        build_kernel_rpm
        ;;
    *)
        echo "用法: $0 [all|firmware|alsa|devauth|kernel <version>]" >&2
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo " RPM 构建完成！"
echo " 输出目录: $RPM_OUTPUT"
ls -lah "$RPM_OUTPUT"/*.rpm 2>/dev/null || echo "  (无 RPM 文件)"
echo "=========================================="
