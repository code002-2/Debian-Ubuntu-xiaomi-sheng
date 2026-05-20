#!/bin/bash
set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"

UBUNTU_SUITE="resolute"
UBUNTU_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/ubuntu"

usage() {
    echo "用法: $0 <variant> <kernel_version> [desktop_environment]"
    echo "variant: server 或 desktop"
    echo "desktop_environment: gnome 或 kde (仅当 variant=desktop 时有效，默认 gnome)"
    exit 1
}

if [ $# -lt 2 ]; then
    usage
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root权限运行"
    exit 1
fi

VARIANT=$1
KERNEL=$2
DESKTOP_ENV=${3:-gnome}

if [[ "$VARIANT" != "server" && "$VARIANT" != "desktop" ]]; then
    echo "错误: variant 必须是 server 或 desktop"
    exit 1
fi

if [ "$VARIANT" = "desktop" ] && [[ "$DESKTOP_ENV" != "gnome" && "$DESKTOP_ENV" != "kde" ]]; then
    echo "错误: desktop_environment 必须是 gnome 或 kde"
    exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="ubuntu26_${VARIANT}_${DESKTOP_ENV}_${TIMESTAMP}.img"

echo "=========================================="
echo "开始构建 Ubuntu 26.04 LTS (Resolute) RootFS"
echo "变体: $VARIANT"
echo "桌面环境: $([ "$VARIANT" = "desktop" ] && echo "$DESKTOP_ENV" || echo "none")"
echo "内核版本: $KERNEL"
echo "语言环境: 英文 (en_US.UTF-8)"
echo "=========================================="

rm -rf rootdir || true
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

debootstrap --arch=arm64 "$UBUNTU_SUITE" rootdir "$UBUNTU_MIRROR"

mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

cat > rootdir/etc/apt/sources.list <<EOF
deb $UBUNTU_MIRROR $UBUNTU_SUITE main restricted universe multiverse
deb $UBUNTU_MIRROR ${UBUNTU_SUITE}-updates main restricted universe multiverse
deb $UBUNTU_MIRROR ${UBUNTU_SUITE}-backports main restricted universe multiverse
deb $UBUNTU_MIRROR ${UBUNTU_SUITE}-security main restricted universe multiverse
EOF

chroot rootdir apt update

if ls *.deb 1> /dev/null 2>&1; then
    cp *.deb rootdir/tmp/
    chroot rootdir bash -c "apt install -y /tmp/*.deb || true"
fi

# ============================================
# 基础包（不安装任何中文相关包）
# ============================================
chroot rootdir apt install -y --no-install-recommends \
    systemd sudo vim-tiny wget curl \
    network-manager openssh-server \
    wpasupplicant dbus

# 设置默认 locale 为英文
chroot rootdir bash -c "echo 'LANG=en_US.UTF-8' > /etc/default/locale"
chroot rootdir locale-gen en_US.UTF-8

# root 密码
chroot rootdir bash -c "echo -e '1234\n1234' | passwd root"
echo "ubuntu26-${VARIANT}" > rootdir/etc/hostname

# =========================
# 桌面环境安装（根据 DESKTOP_ENV 选择）
# =========================
if [ "$VARIANT" = "desktop" ]; then
    if [ "$DESKTOP_ENV" = "gnome" ]; then
        chroot rootdir apt install -y --no-install-recommends \
            ubuntu-desktop-minimal \
            gnome-terminal \
            firefox \
            gdm3
        DM="gdm3"
    else   # KDE Plasma
        chroot rootdir apt install -y --no-install-recommends \
            plasma-desktop \
            sddm \
            konsole \
            firefox \
            plasma-workspace \
            systemsettings \
            discover \
            packagekit \
            packagekit-tools
        DM="sddm"
    fi

    # 创建普通用户
    chroot rootdir useradd -m -s /bin/bash luser
    echo "luser:luser" | chroot rootdir chpasswd
    chroot rootdir usermod -aG sudo luser

    # 自动登录配置
    if [ "$DM" = "gdm3" ]; then
        mkdir -p rootdir/etc/gdm3
        cat > rootdir/etc/gdm3/daemon.conf <<EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=luser
EOF
        chroot rootdir systemctl enable gdm3
    else
        mkdir -p rootdir/etc/sddm.conf.d
        cat > rootdir/etc/sddm.conf.d/autologin.conf <<EOF
[Autologin]
User=luser
Session=plasma
EOF
        chroot rootdir systemctl enable sddm
    fi

    # 注意：不配置任何中文输入法和中文环境变量
    chroot rootdir systemctl set-default graphical.target
else
    # 服务器版
    chroot rootdir systemctl enable ssh
    chroot rootdir systemctl enable NetworkManager
    chroot rootdir systemctl set-default multi-user.target
fi

# fstab
cat > rootdir/etc/fstab <<EOF
PARTLABEL=linux / ext4 defaults 0 1
EOF

chroot rootdir apt clean
chroot rootdir rm -rf /tmp/*.deb

umount rootdir/dev/pts || true
umount rootdir/dev || true
umount rootdir/proc || true
umount rootdir/sys || true
umount rootdir || true
rm -rf rootdir

tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"

echo "✅ 镜像生成: $ROOTFS_IMG"
echo "🗜️ 压缩中..."
7z a "${ROOTFS_IMG}.7z" "$ROOTFS_IMG"
echo "🎉 完成！输出文件: ${ROOTFS_IMG}.7z"
