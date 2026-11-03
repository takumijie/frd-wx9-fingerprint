#!/usr/bin/env bash
# probe-gxfp51a0.sh — 只读取证：确认 HONOR FRD-WX9 上的 GXFP51A0 能否复用
# huawei-matebook-13-linux 的指纹驱动，并推导需要改写的 GPIO 常量。
#
# 用法：  sudo ./probe-gxfp51a0.sh
# 不做任何写操作：不解绑设备、不加载驱动、不触碰 GPIO 电平、不安装软件。

set -uo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "需要 root（读取 DSDT 与 debugfs）：sudo $0" >&2
  exit 1
fi

work=$(mktemp -d /tmp/gxfp-probe.XXXXXX)
trap 'rm -rf "$work"' EXIT

echo "=============================================================="
echo " 1. GPIO 控制器（驱动按 label 前缀找芯片）"
echo "=============================================================="
gpio_label=""
for g in /sys/bus/gpio/devices/*; do
  [[ -e $g ]] || continue
  lbl=$(cat "$g/label" 2>/dev/null)
  n=$(cat "$g/ngpio" 2>/dev/null)
  [[ -z $gpio_label && -n $lbl ]] && gpio_label=$lbl
  printf '  %-12s label=%-14s lines=%-5s <- %s\n' \
    "$(basename "$g")" "${lbl:-?}" "${n:-?}" "$(readlink -f "$g")"
done
[[ -n $gpio_label ]] || echo "  (未能读取 label)"

echo
echo "=============================================================="
echo " 2. ACPI / SPI 设备状态"
echo "=============================================================="
for m in /sys/bus/spi/devices/*/modalias; do
  grep -q '^acpi:GXFP51A0:' "$m" 2>/dev/null || continue
  s=$(dirname "$m")
  echo "  设备: $(basename "$s")"
  echo "  modalias: $(cat "$m")"
  if [[ -L $s/driver ]]; then
    echo "  已绑定驱动: $(basename "$(readlink -f "$s/driver")")"
  else
    echo "  已绑定驱动: (无，符合预期)"
  fi
done

echo
echo "=============================================================="
echo " 3. 内核日志中的指纹/Goodix 记录"
echo "=============================================================="
dmesg 2>/dev/null | grep -iE 'gxfp|goodix|INT3450' | tail -n 15 || echo "  (无)"

echo
echo "=============================================================="
echo " 4. 解编译 ACPI 表并提取 GXFP51A0 的 _CRS GPIO 引脚"
echo "=============================================================="
cd "$work" || exit 1
acpidump -o tables.dat >/dev/null 2>&1
acpixtract -a tables.dat >/dev/null 2>&1
for f in *.dat; do
  [[ -e $f ]] || continue
  iasl -d "$f" >/dev/null 2>&1
done

python3 - "$work" "$gpio_label" "${GXFP_IRQ_LINE:-}" <<'PY'
import os, pathlib, re, sys

root = pathlib.Path(sys.argv[1])
label = sys.argv[2] if len(sys.argv) > 2 else ""

def block_of(text, name):
    m = re.search(r'Device\s*\(\s*' + re.escape(name) + r'\s*\)', text)
    if not m:
        return None
    i = text.find('{', m.end())
    if i < 0:
        return None
    depth = 0
    for j in range(i, len(text)):
        c = text[j]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return text[i + 1:j]
    return None

def pins(block):
    out = {}
    for kind in ('GpioInt', 'GpioIo'):
        for m in re.finditer(kind + r'\s*\(', block):
            depth = 0
            i = m.end() - 1
            for j in range(i, len(block)):
                if block[j] == '(':
                    depth += 1
                elif block[j] == ')':
                    depth -= 1
                    if depth == 0:
                        close = j
                        break
            else:
                continue
            lb = block.find('{', close)
            if lb < 0:
                continue
            rb = block.find('}', lb)
            body = block[lb + 1:rb]
            hexes = re.findall(r'0x([0-9A-Fa-f]+)', body)
            args = re.sub(r'\s+', ' ', block[m.end():close]).strip()
            for h in hexes:
                out.setdefault(kind, []).append(int(h, 16))
            out.setdefault(kind + '_args', []).append(args)
    return out

found = False
irq_pin = None
reset_pin = None
for dsl in sorted(root.glob('*.dsl')):
    text = dsl.read_text(errors='replace')
    if 'GXFP51A0' not in text and 'FPNT' not in text:
        continue
    for name in ('FPNT', 'GXFP'):
        blk = block_of(text, name)
        if not blk:
            continue
        found = True
        print(f"  找到 Device ({name}) 于 {dsl.name}")
        p = pins(blk)
        if 'GpioInt' in p:
            for n in p['GpioInt']:
                if irq_pin is None:
                    irq_pin = n
                print(f"    IRQ   GpioInt -> GPIO {n} (0x{n:03x})")
                for a in p['GpioInt_args']:
                    print(f"          args: {a}")
        if 'GpioIo' in p:
            for n in p['GpioIo']:
                if reset_pin is None:
                    reset_pin = n
                print(f"    RESET GpioIo  -> GPIO {n} (0x{n:03x})")
                for a in p['GpioIo_args']:
                    print(f"          args: {a}")
        if not p:
            print("    (该 Device 内未直接找到 GpioInt/GpioIo；_CRS 可能拆分在别处)")
        # 打印 _CRS 方法体辅助核对
        m = re.search(r'Method\s*\(_CRS.*?\n', blk)
        if m:
            print("    --- _CRS 片段 ---")
            start = m.start()
            seg = blk[start:start + 900]
            for line in seg.splitlines()[:24]:
                print("    " + line.rstrip())
        break
    if found:
        break

if not found:
    print("  (未找到 Device(FPNT)/GXFP；尝试全局搜索 GXFP51A0 上下文)")
    for dsl in sorted(root.glob('*.dsl')):
        text = dsl.read_text(errors='replace')
        for m in re.finditer(r'GXFP51A0', text):
            print(f"  {dsl.name}: ...{text[max(0,m.start()-200):m.start()+200]}...")
            break

print()
print("==============================================================")
print(" 5. 结论：需要改写的常量")
print("==============================================================")
prefix = (label[:7] if label else 'INT3450')
print(f"  gx51_transport.c:  strncmp(info.label, \"{prefix}\", 7)")
if irq_pin is not None:
    print(f"  gx51_transport.h:  #define GX51_EXPECTED_HWIRQ {irq_pin}u")
else:
    print("  gx51_transport.h:  #define GX51_EXPECTED_HWIRQ <未解析到 GpioInt>")
if reset_pin is not None:
    print(f"  gx51_transport.h:  #define GX51_RESET_LINE   {reset_pin}u")
else:
    print("  gx51_transport.h:  #define GX51_RESET_LINE   <未解析到 GpioIo>")
PY

echo
echo "=============================================================="
echo " 6. 已占用该传感器的 GPIO 行（若有）"
echo "=============================================================="
grep -i -A2 'gxfp\|GXFP' /sys/kernel/debug/gpio 2>/dev/null || echo "  (debugfs 未挂载或无匹配)"

echo
echo "完成。请把第 4、5 节输出贴回。"
