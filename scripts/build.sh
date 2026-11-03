#!/usr/bin/env bash
# 构建 libfprint-goodix51a0 包（不需要 root）
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT/fingerprint/packaging/arch"

command -v makepkg >/dev/null || { echo "缺少 makepkg（请安装 base-devel）" >&2; exit 1; }
pacman -Q libgusb >/dev/null 2>&1 || { echo "缺少 libgusb：sudo pacman -S libgusb" >&2; exit 1; }

makepkg -f "$@"

echo
echo "构建完成："
ls -1t libfprint-goodix51a0-*.pkg.tar.zst | head -1
