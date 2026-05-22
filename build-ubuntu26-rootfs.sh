#!/bin/bash
set -e

# 🛡️ 异常守护：确保清理挂载
cleanup() {
    umount -l rootdir/dev/pts 2>/dev/null || true
    umount -l rootdir/dev 2>/dev/null || true
    umount -l rootdir/proc 2>/dev/null || true
    umount -l rootdir/sys 2>/dev/null || true
    umount -l rootdir 2>/dev/null || true
}
trap cleanup EXIT ERR

IMAGE_SIZE="12G"
UBUNTU_SUITE="resolute"
BUILD_MIRROR="http://archive.ubuntu.com/ubuntu"

if [ $# -ne 2 ]; then
    echo "用法: $0 <kernel_version> <desktop_environment>"
    exit 1
fi

KERNEL=$1
DESKTOP_ENV=$2
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="ubuntu26_${DESKTOP_ENV}_${TIMESTAMP}.img"

truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 -L linux "$ROOTFS_IMG"
mkdir -p rootdir
mount -o loop "$ROOTFS_IMG" rootdir

# 基础自举
debootstrap --arch=arm64 "$UBUNTU_SUITE" rootdir "$BUILD_MIRROR"

# 挂载虚拟文件系统
mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

# 配置源
printf "deb %s %s main restricted universe multiverse\n" "$BUILD_MIRROR" "$UBUNTU_SUITE" > rootdir/etc/apt/sources.list
export DEBIAN_FRONTEND=noninteractive

# 安装基础组件
chroot rootdir apt-get update
chroot rootdir apt-get install -y eatmydata
chroot rootdir eatmydata apt-get install -y --no-install-recommends \
    systemd sudo vim-tiny wget curl network-manager openssh-server dbus

# 桌面环境安装 (替换为完整的 ubuntu-desktop)
if [ "$DESKTOP_ENV" = "gnome" ]; then
    chroot rootdir eatmydata apt-get install -y --no-install-recommends ubuntu-desktop gdm3 mesa-vulkan-drivers libgl1-mesa-dri
    # 配置自动登录
    mkdir -p rootdir/etc/gdm3
    printf "[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=luser\n" > rootdir/etc/gdm3/custom.conf
    DM="gdm3"
fi

# 创建用户与底层修复
chroot rootdir useradd -m -s /bin/bash luser
echo "luser:luser" | chroot rootdir chpasswd
chroot rootdir usermod -aG sudo,audio,video,render,input luser
mkdir -p rootdir/etc/udev/rules.d/
printf 'ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"\n' > rootdir/etc/udev/rules.d/99-touchscreen-sheng.rules

# 清理并压缩
chroot rootdir apt-get clean
cleanup
7z a -t7z -m0=lzma2 -mx=5 -mmt=on "ubuntu26_${DESKTOP_ENV}_${TIMESTAMP}.7z" "$ROOTFS_IMG"
rm -f "$ROOTFS_IMG"

echo "✅ 构建完成: ubuntu26_${DESKTOP_ENV}_${TIMESTAMP}.7z"
