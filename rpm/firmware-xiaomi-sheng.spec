Name:           firmware-xiaomi-sheng
Version:        1.0
Release:        1%{?dist}
Summary:        Firmware blobs for Xiaomi Pad 6S Pro (sheng)

License:        Proprietary
BuildArch:      noarch

Conflicts:      linux-firmware
Provides:       linux-firmware

%description
Firmware blobs and configuration files for Xiaomi Pad 6S Pro (sheng)
SM8550 tablet, including:
  - Novatek NT36532E panel firmware
  - Nanosic touch controller firmware
  - Cirrus Logic CS35L43 audio DSP firmware
  - Qualcomm WiFi (ath12k/WCN7850) board files
  - Audio topology firmware (tplg)

%install
mkdir -p %{buildroot}/usr/lib/firmware
cp -a firmware-xiaomi-sheng/usr/lib/firmware/* %{buildroot}/usr/lib/firmware/

%files
/usr/lib/firmware/*
