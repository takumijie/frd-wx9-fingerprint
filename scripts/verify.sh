#!/usr/bin/env bash
# 安装后校验（只读，不需要 root；journal 需要时会自动用 sudo）
set -uo pipefail

fail=0
ok()  { printf 'PASS  %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; fail=1; }
skip(){ printf 'SKIP  %s\n' "$*"; }

echo "FRD-WX9 指纹安装校验"
echo "kernel: $(uname -r)"
echo

# 1. ACPI/SPI 设备
if grep -qs '^acpi:GXFP51A0:' /sys/bus/spi/devices/*/modalias; then
  ok "ACPI 设备 GXFP51A0 存在"
else
  bad "未找到 ACPI 设备 GXFP51A0"
fi

# 2. GPIO 控制器
if readlink -f /sys/bus/gpio/devices/gpiochip0 2>/dev/null | grep -q 'INT3450'; then
  ok "GPIO 控制器是 INT3450"
else
  bad "GPIO 控制器不是 INT3450（本移植不适用）"
fi

# 3. spidev 绑定
drv=$(basename "$(readlink -f /sys/bus/spi/devices/spi-GXFP51A0:00/driver 2>/dev/null)" 2>/dev/null)
if [[ ${drv} == spidev ]]; then
  ok "SPI 设备已绑定 spidev"
else
  bad "SPI 设备未绑定 spidev（当前: ${drv:-无}）"
fi

# 4. 设备节点（编号取决于总线，不写死）
node=$(ls -1 /dev/spidev* 2>/dev/null | head -1)
if [[ -n ${node} && -c ${node} ]]; then
  ok "${node} 存在"
else
  bad "没有 /dev/spidev* 节点"
fi

# 5. 软件包
for p in libfprint-goodix51a0 fprintd; do
  if pacman -Q "$p" >/dev/null 2>&1; then
    ok "$p $(pacman -Q "$p" | awk '{print $2}')"
  else
    bad "$p 未安装"
  fi
done

# 6. 服务
if systemctl is-active --quiet fprintd; then
  ok "fprintd 运行中"
else
  bad "fprintd 未运行"
fi

# 7. 驱动握手日志
if journalctl -u fprintd -b --no-pager >/dev/null 2>&1; then
  J=(journalctl -u fprintd -b --no-pager)
elif sudo -n journalctl -u fprintd -b --no-pager >/dev/null 2>&1; then
  J=(sudo -n journalctl -u fprintd -b --no-pager)
else
  J=()
fi

if ((${#J[@]})); then
  log=$("${J[@]}" 2>/dev/null)
  grep -q 'stage=tls_attempt.*handshake_ok=1' <<<"$log" \
    && ok "TLS 握手成功" || bad "日志中没有 handshake_ok=1"
  grep -q 'stage=full_capture_context.*success=1' <<<"$log" \
    && ok "冷启动准备成功" || bad "日志中没有 full_capture_context success=1"
else
  skip "无权限读取 journal，跳过日志检查（可用 sudo 运行本脚本）"
fi

# 8. D-Bus 设备
if busctl --system call net.reactivated.Fprint /net/reactivated/Fprint/Manager \
     net.reactivated.Fprint.Manager GetDefaultDevice 2>/dev/null | grep -q 'Device/0'; then
  ok "D-Bus 默认设备已就绪"
else
  bad "D-Bus 上没有默认指纹设备"
fi

echo
if ((fail)); then
  echo "结果：有项目未通过，见上。"
  exit 1
fi
echo "结果：全部通过。可以开始录入指纹（见 docs/runbook.md 第 6 节）。"
