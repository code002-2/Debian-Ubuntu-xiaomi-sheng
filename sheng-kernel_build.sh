#!/bin/bash
set -e

# ==========================================
# 1. 编译缓存 (ccache) 与 LLVM 工具链配置
# ==========================================
export CCACHE_DIR="/home/runner/.ccache"
export CCACHE_MAXSIZE="10G"
export CCACHE_SLOPPINESS="file_macro,locale,time_macros"
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
# 2. 拉取内核源码
# ==========================================
git clone https://github.com/code002-2/sm8550-mainline.git --branch sheng-mainline --depth 1 linux
cd linux

# ==========================================
# 3. 自动生成并命名 sm8550.config (核心逻辑)
# ==========================================
echo "⚙️ 正在定位基准配置..."
# 优先查找你仓库里的 config 文件
CONFIG_PATH=$(find "$GITHUB_WORKSPACE" ../ -maxdepth 2 -name "config*.aarch64*" 2>/dev/null | head -n 1)

if [ -n "$CONFIG_PATH" ]; then
    echo "✅ 发现基准配置，正在复制..."
    cp "$CONFIG_PATH" .config
else
    echo "⚠️ 未找到基准配置，请检查仓库路径。"
    exit 1
fi

echo "🛠️ 执行 olddefconfig 以适配 7.1 并剔除无效设备树..."
# 自动填补 7.1 新增项，彻底消灭 Error in reading
make ARCH=arm64 olddefconfig

# 踢掉报错的无效开发板设备树
sed -i '/hamoa-iot-evk.dtb/d' arch/arm64/boot/dts/qcom/Makefile || true

# 导出生成的配置
cp .config ../sm8550.config
echo "🎉 成功生成配置: sm8550.config 已存入仓库根目录"

# ==========================================
# 🛑 强制终止：不再往下编译
# ==========================================
echo "🛑 任务完成：已生成 sm8550.config，停止编译。"
exit 0
