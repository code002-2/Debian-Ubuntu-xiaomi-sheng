#!/bin/bash
set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"
KERNEL=$1
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="void_retro_${TIMESTAMP}.img"

echo "=========================================="
echo "🎮 开始构建 Void Linux Retro Gaming OS"
echo "内核版本: $KERNEL"
echo "=========================================="

rm -rf rootdir || true
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir


echo "⬇️ 正在提取 Void Linux 底包..."
VOID_REPO="https://repo-default.voidlinux.org/live/current"
LATEST_TAR=$(curl -s "$VOID_REPO/" | grep -o 'void-aarch64-ROOTFS-[0-9]*.tar.xz' | head -n 1)

if [ -z "$LATEST_TAR" ]; then
    echo "❌ 无法获取 Void Linux 底包！"
    exit 1
fi

wget -q "$VOID_REPO/$LATEST_TAR"
tar -xpf "$LATEST_TAR" -C rootdir/
rm -f "$LATEST_TAR"

mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

echo "nameserver 8.8.8.8" > rootdir/etc/resolv.conf

echo "📦 正在安装 Xorg 底层与 RetroArch 游戏前端..."
export XBPS_ARCH=aarch64

# 初始化包签名并更新
chroot rootdir xbps-install -Syu || true 
chroot rootdir xbps-install -y xbps

chroot rootdir xbps-install -y \
    sudo nano wget curl pciutils findutils \
    NetworkManager wpa_supplicant dbus kmod dracut \
    xorg-minimal xorg-server xinit mesa-dri \
    retroarch

echo "🔨 正在解包注入系统内核与固件..."
if ls *.deb 1> /dev/null 2>&1; then
    for pkg in *.deb; do
        dpkg-deb --fsys-tarfile "$pkg" | tar -x --keep-directory-symlink -C rootdir/
    done
    
    REAL_KERNEL_VER=$(ls rootdir/boot/vmlinuz-* 2>/dev/null | head -n 1 | sed -e 's/.*vmlinuz-//')
    if [ -n "$REAL_KERNEL_VER" ]; then
        echo "   ✅ 锁定真实内核版本: $REAL_KERNEL_VER"
        chroot rootdir /usr/sbin/depmod -a "$REAL_KERNEL_VER" || true
        
        echo "   ⚙️ 正在生成 Initramfs (Dracut)..."
        chroot rootdir dracut -N --kver "$REAL_KERNEL_VER" --force "/boot/initramfs-linux.img"
        cp "rootdir/boot/vmlinuz-$REAL_KERNEL_VER" "rootdir/boot/Image"
    fi
fi

if ls *.tar.gz 1> /dev/null 2>&1; then
    for tarball in *.tar.gz; do
        tar -xz --keep-directory-symlink -f "$tarball" -C rootdir/
    done
fi


chroot rootdir bash -c "echo 'root:1234' | chpasswd"
echo "void-retro-sheng" > rootdir/etc/hostname

chroot rootdir useradd -m -s /bin/bash luser
chroot rootdir bash -c "echo 'luser:luser' | chpasswd"
chroot rootdir usermod -aG wheel,audio,video,input luser
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > rootdir/etc/sudoers.d/wheel

# 高通固件伪装
FW_DIR="rootdir/usr/lib/firmware/ath12k/WCN7850/hw2.0"
if [ -f "$FW_DIR/board-2.bin" ]; then cp "$FW_DIR/board-2.bin" "$FW_DIR/board.bin"; fi

# IPC 防崩溃 (QRTR)
echo "⚙️ 配置 高通 QRTR Runit 服务..."
mkdir -p rootdir/etc/sv/qrtr-ns
cat << 'EOF' > rootdir/etc/sv/qrtr-ns/run
#!/bin/sh
exec 2>&1
exec /usr/bin/qrtr-ns -f
EOF
chmod +x rootdir/etc/sv/qrtr-ns/run

echo "🎮 配置 RetroArch 开机自动全屏启动..."

# 1. 告诉 X 服务器启动时只运行 RetroArch
cat << 'EOF' > rootdir/home/luser/.xinitrc
#!/bin/sh
# 隐藏鼠标光标 (需要安装 unclutter，这里先忽略，RetroArch 支持手柄/触控)
exec retroarch
EOF
chroot rootdir chown luser:luser /home/luser/.xinitrc

# 2. 创建一个自定义的 Runit 服务，让它在 tty1 自动登录并启动 X
mkdir -p rootdir/etc/sv/autostart-retro
cat << 'EOF' > rootdir/etc/sv/autostart-retro/run
#!/bin/sh
exec 2>&1
# 确保 DBus 已经起来
sv check dbus || exit 1
# 以 luser 身份启动 X 服务器
exec chpst -u luser:luser startx
EOF
chmod +x rootdir/etc/sv/autostart-retro/run

# ========================================================
# 🔗 启用所有必要的 Runit 服务
# ==========================================
mkdir -p rootdir/etc/runit/runsvdir/default
ln -s /etc/sv/dbus rootdir/etc/runit/runsvdir/default/ || true
ln -s /etc/sv/NetworkManager rootdir/etc/runit/runsvdir/default/ || true
ln -s /etc/sv/qrtr-ns rootdir/etc/runit/runsvdir/default/ || true
ln -s /etc/sv/autostart-retro rootdir/etc/runit/runsvdir/default/ || true

# 触控与挂载
mkdir -p rootdir/etc/udev/rules.d/
printf 'ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"\n' > rootdir/etc/udev/rules.d/99-touchscreen-sheng.rules
printf "PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro 0 1\n" > rootdir/etc/fstab

# ========================================================
# 🧹 安全打包
# ==========================================
chroot rootdir xbps-remove -Oo || true

fuser -k -9 -m rootdir || true
sleep 2

umount -l rootdir/dev/pts || true
umount -l rootdir/dev || true
umount -l rootdir/proc || true
umount -l rootdir/sys || true
umount -l rootdir || true
sleep 2
rm -rf rootdir

tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"
SPARSE_IMG="sparse_${ROOTFS_IMG}"
img2simg "$ROOTFS_IMG" "$SPARSE_IMG"
7z a "void_retro_${TIMESTAMP}.7z" "$SPARSE_IMG"
rm -f "$ROOTFS_IMG" "$SPARSE_IMG"

echo "🎉 Void Retro Gaming OS 构建成功！"
