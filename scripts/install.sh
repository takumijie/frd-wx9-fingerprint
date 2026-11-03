#!/usr/bin/env bash
# 安装已构建的包、绑定 spidev、启动 fprintd，并做一次校验
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PKG=$(ls -1t "$ROOT"/fingerprint/packaging/arch/libfprint-goodix51a0-*.pkg.tar.zst 2>/dev/null | head -1)

if [[ -z ${PKG} || ! -f ${PKG} ]]; then
  echo "没有找到构建产物，先运行 scripts/build.sh" >&2
  exit 1
fi

echo "==> 安装 $(basename "$PKG")"
sudo pacman -U --noconfirm "$PKG"

echo "==> 安装 fprintd"
sudo pacman -S --needed --noconfirm fprintd

echo "==> 重新触发 SPI 设备的 udev 规则"
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=spi
sleep 1

echo "==> 启动 fprintd"
sudo systemctl enable --now fprintd
sleep 6

echo
"$ROOT/scripts/verify.sh"
