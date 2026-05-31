#!/bin/bash
set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"

# 🎯 锁定 Deepin 官方的新版滚动底座 beige
DEBIAN_SUITE="beige"
DEBIAN_MIRROR="https://community-packages.deepin.com/beige/"

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
ROOTFS_IMG="deepin25_1_0_desktop_${TIMESTAMP}.img"

echo "=========================================="
echo "⏳ 开始构建最前沿版 Deepin 25.1.0 RootFS (安全调试模式)"
echo "内核版本: $KERNEL"
echo "目标分支: $DEBIAN_SUITE"
echo "=========================================="

rm -rf rootdir || true
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

# 欺骗 debootstrap，映射对应的 Deepin 代号
if [ ! -f "/usr/share/debootstrap/scripts/${DEBIAN_SUITE}" ]; then
    echo "🔗 正在映射 debootstrap 构建脚本..."
    ln -sf /usr/share/debootstrap/scripts/sid "/usr/share/debootstrap/scripts/${DEBIAN_SUITE}"
fi

# 基础系统自举安装 (跳过初期的 GPG 校验, 直连官方)
debootstrap --no-check-gpg --arch=arm64 "$DEBIAN_SUITE" rootdir "$DEBIAN_MIRROR"

mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

# 写入专属官方源并强制信任
printf "deb [trusted=yes] %s %s main commercial community\n" "$DEBIAN_MIRROR" "$DEBIAN_SUITE" > rootdir/etc/apt/sources.list

# 🎯 终极网络修复 1：强制写入全球公共 DNS，防断网
rm -f rootdir/etc/resolv.conf
echo "nameserver 8.8.8.8" > rootdir/etc/resolv.conf
echo "nameserver 1.1.1.1" >> rootdir/etc/resolv.conf
echo "nameserver 114.114.114.114" >> rootdir/etc/resolv.conf

chroot rootdir apt update

# 安装定制的高通内核与驱动包，并自动修复依赖
if ls *.deb 1> /dev/null 2>&1; then
    cp *.deb rootdir/tmp/
    chroot rootdir bash -c "apt install -y /tmp/*.deb || apt-get install -f -y"
fi

# 安装基础组件和引导生成工具
chroot rootdir apt install -y --no-install-recommends \
    deepin-keyring systemd systemd-resolved sudo vim-tiny wget curl network-manager wpasupplicant dbus locales initramfs-tools

# 💥 核心防线 2：在 systemd-resolved 覆盖后，再次强行恢复 DNS！
echo "🛡️ 正在恢复被系统覆盖的 DNS 解析配置..."
rm -f rootdir/etc/resolv.conf
echo "nameserver 8.8.8.8" > rootdir/etc/resolv.conf
echo "nameserver 1.1.1.1" >> rootdir/etc/resolv.conf
echo "nameserver 114.114.114.114" >> rootdir/etc/resolv.conf

# 语言环境
chroot rootdir bash -c "echo 'LANG=en_US.UTF-8' > /etc/default/locale"
chroot rootdir sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
chroot rootdir locale-gen en_US.UTF-8

# 密码设置 (root密码: 1234)
chroot rootdir bash -c "echo -e '1234\n1234' | passwd root"
echo "deepin-sheng" > rootdir/etc/hostname

# 🖥️ 拉取 Deepin 官方桌面环境 (双重包名兜底)
echo "🖥️ 正在拉取 Deepin 官方桌面环境..."
chroot rootdir bash -c "apt install -y --no-install-recommends deepin-desktop-environment lightdm || apt install -y --no-install-recommends deepin-desktop-environment-core dde-session-shell lightdm"

# 创建普通用户 (luser / luser)
chroot rootdir useradd -m -s /bin/bash luser
echo "luser:luser" | chroot rootdir chpasswd
chroot rootdir usermod -aG sudo,audio,video,render,input luser

echo "🩹 正在注入底层自愈补丁..."
chroot rootdir bash -c "echo 'ttyMSM0' >> /etc/securetty"
ln -sf /lib/systemd/system/getty@.service rootdir/etc/systemd/system/getty.target.wants/getty@ttyMSM0.service

# 高通 WiFi 固件伪装
if [ -f "rootdir/lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin" ]; then
    cp rootdir/lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin rootdir/lib/firmware/ath12k/WCN7850/hw2.0/board.bin
fi

# 恢复真机的动态 DNS 解析权
chroot rootdir systemctl enable systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf rootdir/etc/resolv.conf

# 触控屏幕矩阵校准规则
mkdir -p rootdir/etc/udev/rules.d/
printf 'ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"\n' > rootdir/etc/udev/rules.d/99-touchscreen-sheng.rules

# ================= 🌌 调试安全配置 开始 =================
echo "🌌 配置调试环境参数..."

# 1. 强制所有 QT 应用和底层环境走 Wayland 协议 (保留此配置为后续测试做准备)
cat <<EOF > rootdir/etc/profile.d/wayland-force.sh
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM="wayland;xcb"
export MOZ_ENABLE_WAYLAND=1
export WLR_NO_HARDWARE_CURSORS=1
EOF
chmod +x rootdir/etc/profile.d/wayland-force.sh

# 2. 配置 LightDM 自动登录
mkdir -p rootdir/etc/lightdm/lightdm.conf.d
cat <<EOF > rootdir/etc/lightdm/lightdm.conf.d/12-autologin.conf
[Seat:*]
autologin-user=luser
autologin-user-timeout=0
user-session=deepin-wayland
EOF

chroot rootdir systemctl enable lightdm

# 🚨 核心改动 1：强制系统开机只进入纯命令行模式，绝对不启动图形界面防死机
echo "🛠️ 设置系统默认启动级别为命令行模式..."
chroot rootdir systemctl set-default multi-user.target

# 3. 屏蔽易导致卡死的声音服务，保留内核报错日志
echo "🔇 正在禁用开机音效服务..."
chroot rootdir systemctl mask deepin-login-sound.service || true
chroot rootdir systemctl mask deepin-login-sound-service.service || true
chroot rootdir bash -c "sed -i 's/quiet splash//g' /etc/default/grub" 2>/dev/null || true

# 🚨 核心改动 2：注释掉高通 KMS 早期强制加载模块，避免 initramfs 阶段屏幕锁死
# echo "⚙️ 配置高通 GPU 早期渲染模块..."
# echo "msm" >> rootdir/etc/initramfs-tools/modules
# echo "gpu_sched" >> rootdir/etc/initramfs-tools/modules
# echo "panel_edp" >> rootdir/etc/initramfs-tools/modules
# ================= 🌌 调试安全配置 结束 =================

# 文件系统挂载对齐
printf "PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro 0 1\n" > rootdir/etc/fstab

# 强制生成引导镜像
echo "🔄 强制重新生成 initramfs 引导镜像..."
chroot rootdir bash -c "update-initramfs -u -k all"

# 清理缓存
chroot rootdir apt clean
chroot rootdir rm -rf /tmp/*.deb

umount rootdir/dev/pts || true
umount rootdir/dev || true
umount rootdir/proc || true
umount rootdir/sys || true
umount rootdir || true
rm -rf rootdir

tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"

echo "✅ 镜像生成完成: $ROOTFS_IMG"
echo "🗜️ 正在生成最终 7z 压缩包..."
7z a "deepin25_1_0_desktop_${TIMESTAMP}.7z" "$ROOTFS_IMG"
rm -f "$ROOTFS_IMG"

echo "🎉 Deepin 25 (命令行调试版) 自动化编译全部圆满成功！"
