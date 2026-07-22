Name:           sheng-sensors
Version:        20240917
Release:        1%{?dist}
Summary:        Sensor configuration files for Xiaomi Pad 6S Pro

License:        Proprietary
BuildArch:      noarch

%description
Proprietary sensor configuration files for Xiaomi Pad 6S Pro (sheng).

%install
mkdir -p %{buildroot}
cp -a sheng-sensors/usr %{buildroot}/

%files
/usr/*
