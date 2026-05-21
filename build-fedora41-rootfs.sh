#!/bin/bash
set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"
FEDORA_VERSION="41"
FEDORA_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/fedora"

usage() { echo "用法: $0 <kernel_version>"; exit 1; }
[ $# -ne 1 ] && usage
[ "$(id -u)" -ne 0 ] && { echo "请使用root权限运行"; exit 1; }

KERNEL=$1
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="fedora41_${TIMESTAMP}.img"

echo "=========================================="
echo "开始构建 Fedora $FEDORA_VERSION (ARM64) RootFS"
echo "将从 kernel-bundle-$KERNEL 中提取固件并注入"
echo "=========================================="

# --- 准备工作: 提取 kernel-bundle 中的固件 ---
# 1. 创建一个临时目录，用于存放从 kernel-bundle 中提取的所有文件
FW_TEMP_DIR=$(mktemp -d)
# 2. 将当前目录下所有 .deb 包解压到这个临时目录
for deb in *.deb; do
    dpkg-deb -x "$deb" "$FW_TEMP_DIR"
done
# 3. 如果解压后的目录中包含 /lib/firmware，则将其复制出来供后续使用
if [ -d "$FW_TEMP_DIR/lib/firmware" ]; then
    echo "✅ 已从 kernel-bundle 中提取固件"
    FW_SOURCE_DIR="$FW_TEMP_DIR/lib/firmware"
else
    echo "⚠️ 未找到固件目录，将跳过此步骤"
    FW_SOURCE_DIR=""
fi

# 检查固件源目录是否存在，如果不存在，将在后续脚本中跳过复制步骤
# --- 1. 创建空白 ext4 镜像并挂载 ---
rm -rf rootdir || true
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

# --- 2. 使用 dnf 安装基础系统（--installroot 是关键）---
# 注意: dnf 安装时会自动处理依赖关系，确保基础系统是可用的
# --nogpgcheck 跳过GPG签名检查，因为在某些环境下可能会因为缺少密钥而失败
# --forcearch=aarch64 强制指定架构为 ARM64，防止因宿主机架构不同而出错
dnf --installroot=rootdir \
    --releasever=$FEDORA_VERSION \
    --forcearch=aarch64 \
    --nogpgcheck \
    --setopt=reposdir=/dev/null \
    --repofrompath=fedora,$FEDORA_MIRROR/releases/$FEDORA_VERSION/Everything/aarch64/os \
    --repofrompath=fedora-updates,$FEDORA_MIRROR/updates/$FEDORA_VERSION/Everything/aarch64/os \
    install -y \
    systemd sudo dnf kernel-core \
    NetworkManager openssh-server \
    passwd glibc-langpack-en

# --- 3. 注入从 kernel-bundle 中提取的固件（这是整个方案的核心部分）---
if [ -n "$FW_SOURCE_DIR" ]; then
    echo "📡 正在将 kernel-bundle 中的固件合并到 Fedora 系统..."
    # 确保目标固件目录存在
    mkdir -p rootdir/lib/firmware
    # 复制固件文件，如果目标已有同名文件，则覆盖（-f 选项）
    cp -rf $FW_SOURCE_DIR/* rootdir/lib/firmware/
    echo "✅ 固件合并完成"
fi

# --- 4. 挂载虚拟文件系统（用于后续的系统配置，如 systemctl enable）---
# 这一步是必要的，因为后续的 systemctl 命令需要在 chroot 环境中执行
mount --bind /dev rootdir/dev
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

# --- 5. 配置系统环境（设置语言、主机名、root密码等）---
chroot rootdir /bin/bash -c "echo 'LANG=en_US.UTF-8' > /etc/locale.conf"
chroot rootdir /bin/bash -c "echo 'fedora41' > /etc/hostname"
chroot rootdir /bin/bash -c "echo -e '1234\n1234' | passwd root"
chroot rootdir systemctl enable NetworkManager sshd

# --- 6. 创建普通用户 ---
chroot rootdir useradd -m -s /bin/bash luser
chroot rootdir bash -c "echo 'luser:luser' | chpasswd"
chroot rootdir usermod -aG wheel luser

# --- 7. 安装桌面环境（以 GNOME 为例，可根据需要注释或替换）---
# 如果你想构建一个没有图形界面的最小化系统，可以将这一整段注释掉
chroot rootdir dnf groupinstall -y "GNOME Desktop" "GNOME Applications" "Standard"
chroot rootdir systemctl set-default graphical.target
chroot rootdir systemctl enable gdm

# --- 8. 清理不必要的文件以减小镜像体积---
chroot rootdir dnf clean all
rm -rf rootdir/var/cache/dnf
rm -rf rootdir/tmp/*.deb 2>/dev/null || true

# --- 9. 清理临时固件目录并卸载文件系统 ---
rm -rf "$FW_TEMP_DIR"

# 等待片刻，确保所有写入操作完成
sync; sleep 2
umount rootdir/dev rootdir/proc rootdir/sys 2>/dev/null || true
umount rootdir || true
rm -rf rootdir

# 为生成的镜像文件设置一个固定的 UUID，方便以后挂载
tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"

echo "✅ 镜像生成: $ROOTFS_IMG"
echo "🗜️ 压缩中..."
7z a "${ROOTFS_IMG}.7z" "$ROOTFS_IMG"
echo "🎉 完成！输出: ${ROOTFS_IMG}.7z"
