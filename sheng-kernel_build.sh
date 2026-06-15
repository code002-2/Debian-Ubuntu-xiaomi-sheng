#!/bin/bash
set -e

# ==========================================
# 1. 编译缓存 (ccache) 与 LLVM 工具链配置
# ==========================================
if [ -z "$CCACHE_DIR" ]; then
    export CCACHE_DIR="/home/runner/.ccache"
    export CCACHE_MAXSIZE="10G"
    export CCACHE_SLOPPINESS="file_macro,locale,time_macros"
fi

mkdir -p "$CCACHE_DIR"

export CC="ccache clang"
export CXX="ccache clang++"
export AR="llvm-ar"
export NM="llvm-nm"
export OBJCOPY="llvm-objcopy"
export OBJDUMP="llvm-objdump"
export READELF="llvm-readelf"
export STRIP="llvm-strip"

# ==========================================
# 2. 拉取内核源码 (默认使用 sheng-mainline 分支)
# ==========================================
git clone https://github.com/code002-2/sm8550-mainline.git --branch sheng-mainline --depth 1 linux
cd linux

# ==========================================
# 3. 智能定位并应用内核配置文件 (.config)
# ==========================================
echo "⚙️ 正在智能定位并配置内核..."
CONFIG_PATH=$(find "$GITHUB_WORKSPACE" ../ -maxdepth 2 -name "config*.aarch64*" 2>/dev/null | head -n 1)

if [ -n "$CONFIG_PATH" ]; then
    echo "✅ 成功找到并复制配置文件: $CONFIG_PATH"
    cp "$CONFIG_PATH" .config
else
    echo "⚠️ 未找到动态配置文件，尝试使用后备默认配置..."
    cp ../config-postmarketos-qcom-sm8550.aarch64 .config || { echo "❌ 致命错误: 找不到任何配置文件！"; exit 1; }
fi

# ==========================================
# 🚀 3.5 暴力修复区 (解决 7.1 卡死与节点报错)
# ==========================================
echo "🛠️ 正在暴力修复 Config 文件以适配 7.1..."
# 此时配置已经被复制到了 .config，我们直接改 .config
sed -i 's/Linux\/arm64 7.0.0/Linux\/arm64 7.1.0/g' .config || true
echo "# CONFIG_ACPI_APEI_GHES_NVIDIA is not set" >> .config
echo "CONFIG_DRIVER_DEFERRED_PROBE_TIMEOUT=10" >> .config

echo "🛠️ 正在剔除冲突的 hamoa 开发板设备树..."
sed -i '/hamoa-iot-evk.dtb/d' arch/arm64/boot/dts/qcom/Makefile || true
# ==========================================

# ==========================================
# 4. 极速编译内核
# ==========================================
echo "🔨 开始使用 LLVM Clang 编译内核..."

# ⬇️ 新加这一行：自动静默填补所有 7.1 新增配置的默认值，彻底堵住提问卡死！
make olddefconfig ARCH=arm64

# 下面是你原本的编译命令，保持不变
make -j$(nproc) ARCH=arm64 CC="ccache clang" LLVM=1
_kernel_version="$(make kernelrelease -s)"


# ==========================================
# 5. 提取产物并注入打包目录
# ==========================================
PKGDIR=../linux-xiaomi-sheng
ARCH=arm64

mkdir -p $PKGDIR/boot

install -Dm644 arch/$ARCH/boot/Image.gz \
    $PKGDIR/boot/Image.gz

install -Dm644 arch/$ARCH/boot/dts/qcom/sm8550-xiaomi-sheng.dtb \
    $PKGDIR/boot/sm8550-xiaomi-sheng.dtb

install -Dm644 .config \
    $PKGDIR/boot/config-${_kernel_version}

install -Dm644 System.map \
    $PKGDIR/boot/System.map-${_kernel_version}
    
chmod +x ../mkbootimg

# ==========================================
# 6. 打包 Android 规范的 boot.img (包含全局防黑屏补丁)
# ==========================================
cat arch/arm64/boot/Image.gz arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb > Image.gz-dtb_sheng

install -Dm644 Image.gz-dtb_sheng \
    $PKGDIR/boot/Image.gz-dtb_sheng

mv Image.gz-dtb_sheng zImage_sheng

../mkbootimg --kernel zImage_sheng --cmdline "root=PARTLABEL=linux rootwait rw" --base 0x00000000 --kernel_offset 0x00008000 --tags_offset 0x01e00000 --pagesize 4096 --id -o ../boot_sheng_dualboot.img
../mkbootimg --kernel zImage_sheng --cmdline "root=PARTLABEL=userdata rootwait rw" --base 0x00000000 --kernel_offset 0x00008000 --tags_offset 0x01e00000 --pagesize 4096 --id -o ../boot_sheng_singleboot.img

# ==========================================
# 7. 编译内核模块并清理冗余链接 (减小 deb 包体积)
# ==========================================
make -j$(nproc) ARCH=arm64 CC="ccache clang" LLVM=1 INSTALL_MOD_PATH=../linux-xiaomi-sheng modules_install

echo "🧹 正在清理冗余的 build 和 source 软链接..."
rm -rf ../linux-xiaomi-sheng/lib/modules/*/build || true
rm -rf ../linux-xiaomi-sheng/lib/modules/*/source || true

cd ..

# ==========================================
# 8. 打包各种外设固件 (Wi-Fi, 蓝牙, 触屏等)
# ==========================================
echo "📦 正在拉取并构建固件与音频补丁包..."

git clone https://github.com/map220v/sheng-firmware
mkdir -p firmware-xiaomi-sheng/usr/lib/firmware
cp -r sheng-firmware/* firmware-xiaomi-sheng/usr/lib/firmware/

git clone https://github.com/alghiffaryfa19/alsa-sheng
cp -r alsa-sheng/* alsa-xiaomi-sheng/

dpkg-deb --build --root-owner-group linux-xiaomi-sheng
dpkg-deb --build --root-owner-group firmware-xiaomi-sheng
dpkg-deb --build --root-owner-group alsa-xiaomi-sheng
dpkg-deb --build --root-owner-group sheng-devauth

echo "🎉 终极通用版内核与驱动打包圆满完成！"
