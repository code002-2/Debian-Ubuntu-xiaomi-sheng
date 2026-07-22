# Debian / Ubuntu for Xiaomi Pad 6S Pro

Debian 13 (Trixie) 和 Ubuntu 26.04 (aarch64) rootfs 构建系统，面向小米平板 6S Pro 12.4 (SM8550, 代号 "sheng")。

基于 debootstrap 构建，支持多桌面环境。

属于 [Xiaomi Pad 6S Pro Linux](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux) 项目的一部分。

## 支持的桌面环境

| 桌面 | 状态 |
|------|------|
| GNOME | 稳定 |
| KDE Plasma | 稳定 |
| XFCE | 测试 |

## 构建

```bash
# Debian 13 / GNOME
sudo bash sheng-rootfs_build.sh debian-desktop 7.1 all gnome

# Ubuntu 26.04 / KDE
sudo bash build-ubuntu26-rootfs.sh ubuntu-desktop 7.1 all kde

# 自定义凭据
ROOT_PASS="mypass" USER_PASS="mypass" USER_NAME="myuser" \
sudo bash sheng-rootfs_build.sh debian-desktop 7.1 all gnome
```

## 默认凭据

| 账户 | 用户名 | 密码 |
|------|--------|------|
| 普通用户 | `luser` | `luser` |
| root | `root` | `1234` |

## 功能状态

参见 [主项目 Wiki](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki)

[![Telegram](https://img.shields.io/badge/Telegram-%40Pad_6S_Pro_Linux_Chat-blue?logo=telegram)](https://t.me/Pad_6S_Pro_Linux_Chat)
