Name:           linux-xiaomi-sheng
Version:        %{kernel_version}
Release:        1%{?dist}
Summary:        Kernel and modules for Xiaomi Pad 6S Pro (sheng)

License:        GPLv2+
BuildArch:      aarch64

Provides:       kernel = %{version}-%{release}

%description
Mainline Linux kernel, modules, and device tree for Xiaomi Pad 6S Pro
(sheng) SM8550 tablet. Built with Clang/LLVM from sm8550-mainline tree.

%install
mkdir -p %{buildroot}/boot
mkdir -p %{buildroot}/usr/lib/modules
mkdir -p %{buildroot}/usr/lib/firmware

cp -a linux-xiaomi-sheng/boot/* %{buildroot}/boot/
cp -a linux-xiaomi-sheng/usr/lib/modules/* %{buildroot}/usr/lib/modules/
cp -a linux-xiaomi-sheng/usr/lib/firmware/* %{buildroot}/usr/lib/firmware/ 2>/dev/null || true

%post
KVER=$(ls %{buildroot}/usr/lib/modules/ 2>/dev/null | head -1)
if [ -n "$KVER" ]; then
    depmod -a "$KVER" 2>/dev/null || true
fi

%files
/boot/*
/usr/lib/modules/*
