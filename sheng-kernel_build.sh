#!/bin/bash
set -e # 遇到任何错误立即停止执行

# 获取通过参数传入的内核版本，默认 7.1
KERNEL_VER="${1:-7.1}"
WORKSPACE="${2:-$(pwd)}"

# 仅在未设置环境变量时配置ccache
if [ -z "$CCACHE_DIR" ]; then
    export CCACHE_DIR="/home/runner/.ccache"
    export CCACHE_MAXSIZE="10G"
    export CCACHE_SLOPPINESS="file_macro,locale,time_macros"
fi

# 确保ccache目录存在
mkdir -p "$CCACHE_DIR"

# 确保ccache优先使用clang
export CC="ccache clang"
export CXX="ccache clang++"
export AR="llvm-ar"
export NM="llvm-nm"
export OBJCOPY="llvm-objcopy"
export OBJDUMP="llvm-objdump"
export READELF="llvm-readelf"
export STRIP="llvm-strip"

echo "🌐 正在克隆你的自定义 sm8550-mainline 仓库..."
# 修改为你的仓库：动态匹配你传入的 7.1 分支 (如 sheng-7.1 或 sm8550-7.1)
# 如果你的分支名就是 7.1 对应名字，请在此处修改。这里默认先尝试拉取分支名包含版本号的分支
if git clone https://github.com/code002-2/sm8550-mainline.git --branch "sheng-${KERNEL_VER}" --depth 1 linux; then
    echo "✅ 成功克隆 sheng-${KERNEL_VER} 分支"
else
    echo "⚠️ 未找到 sheng-${KERNEL_VER} 分支，尝试克隆默认主分支..."
    git clone https://github.com/code002-2/sm8550-mainline.git --depth 1 linux
fi

cd linux

echo "📥 正在下载基础内核配置文件..."
wget https://gitlab.postmarketos.org/alghiffaryfa19/pmaports/-/raw/sheng/device/testing/linux-postmarketos-qcom-sm8550/config-postmarketos-qcom-sm8550.aarch64 -O .config

echo "🔄 正在针对 Linux ${KERNEL_VER} 自动更新老旧配置项..."
# 【重大改进】防止 7.0 配置文件在 7.1 内核上编译时因新选项弹交互提示导致 CI 卡死
make ARCH=arm64 LLVM=1 olddefconfig

echo "🔨 开始编译内核 Image, Image.gz 和设备树..."
# 【改进】显式指定编译 Image.gz，确保后面打包 boot.img 时文件存在
make -j$(nproc) ARCH=arm64 CC="ccache clang" LLVM=1 Image Image.gz dtbs

_kernel_version="$(make kernelrelease -s)"
echo "📦 编译出的内核完整版本号为: ${_kernel_version}"

# 动态修改 deb 包控制文件中的版本
sed -i "s/Version:.*/Version: ${_kernel_version}/" ../linux-xiaomi-sheng/DEBIAN/control

PKGDIR=../linux-xiaomi-sheng
ARCH=arm64

# =========================
# 安装内核和设备树到打包目录
# =========================
mkdir -p $PKGDIR/boot

if [ -f arch/$ARCH/boot/Image.gz ]; then
    install -Dm644 arch/$ARCH/boot/Image.gz $PKGDIR/boot/Image.gz
else
    echo "⚠️ 未找到 Image.gz，尝试手动压缩 Image..."
    gzip -c arch/$ARCH/boot/Image > arch/$ARCH/boot/Image.gz
    install -Dm644 arch/$ARCH/boot/Image.gz $PKGDIR/boot/Image.gz
fi

install -Dm644 arch/$ARCH/boot/dts/qcom/sm8550-xiaomi-sheng.dtb \
    $PKGDIR/boot/sm8550-xiaomi-sheng.dtb

install -Dm644 .config \
    $PKGDIR/boot/config-${_kernel_version}

install -Dm644 System.map \
    $PKGDIR/boot/System.map-${_kernel_version}
    
chmod +x ../mkbootimg

# 拼接内核与 DTB 准备制作 Android 镜像
cat arch/arm64/boot/Image.gz arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb > Image.gz-dtb_sheng

install -Dm644 Image.gz-dtb_sheng \
    $PKGDIR/boot/Image.gz-dtb_sheng

mv Image.gz-dtb_sheng zImage_sheng

echo "📱 正在生成小米平板 6S Pro 双系统与单系统 boot.img..."
../mkbootimg --kernel zImage_sheng --cmdline "root=PARTLABEL=linux" --base 0x00000000 --kernel_offset 0x00008000 --tags_offset 0x01e00000 --pagesize 4096 --id -o ../boot_sheng_dualboot.img
../mkbootimg --kernel zImage_sheng --cmdline "root=PARTLABEL=userdata" --base 0x00000000 --kernel_offset 0x00008000 --tags_offset 0x01e00000 --pagesize 4096 --id -o ../boot_sheng_singleboot.img

echo "🧱 正在安装内核模块..."
make -j$(nproc) ARCH=arm64 CC="ccache clang" LLVM=1 INSTALL_MOD_PATH=../linux-xiaomi-sheng modules_install
rm -rf ../linux-xiaomi-sheng/lib/modules/**/build

cd ..

echo "🧬 正在拉取固件与声音配置依赖..."
git clone https://github.com/map220v/sheng-firmware --depth 1
mkdir -p firmware-xiaomi-sheng/usr/lib/firmware
cp -r sheng-firmware/* firmware-xiaomi-sheng/usr/lib/firmware/
rm -rf sheng-firmware

git clone https://github.com/alghiffaryfa19/alsa-sheng --depth 1
cp -r alsa-sheng/* alsa-xiaomi-sheng/
rm -rf alsa-sheng

echo "📦 正在打包为 .deb 文件..."
dpkg-deb --build --root-owner-group linux-xiaomi-sheng
dpkg-deb --build --root-owner-group firmware-xiaomi-sheng
dpkg-deb --build --root-owner-group alsa-xiaomi-sheng
dpkg-deb --build --root-owner-group sheng-devauth

echo "🎉 所有任务顺利完成！"
