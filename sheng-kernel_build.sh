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

git clone https://github.com/code002-2/sm8550-mainline.git --branch sheng-mainline --depth 1 linux
cd linux

cp ../sm8550.config .config

make -j$(nproc) ARCH=arm64 CC="ccache clang" LLVM=1
_kernel_version="$(make kernelrelease -s)"


sed -i "s/Version:.*/Version: ${_kernel_version}/" ../linux-xiaomi-sheng/DEBIAN/control

PKGDIR=../linux-xiaomi-sheng
ARCH=arm64

# =========================
# Install kernel images
# =========================
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

cat arch/arm64/boot/Image.gz arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb > Image.gz-dtb_sheng

install -Dm644 Image.gz-dtb_sheng \
    $PKGDIR/boot/Image.gz-dtb_sheng

mv Image.gz-dtb_sheng zImage_sheng
../mkbootimg --kernel zImage_sheng --cmdline "root=PARTLABEL=linux" --base 0x00000000 --kernel_offset 0x00008000 --tags_offset 0x01e00000 --pagesize 4096 --id -o ../boot_sheng_dualboot.img
../mkbootimg --kernel zImage_sheng --cmdline "root=PARTLABEL=userdata" --base 0x00000000 --kernel_offset 0x00008000 --tags_offset 0x01e00000 --pagesize 4096 --id -o ../boot_sheng_singleboot.img

#rm $1/linux-xiaomi-sheng/usr/dummy

make -j$(nproc) ARCH=arm64 CC="ccache clang" LLVM=1 INSTALL_MOD_PATH=../linux-xiaomi-sheng modules_install
rm ../linux-xiaomi-sheng/lib/modules/**/
cd ..

echo "📥 正在从上游拉取最新的固件文件..."
git clone --depth 1 https://github.com/lzxcr/linux-firmware-sheng.git /tmp/temp_fw

echo "🔧 正在将固件注入打包目录，并强制转入 /usr/lib..."
mkdir -p firmware-xiaomi-sheng/usr/lib
if [ -d "/tmp/temp_fw/lib" ]; then
    cp -r /tmp/temp_fw/lib/* firmware-xiaomi-sheng/usr/lib/
else
    cp -r /tmp/temp_fw/* firmware-xiaomi-sheng/usr/lib/ 2>/dev/null || true
fi
rm -rf /tmp/temp_fw

mkdir -p alsa-xiaomi-sheng/usr/share/alsa/ucm2
git clone --depth 1 https://github.com/map220v/alsa-ucm-conf.git /tmp/temp_alsa

# 智能识别上游 UCM2 的结构并安全提取至包内
if [ -d "/tmp/temp_alsa/ucm2" ]; then
    cp -r /tmp/temp_alsa/ucm2/* alsa-xiaomi-sheng/usr/share/alsa/ucm2/
else
    cp -r /tmp/temp_alsa/* alsa-xiaomi-sheng/usr/share/alsa/ucm2/ 2>/dev/null || true
fi
rm -rf /tmp/temp_alsa

echo "🔧 正在对内核及音频模块进行安全级 UsrMerge 路径融合..."
for pkg in linux-xiaomi-sheng alsa-xiaomi-sheng; do
    if [ -d "$pkg/lib" ]; then
        echo "✅ 正在安全融合 $pkg 中的 /lib 至 /usr/lib..."
        mkdir -p "$pkg/usr/lib"
        cp -r "$pkg/lib"/* "$pkg/usr/lib/" 2>/dev/null || true
        rm -rf "$pkg/lib"
        echo "🧹 $pkg 的老式 /lib 目录已安全移除"
    fi
done

echo "📦 开始构建符合全平台规范的 .deb 文件..."
dpkg-deb --build --root-owner-group linux-xiaomi-sheng
dpkg-deb --build --root-owner-group firmware-xiaomi-sheng
dpkg-deb --build --root-owner-group alsa-xiaomi-sheng
dpkg-deb --build --root-owner-group sheng-devauth

echo "🎉 核心编译、固件注入与音频重组打包全线通关！"
