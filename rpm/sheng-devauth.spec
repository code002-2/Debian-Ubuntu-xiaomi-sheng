Name:           sheng-devauth
Version:        1.0
Release:        1%{?dist}
Summary:        Xiaomi Keyboard authentication service

License:        GPLv2+
BuildArch:      noarch

Requires:       systemd

%description
Systemd service that pairs with a kernel driver to authenticate
the Xiaomi Pad 6S Pro keyboard cover.

%install
mkdir -p %{buildroot}/usr/lib/systemd/system
cp -a sheng-devauth/usr/lib/systemd/system/* %{buildroot}/usr/lib/systemd/system/

%post
%systemd_post sheng-devauth.service

%preun
%systemd_preun sheng-devauth.service

%files
/usr/lib/systemd/system/sheng-devauth.service
