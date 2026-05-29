#!/bin/bash
set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"
ALARM_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm"

usage() {
    echo "用法: $0 <distro_name> <kernel_version>"
    exit 1
}

if [ $# -ne 2 ]; then
    usage
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root权限运行"
    exit 1
fi

DISTRO=$1
KERNEL=$2
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="archlinux_desktop_${TIMESTAMP}.img"

echo "=========================================="
echo "⏳ 开始构建纯净桌面版 Arch Linux ARM RootFS"
echo "内核版本: $KERNEL"
echo "=========================================="

rm -rf rootdir || true
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

echo "⬇️ 正在下载 Arch Linux ARM (aarch64) 基础包..."
wget -q http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
bsdtar -xpf ArchLinuxARM-aarch64-latest.tar.gz -C rootdir
rm ArchLinuxARM-aarch64-latest.tar.gz

mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

# 配置清华大学 Arch Linux ARM 镜像源
echo "Server = $ALARM_MIRROR/\$arch/\$repo" > rootdir/etc/pacman.d/mirrorlist

# 初始化 pacman 密钥环
chroot rootdir pacman-key --init
chroot rootdir pacman-key --populate archlinuxarm

echo "📦 正在更新系统并安装基础组件..."
chroot rootdir pacman -Syu --noconfirm systemd sudo vim wget curl networkmanager wpa_supplicant dbus

if ls *.pkg.tar.* 1> /dev/null 2>&1; then
    echo "🔨 发现本地内核/构建包，正在安装..."
    cp *.pkg.tar.* rootdir/tmp/
    chroot rootdir bash -c "pacman -U --noconfirm /tmp/*.pkg.tar.* || true"
fi

# 🌐 语言环境初始化
echo 'en_US.UTF-8 UTF-8' > rootdir/etc/locale.gen
chroot rootdir locale-gen
echo 'LANG=en_US.UTF-8' > rootdir/etc/locale.conf

# 密码设置
chroot rootdir bash -c "echo 'root:1234' | chpasswd"

# 主机名完全调整为 arch-sheng
echo "arch-sheng" > rootdir/etc/hostname

# 安装 GNOME 桌面环境和 GDM
echo "🖥️ 正在安装 GNOME 桌面环境..."
chroot rootdir pacman -S --noconfirm gnome gdm

# 创建普通用户并分配合规的硬件访问权限组 (Arch 习惯使用 wheel 组进行提权)
chroot rootdir useradd -m -s /bin/bash luser
chroot rootdir bash -c "echo 'luser:luser' | chpasswd"
chroot rootdir usermod -aG wheel,audio,video,input luser

# 赋予 wheel 组 sudo 权限
echo "%wheel ALL=(ALL:ALL) ALL" > rootdir/etc/sudoers.d/wheel
chmod 440 rootdir/etc/sudoers.d/wheel

echo "🩹 正在针对高通 SM8550 (Sheng) 注入底层自愈补丁..."
ln -sf /usr/lib/systemd/system/getty@.service rootdir/etc/systemd/system/getty.target.wants/getty@ttyMSM0.service

# 激活 DNS 托管解析与网络服务
chroot rootdir systemctl enable systemd-resolved
chroot rootdir systemctl enable NetworkManager
ln -sf /run/systemd/resolve/stub-resolv.conf rootdir/etc/resolv.conf

# 触控屏幕方向与矩阵校准规则
mkdir -p rootdir/etc/udev/rules.d/
printf 'ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"\n' > rootdir/etc/udev/rules.d/99-touchscreen-sheng.rules

# GDM 自动登录配置 (Arch 中 GDM 配置文件路径不同于 Debian)
mkdir -p rootdir/etc/gdm
printf "[daemon]\nAutomaticLoginEnable=True\nAutomaticLogin=luser\n" > rootdir/etc/gdm/custom.conf
chroot rootdir systemctl enable gdm

# 强制进入图形化靶位
chroot rootdir systemctl set-default graphical.target

# 文件系统挂载对齐
printf "PARTLABEL=linux / ext4 defaults,noatime 0 1\n" > rootdir/etc/fstab

# 清理构建缓存
chroot rootdir pacman -Scc --noconfirm
chroot rootdir rm -rf /tmp/*.pkg.tar.*

# 卸载与清理
umount rootdir/dev/pts || true
umount rootdir/dev || true
umount rootdir/proc || true
umount rootdir/sys || true
umount rootdir || true
rm -rf rootdir

tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"

echo "✅ 镜像生成完成: $ROOTFS_IMG"
echo "🗜️ 正在生成最终 7z 压缩包..."
7z a "archlinux_desktop_${TIMESTAMP}.7z" "$ROOTFS_IMG"
rm -f "$ROOTFS_IMG"

echo "🎉 精简桌面版 Arch Linux ARM 自动化编译全部圆满成功！"
