# HONOR FRD-WX9 指纹驱动移植记录

> 适用范围：**仅限 HONOR FRD-WX9（HONOR HUNTER，Comet Lake-H）这一台机器**。
> 本文记录把 [GodsQuantum/huawei-matebook-13-linux](https://github.com/GodsQuantum/huawei-matebook-13-linux)
> 的 Goodix GXFP51A0 指纹驱动移植到本机的完整推导、改动与验证过程。
> 记录时间：2026-11-03。
>
> 需要在一台同型号设备上照抄执行时，使用配套的 [runbook.md](runbook.md)；
> 本文侧重"为什么这样改"，手册侧重"照着做"。

---

## 0. 结论

**可以移植，且已在本机跑通。** 但不是"装上就能用"：传感器、协议、发行版版本都对得上，
真正的障碍是**驱动里写死了参考机 MateBook 13 的 GPIO 控制器与引脚号**，而本机的取值完全不同，
且这两个引脚号在 ACPI 表里是**运行时才被填入的占位符**，无法靠读 DSDT 静态文本得到。

最终状态（本机实测）：

| 项目 | 结果 |
|---|---|
| 传感器识别 | `Goodix GXFP51A0 SPI (ST411 / experimental)` |
| 固件版本读取 | 成功（`stage=fw_version elapsed_ms=13`） |
| TLS 握手 | 成功（`config_ok=1 handshake_ok=1 handshake_ms=53`） |
| 冷启动准备 | 成功（首次 `full_capture_context elapsed_ms=3952`；PMK 缓存建立后 2075 ms） |
| 热态就绪 | `FAST_READY in 89 ms` |
| D-Bus 设备 | `/net/reactivated/Fprint/Device/0`（默认设备） |

---

## 1. 目标设备

| 项 | 值 |
|---|---|
| 厂商 / 型号 | HONOR / FRD-WX9（product family: HONOR HUNTER）|
| 主板 | FRD-WX9-PCB |
| BIOS | 3.06（2022-03-11）|
| CPU | Intel Core i5-10300H（Comet Lake-H，4C/8T）|
| 系统 | Arch Linux（rolling）|
| 内核 | 7.2.14-zen1-1-zen |
| 桌面 | KDE Plasma 6.8.2 + SDDM（Wayland，tty1）|

### 指纹传感器

| 项 | 值 |
|---|---|
| ACPI HID | `GXFP51A0`（`_CID` 相同，`_UID=1`）|
| ACPI 路径 | `\_SB.PCI0.SPI1.FPNT` |
| 总线 | SPI1（Intel LPSS，`pxa2xx-spi`），mode 0，10 MHz，四线 |
| 检测 | / 芯片 | Goodix GXFP51A0 / GF3658 Milan ST411，chip-id `0x2504` |
| 参考固件 | `GF_ST411SEC_APP_14115`（本机校验通过）|
| 功耗 | 无独立电源 GPIO（ACPI 未声明），复位线兼作上电控制 |

---

## 2. 上游项目与基线

| 项 | 值 |
|---|---|
| 上游仓库 | `https://github.com/GodsQuantum/huawei-matebook-13-linux` |
| 本仓库 | `fingerprint/`（vendored 子树）|
| 基线提交 | `0eebade95521dc17317235a1b27017ad73f44c16`（2026-11-02）|
| 移植范围 | 仅 `fingerprint/` 子目录中的驱动与安装路径 |
| 参考机型 | Huawei MateBook 13（WRTB-WXX9），全部硬件验证仅此一台 |

**项目状态提示**：上游自述为 QA 候选（`rel71.74` / QA59），S4 休眠未认证、
第一触成功率在参考机上也不稳定（`HALL_OF_FAME.md` 有多版本回归记录）。
本移植只验证到"设备可用、握手成功"，**不代表登录场景已可靠**。

**不要执行仓库根目录的 `./install.sh`**：那是 MateBook 的 GPU 电源管理器，
要求 NVIDIA MX250（`10de:1d13`）与私有 R580 驱动，本机是 GTX 1660 Ti Mobile，逻辑不适用。

---

## 3. 兼容性判定过程

### 3.1 初步匹配（全部通过）

- `acpi:GXFP51A0:` 存在于 `/sys/bus/spi/devices/spi-GXFP51A0:00/modalias` → 安装脚本的硬门槛通过。
- 传感器型号与上游支持列表一致（GXFP51A0 / GF3658 ST411）。
- Arch 官方 `libfprint` 恰为 `1.94.100-1`，与驱动锁定的 `v1.94.100` 完全一致。
- 纯用户态驱动（libfprint 插件 + `spidev` + GPIO chardev），**不需要内核模块/DKMS**，
  7.2 内核不构成障碍；`CONFIG_GPIO_CDEV=y`、`CONFIG_SPI_SPIDEV=m` 均满足。
- 设备当前无驱动绑定，`/sys/bus/spi/devices/spi-GXFP51A0:00/driver_override` 为空，可直接交给 udev 规则。

### 3.2 决定性差异一：GPIO 控制器

驱动 `gx51_transport.c: gx51_open_int34bb()` 遍历 `/dev/gpiochipN`，用
`strncmp(info.label, "INT34BB", 7)` 认芯片。

本机 `gpiochip0` 的父 ACPI 设备是 **`INT3450`**（路径 `\_SB.PCI0.GPI0`），
`gpiochip0: 364 GPIOs, parent: platform/INT3450:00, INT3450:00:`。
`INT34BB` 是参考机那代 LP 平台的 PCH，本机 Comet Lake-H 用 `INT3450`。

→ 不改这一处，驱动**找不到 GPIO 芯片**，设备 open 直接失败。

### 3.3 决定性差异二：引脚号是运行时占位符（关键陷阱）

DSDT 里 `FPNT._CRS` 字面上写的是：

```
GpioInt (Level, ActiveHigh, ExclusiveAndWake, PullDefault, ...) { 0x0000 }
GpioIo  (Exclusive, PullUp, ..., IoRestrictionOutputOnly, ...)   { 0x0008 }
```

看似 IRQ=0、RESET=8。但同一个 `_CRS` 方法在返回前做了：

```asl
CreateWordField (BBUF, 0x63, SPIN)
CreateWordField (BBUF, 0x3B, GPIN)
SPIN = GNUM (GFPS)
GPIN = GNUM (GFPI)
```

即两个引脚列表在运行时被 `GNUM()` 覆盖。`GNUM` 定义：

```asl
Method (GNUM, 1) {
    Local0 = GNMB (Arg0)          // 低 16 位：组内偏移
    Local1 = GGRP (Arg0)          // 第 16-23 位：组号
    Return ((GINF (Local1, 0x06) + Local0))
}
Method (GINF, 2) {
    If ((PCHS == PCHL)) { Return (DerefOf (DerefOf (GPCL [Arg0]) [Arg1])) }
    Else                { Return (DerefOf (DerefOf (GPCH [Arg0]) [Arg1])) }
}
```

`GINF(group, 6)` 取的是 `GPCH[group][6]`，即该组的**全局 GPIO 基址**。
本机 `\_SB.PCI0.GPI0._HID` 返回 `INT3450`（`PCHS == PCHH`），因此走 `GPCH` 表。

> 用 SPIN/GPIN 的字节偏移与描述符布局交叉验证：`0x3B` 落在 GpioInt 的引脚表、
> `0x63` 落在 GpioIo 的引脚表，因此 **GPIN = 中断脚，SPIN = 复位/上电脚**。
> 旁证：模板里的 SPI DeviceSelection 为 0，内核实际生成的是 `/dev/spidev1.0`（CS=0），
> 说明 `SPIN` 不是 SPI 片选字段。

### 3.4 推导真实引脚

`GFPI` / `GFPS` 是 BIOS 写在 ACPI NVS（GNVS 区）里的 32 位字段，只能运行时读：

| 项 | 值 |
|---|---|
| GNVS OperationRegion | 物理地址 `0x8FB83298`，长度 `0x07FA` |
| GFPS 偏移 | `0x465` |
| GFPI 偏移 | `0x469` |

本机实测值：

```
GFPS = 0x03040003  → group = 4, offset = 3
GFPI = 0x0302000F  → group = 2, offset = 15
```

`GPCH` 各组基址（第 7 个元素）：

| group | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| base | 0 | 32 | 64 | 96 | 256 | 288 | 128 | 224 | 320 | 352 | 192 |

计算结果：

```
中断脚  = base(2) + 15 = 64 + 15 = 79
复位脚  = base(4) + 3  = 256 + 3 = 259
```

**交叉验证**：触控板（`TPDG`）的 GpioInt 同样用 offset 15，`GFPI` 在 group 1，
`base(1)+15 = 32+15 = 47`，与内核 `/sys/kernel/debug/gpio` 中的
`gpio-47 ( |TPDG GpioInt(0) ) in hi IRQ ACTIVE LOW` 完全吻合，证明换算方式正确。

对应的物理焊盘（`/sys/kernel/debug/pinctrl/INT3450:00/pins`）：

| GPIO | pin | 焊盘名 | 状态 |
|---|---|---|---|
| 79 | 66 | `UART1_CTSB` | GPIO，未占用 |
| 259 | 206 | `CPU_GP_0` | GPIO，未占用 |

> 注意：`pins` 文件里引脚索引与 GPIO 号不是一回事（例如 pin 47 对应 gpio 54），
> 计算时必须用 GPIO 号，不能用焊盘索引。

### 3.5 复位极性：实测推翻推断

ACPI 把复位脚声明为 `PullUp`，据此曾推断为低有效——**错误**。
用独立探针（见附录）对四种组合做了实测，只有一种能拿到传感器响应：

| assert 电平 | CS_HIGH | 结果 |
|---|---|---|
| 0（低有效）| 1 | MISO 全 `FF`，无响应 |
| **1（高有效）** | **1** | **`A0 06 00 A6 B0 03 00 A8 03 4C …`（有效 ACK）** |
| 0（低有效）| 0 | MISO 全 `FF`，无响应 |

即：**高电平断言 300 ms → 释放为低电平 600 ms**，与上游参考机原始实现一致。
`PullUp` 只是 BIOS 的焊盘默认偏置，不代表复位极性。

---

## 4. 最终改动

补丁文件：`port/frd-wx9.patch`（可用 `git apply` 或 `patch -p1` 作用于基线提交）

| 文件 | 改动 | 原因 |
|---|---|---|
| `fingerprint/driver/goodix51a0/gx51_transport.h` | `GX51_RESET_LINE 264 → 259`<br>`GX51_EXPECTED_HWIRQ 48 → 79`<br>新增 `GX51_RESET_ASSERT 1` / `GX51_RESET_RELEASE 0` | 本机真实引脚；复位高有效 |
| `fingerprint/driver/goodix51a0/gx51_transport.c` | 芯片标签 `"INT34BB" → "INT3450"`<br>两处复位函数改用 `GX51_RESET_ASSERT/RELEASE` | 控制器不匹配；极性宏化 |
| `fingerprint/integration/prestart-recover/gxfp51a0-prestart-recover.c` | 芯片标签 `"INT34BB" → "INT3450"` | 便携版安装器的恢复助手同样写死了标签 |
| `fingerprint/driver/goodix51a0/SOURCE_MANIFEST.sha256` | 更新被改两文件的 SHA-256 | 构建脚本会做 `sha256sum -c`，否则拒绝构建 |

关键常量（最终）：

```c
#define GX51_RESET_LINE 259u
#define GX51_RESET_ASSERT  1
#define GX51_RESET_RELEASE 0
#define GX51_EXPECTED_HWIRQ 79u
```

---

## 5. 构建与安装

前置：`libgusb`（本机原先缺失，构建依赖它）。

本仓库的 `fingerprint/` 子树**已包含移植补丁**，不需要再打补丁，直接构建即可。

```bash
sudo pacman -S --needed libgusb base-devel git python pkgconf cairo glib2-devel

./scripts/build.sh      # 等价于在 fingerprint/packaging/arch 下 makepkg -f
./scripts/install.sh    # 安装 + 绑定 spidev + 启动 fprintd + 自动校验
```

手工等价步骤：

```bash
cd fingerprint/packaging/arch
makepkg -f --noconfirm
sudo pacman -U --noconfirm libfprint-goodix51a0-1.94.100.goodix51a0.qa59-2-x86_64.pkg.tar.zst
sudo pacman -S --needed fprintd
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=spi
sudo systemctl enable --now fprintd
```

结果：

| 组件 | 版本 |
|---|---|
| `libfprint-goodix51a0` | `1.94.100.goodix51a0.qa59-2` |
| `fprintd` | `1.94.5-2` |
| `libgusb` | `0.4.9-2` |

设备节点 `/dev/spidev1.0`，`driver_override = spidev`。

> 包声明了 `provides = libfprint-2.so=2-64`，可满足 `fprintd` 的 soname 依赖，
> 安装时不需要 `--assume-installed`。
> 若系统原本已装官方 `libfprint`，`pacman -U` 会要求移除它（`conflicts = libfprint`）。

---

## 6. 验证结果

启动 `fprintd` 后的关键日志（`journalctl -u fprintd -b`）：

```
GXFP51A0 RESUME_STAGE_QA stage=driverstate elapsed_ms=12 ack=1 sleep_boundary=0
GXFP51A0 RESUME_STAGE_QA stage=fw_version elapsed_ms=13
GXFP51A0 RESUME_STAGE_QA stage=tls_attempt attempt=1 config_ok=1 handshake_ok=1 \
    pmk_cache=0 config_ms=2089 handshake_ms=53
GXFP51A0 RESUME_STAGE_QA stage=full_capture_context elapsed_ms=3952 total_cold_ms=3978 success=1
GXFP51A0 FAST_READY in 89 ms: FDT alive touch=0x00 mean=349 floor=325; reusing prepared TLS/background
```

D-Bus：

```
$ busctl --system call net.reactivated.Fprint /net/reactivated/Fprint/Manager \
    net.reactivated.Fprint.Manager GetDefaultDevice
o "/net/reactivated/Fprint/Device/0"

$ busctl --system introspect ... .name
"Goodix GXFP51A0 SPI (ST411 / experimental)"
```

Claim 测试：`fprintd-enroll -f right-index-finger` 能打开设备并打印
`Using device /net/reactivated/Fprint/Device/0`，但随后 `EnrollStart` 被 polkit 拒绝：

```
Authorization denied to :1.17983 to call method 'EnrollStart' ... :
Not Authorized: net.reactivated.fprint.device.enroll
```

这是策略而非驱动问题：`net.reactivated.fprint.device.enroll` 的 `allow_active = auth_self_keep`，
非图形会话（或沙箱进程）没有 polkit 代理。录入需在 KDE 桌面进行，或在 SSH 终端里先起
`pkttyagent --process $$ &` 再执行。

---

## 7. 已知限制与风险

1. **上游是 QA 候选，不是稳定版**：S4 休眠未认证，第一触成功率在参考机上也波动；
   本机只验证了冷启动准备与握手。**必须保留密码登录**。
2. **固件绑定**：驱动多处硬比较 `GF_ST411SEC_APP_14115`。本机通过，但若厂商刷新固件版本，
   可能直接 init 失败，且没有绕过开关。
3. **引脚写死**：`79/259` 来自当前 BIOS 的 GNVS 配置。**升级 BIOS 后需重新推导**（见附录 A）。
4. **复位极性写死**：`GX51_RESET_ASSERT=1`。换主板/换机型必须重测。
5. **锁屏集成未配置**：`/etc/pam.d/kde` 目前没有 `pam_fprintd.so`，
   KDE 锁屏不会弹指纹。加 PAM 行有锁死风险，需在 CLI 验证通过后再做，并确认密码回退可用。
6. **内核被标记 tainted**：调试期间加载的只读探针模块 `gnvsread` 因一次页错误卡住，
   `rmmod` 不掉（`lsmod` 可见，引用计数 1）。不影响功能，**重启即清除**。
7. **系统更新**：`libfprint-goodix51a0` 与官方 `libfprint` 互斥；若日后有包强制拉取
   `libfprint`，会与当前包冲突，需要重新构建或回滚。

---

## 8. 回滚

```bash
sudo pacman -R libfprint-goodix51a0
sudo pacman -S libfprint fprintd
sudo systemctl restart fprintd
```

源码侧：

```bash
git checkout -- fingerprint/     # 恢复 vendored 子树
```

---

## 附录 A：如何重新推导引脚（BIOS 更新后）

1. **导出并反编译 ACPI 表**

   ```bash
   sudo acpidump -o /tmp/t.dat
   cd /tmp && acpixtract -a t.dat && iasl -d *.dat
   ```

   在 `.dsl` 中找 `Device (FPNT)`，确认 `_CRS` 里仍是
   `SPIN = GNUM (GFPS)` / `GPIN = GNUM (GFPI)`，并记录 `CreateWordField` 的两个偏移。

2. **读取 GNVS 中的 GFPS/GFPI**

   `/dev/mem` 被 `CONFIG_STRICT_DEVMEM` 拒绝，`/proc/kcore` 不含 ACPI NVS 段
   （该段是 e820 reserved，不在内核直接映射里，`phys_to_virt` 会 oops）。
   必须用 `ioremap_cache` 映射后读取：

   ```c
   void __iomem *base = ioremap_cache(0x8FB83298, 0x800);
   u32 gfps = readl(base + 0x465);
   u32 gfpi = readl(base + 0x469);
   iounmap(base);
   ```

   完整模块见 `tools/gnvsmod/gnvsread2.c`。

3. **查 GPCH 组基址并计算**

   ```bash
   grep -A150 'Name (GPCH' /tmp/dsdt.dsl
   ```

   每组第 7 个元素即基址，`GPIO = base(group) + offset`。

4. **实测复位极性**

   用 `tools/fp_probe.c`（见附录 B），
   在 `assert_level = 0/1`、`cs_high = 0/1` 四种组合下各跑一次，
   看 MISO 是否返回 `A0 …` 开头的有效帧。**不要只依据 ACPI 的 PullUp 推断极性。**

## 附录 B：诊断工具（均在本仓库 `tools/`）

| 文件 | 用途 |
|---|---|
| `tools/probe-gxfp51a0.sh` | 只读取证：ACPI 设备、GPIO 控制器、`_CRS` 解析（用 sudo 运行）|
| `tools/gnvsmod/gnvsread2.c` | 只读内核模块：`ioremap_cache` 读 GNVS 的 GFPS/GFPI |
| `tools/fp_probe.c` | 独立探针：直接操作 gpiochip + spidev，发 A8 命令并打印 MISO 原始字节 |
| `port/frd-wx9.patch` | 本机移植补丁（4 文件）|

`fp_probe` 预期输出（正确组合）：

```
== assert_level=1 cs_high=1 ==
MISO 前 32 字节: A0 06 00 A6 B0 03 00 A8 03 4C 4C 4C 4C ...
```

错误组合（assert_level=0）返回全 `FF`。

## 附录 C：过程记录与教训

| 问题 | 现象 | 处理 |
|---|---|---|
| 直接安装 | 驱动 open 失败 | 标签写成 `INT34BB`，本机是 `INT3450` |
| 按 DSDT 文本取 0/8 | 无响应 | 两个值是占位符，真实值在 GNVS |
| 按 `PullUp` 推断低有效 | 无响应 | 实测为高有效，已推翻 |
| `phys_to_virt` 读 GNVS | 内核 oops（`/dev/mem` 亦被拒）| 改用 `ioremap_cache` |
| heredoc 接到 `sudo -S` | 触发 PAM faillock 锁 10 分钟 | 密码管道与 heredoc 不可混用；已恢复 |
| 源码清单校验 | `makepkg` 拒绝构建 | 改源码后必须同步 `SOURCE_MANIFEST.sha256` |
