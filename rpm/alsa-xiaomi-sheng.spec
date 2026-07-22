Name:           alsa-xiaomi-sheng
Version:        1.0
Release:        1%{?dist}
Summary:        ALSA UCM2 configuration for Xiaomi Pad 6S Pro

License:        BSD
BuildArch:      noarch

Requires:       alsa-ucm-conf

%description
ALSA Use Case Manager v2 configuration files for Xiaomi Pad 6S Pro (sheng)
SM8550 tablet audio subsystem, including speaker profiles and routing.

%install
mkdir -p %{buildroot}/usr/share/alsa/ucm2
cp -a alsa-xiaomi-sheng/usr/share/alsa/ucm2/* %{buildroot}/usr/share/alsa/ucm2/

%files
/usr/share/alsa/ucm2/*
