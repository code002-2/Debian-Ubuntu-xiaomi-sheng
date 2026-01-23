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

git clone https://github.com/map220v/sm8550-mainline.git --branch sheng-6.18 --depth 1 linux
cd linux

make -j$(nproc) ARCH=arm64 CC="ccache clang" LLVM=1 defconfig sm8550.config
make -j$(nproc) ARCH=arm64 CC="ccache clang" LLVM=1
_kernel_version="$(make kernelrelease -s)"

sed -i "s/Version:.*/Version: ${_kernel_version}/" $1/linux-xiaomi-sheng/DEBIAN/control

chmod +x $2/mkbootimg

cat $2/linux/arch/arm64/boot/Image.gz $2/linux/arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb > $2/linux/Image.gz-dtb_sheng
mv $2/linux/Image.gz-dtb_sheng $2/linux/zImage_sheng
$2/mkbootimg --kernel zImage_sheng --cmdline "root=PARTLABEL=linux" --base 0x00000000 --kernel_offset 0x00008000 --tags_offset 0x01e00000 --pagesize 4096 --id -o $2/boot_sheng.img

#rm $1/linux-xiaomi-sheng/usr/dummy
make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH=$1/linux-xiaomi-sheng/usr modules_install
rm $2/linux-xiaomi-sheng/usr/lib/modules/**/build
cd $2
rm -rf linux
cd ..

dpkg-deb --build --root-owner-group linux-xiaomi-sheng
dpkg-deb --build --root-owner-group firmware-xiaomi-sheng
dpkg-deb --build --root-owner-group alsa-xiaomi-sheng
