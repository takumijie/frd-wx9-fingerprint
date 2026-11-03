# 技术记录：FRD-WX9 的 GXFP51A0 移植

> 本文回答"为什么是这些值"。要照着做，请看 [runbook.md](runbook.md)。
> 适用范围：**仅 HONOR FRD-WX9（HONOR HUNTER，Comet Lake-H）**。
> 记录时间：2026-11-03。

---

## 摘要

传感器、协议、libfprint 版本都对得上，真正的障碍是驱动里**写死了参考机
MateBook 13 的 GPIO 控制器与引脚号**，而本机取值完全不同；并且这两个引脚号在
ACPI 表里是**运行时才被填入的占位符**，读 DSDT 静态文本只能得到 0 和 8。

| 项 | 参考机（MateBook 13） | 本机（FRD-WX9） | 是否需改 |
|---|---|---|---|
| 传感器 | GXFP51A0 / GF3658 ST411 | 同 | 否 |
| SPI | SPI1，mode 0，10 MHz，四线 | 同 | 否 |
| libfprint | v1.94.100 | 同 | 否 |
| GPIO 控制器 | `INT34BB` | **`INT3450`** | **是** |
| 中断脚 | GPIO 48 | **GPIO 79** | **是** |
| 复位脚 | GPIO 264 | **GPIO 259** | **是** |
| 复位极性 | 高有效 | 高有效（实测） | 否（但已宏化）|

最终状态（本机实测）：

| 项目 | 结果 |
|---|---|
| 传感器识别 | `Goodix GXFP51A0 SPI (ST411 / experimental)` |
| 固件版本读取 | 成功（`stage=fw_version elapsed_ms=13`）|
| TLS 握手 | 成功（`config_ok=1 handshake_ok=1 handshake_ms=53`）|
| 冷启动准备 | 成功（首次 3952 ms；PMK 缓存建立后 2075 ms）|
| 热态就绪 | `FAST_READY in 89 ms` |
| D-Bus 设备 | `/net/reactivated/Fprint/Device/0`（默认设备）|

---

## 1. 设备与传感器

| 项 | 值 |
|---|---|
| 厂商 / 型号 | HONOR / FRD-WX9（product family `HONOR HUNTER`）|
| 主板 / BIOS | `FRD-WX9-PCB` / 3.06（2022-03-11）|
| CPU | Intel Core i5-10300H（Comet Lake-H）|
| 系统 | Arch Linux（rolling），KDE Plasma 6.8.2 + SDDM |
| 内核 | 7.2.14-zen1-1-zen |

| 项 | 值 |
|---|---|
| ACPI HID | `GXFP51A0`（`_CID` 相同，`_UID=1`）|
| ACPI 路径 | `\_SB.PCI0.SPI1.FPNT` |
| 总线 | SPI1（Intel LPSS，`pxa2xx-spi`），mode 0，10 MHz，四线 |
| 芯片 | Goodix GXFP51A0 / GF3658 Milan ST411，chip-id `0x2504` |
| 固件 | `GF_ST411SEC_APP_14115`（本机校验通过）|
| 供电 | ACPI 未声明独立电源 GPIO，复位线兼作上电控制 |

---

## 2. 上游基线与本仓库

| 项 | 值 |
|---|---|
| 上游仓库 | `https://github.com/GodsQuantum/huawei-matebook-13-linux` |
| 基线提交 | `0eebade95521dc17317235a1b27017ad73f44c16`（2026-11-02）|
| 引入内容 | 仅 `fingerprint/`（官方 driver-only 分发，370 文件）|
| 参考机型 | Huawei MateBook 13（WRTB-WXX9），上游全部硬件验证仅此一台 |

上游项目自述为 QA 候选（`rel71.74` / QA59）：S4 休眠未认证，第一触成功率在参考机上
也有波动（`HALL_OF_FAME.md` 记录多次回归）。本移植只验证到"设备可用、握手成功"。

> 上游根仓库还包含 MateBook 专用的 GPU 电源管理器（要求 NVIDIA MX250 `10de:1d13`），
> 与本机无关，本仓库**刻意没有引入**。

---

## 3. 兼容性分析

### 3.1 一致的部分（全部通过）

- `acpi:GXFP51A0:` 存在于 `spi-GXFP51A0:00/modalias`。
- 传感器型号与上游支持列表一致。
- Arch 官方 `libfprint` 恰为 `1.94.100-1`，与驱动锁定的 `v1.94.100` 完全一致。
- 纯用户态驱动（libfprint 插件 + `spidev` + GPIO chardev），不需要内核模块/DKMS；
  `CONFIG_GPIO_CDEV=y`、`CONFIG_SPI_SPIDEV=m` 均满足。
- 设备初始无驱动绑定，`driver_override` 为空，可直接交给 udev 规则。

### 3.2 不一致之一：GPIO 控制器

驱动 `gx51_transport.c: gx51_open_int34bb()` 遍历 `/dev/gpiochipN`，用
`strncmp(info.label, "INT34BB", 7)` 认芯片。

本机 `gpiochip0` 的父 ACPI 设备是 **`INT3450`**（`\_SB.PCI0.GPI0`）：

```
gpiochip0: 364 GPIOs, parent: platform/INT3450:00, INT3450:00:
```

`INT34BB` 是参考机那代 LP 平台的 PCH，Comet Lake-H 用 `INT3450`。
不改这一处，驱动**找不到 GPIO 芯片**，设备 open 直接失败。

### 3.3 不一致之二：引脚号是运行时占位符

DSDT 里 `FPNT._CRS` 字面上写的是：

```
GpioInt (Level, ActiveHigh, ExclusiveAndWake, PullDefault, ...) { 0x0000 }
GpioIo  (Exclusive, PullUp, ..., IoRestrictionOutputOnly, ...)   { 0x0008 }
```

看似 IRQ=0、RESET=8。但同一个 `_CRS` 方法在返回前覆盖了这两个字段：

```asl
CreateWordField (BBUF, 0x63, SPIN)
CreateWordField (BBUF, 0x3B, GPIN)
SPIN = GNUM (GFPS)
GPIN = GNUM (GFPI)
```

`GNUM` 的定义：

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

`GINF(group, 6)` 取 `GPCH[group][6]`，即该组的全局 GPIO 基址。
本机 `\_SB.PCI0.GPI0._HID` 返回 `INT3450`（`PCHS == PCHH`），走 `GPCH` 表。

> **哪个是中断、哪个是复位**：按资源描述符布局核对，`0x3B` 落在 GpioInt 的引脚表、
> `0x63` 落在 GpioIo 的引脚表，所以 **GPIN = 中断脚，SPIN = 复位/上电脚**。
> 旁证：模板里 SPI DeviceSelection 为 0，内核实际生成 `/dev/spidev1.0`（CS=0），
> 说明 SPIN 不是片选字段。

### 3.4 从 GNVS 推导真实引脚

`GFPI` / `GFPS` 是 BIOS 写在 ACPI NVS（GNVS 区）里的 32 位字段，只能运行时读取：

| 项 | 值 |
|---|---|
| GNVS OperationRegion | 物理地址 `0x8FB83298`，长度 `0x07FA` |
| GFPS 偏移 | `0x465` |
| GFPI 偏移 | `0x469` |

本机实测：

```
GFPS = 0x03040003  → group = 4, offset = 3
GFPI = 0x0302000F  → group = 2, offset = 15
```

`GPCH` 各组基址（每组第 7 个元素）：

| group | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| base | 0 | 32 | 64 | 96 | 256 | 288 | 128 | 224 | 320 | 352 | 192 |

换算：

```
中断脚 = base(2) + 15 = 64  + 15 = 79
复位脚 = base(4) + 3  = 256 + 3  = 259
```

**交叉验证**：触控板（`TPDG`）的 GpioInt 同样用 offset 15，其 `GFPI` 在 group 1，
`base(1)+15 = 47`，与内核 `/sys/kernel/debug/gpio` 的
`gpio-47 ( |TPDG GpioInt(0) ) in hi IRQ ACTIVE LOW` 完全吻合。

对应焊盘（`/sys/kernel/debug/pinctrl/INT3450:00/pins`）：

| GPIO | pin | 焊盘名 | 状态 |
|---|---|---|---|
| 79 | 66 | `UART1_CTSB` | GPIO，未占用 |
| 259 | 206 | `CPU_GP_0` | GPIO，未占用 |

> 注意：`pins` 文件里 **pin 索引与 GPIO 号不是一回事**（例如 pin 47 对应 gpio 54）。
> 计算必须用 GPIO 号，不能用焊盘索引。

### 3.5 不一致之三：复位极性（实测推翻推断）

ACPI 把复位脚声明为 `PullUp`，据此曾推断为低有效——**错误**。
用独立探针（`tools/fp_probe.c`）对组合做了实测：

| assert 电平 | CS_HIGH | 结果 |
|---|---|---|
| 0（按低有效）| 1 | MISO 全 `FF`，无响应 |
| **1（按高有效）** | **1** | **`A0 06 00 A6 B0 03 00 A8 03 4C …`（有效 ACK）** |
| 0（按低有效）| 0 | MISO 全 `FF`，无响应 |

即：**HIGH 断言 300 ms → LOW 释放 600 ms**，与上游参考机原始实现一致。
`PullUp` 只是 BIOS 的焊盘默认偏置，不代表复位极性。

---

## 4. 最终改动

补丁文件 `port/frd-wx9.patch`（可用 `git apply` / `patch -p1` 作用于基线提交）：

| 文件 | 改动 | 原因 |
|---|---|---|
| `fingerprint/driver/goodix51a0/gx51_transport.h` | `GX51_RESET_LINE 264 → 259`<br>`GX51_EXPECTED_HWIRQ 48 → 79`<br>新增 `GX51_RESET_ASSERT 1` / `GX51_RESET_RELEASE 0` | 本机真实引脚；复位高有效 |
| `fingerprint/driver/goodix51a0/gx51_transport.c` | 芯片标签 `"INT34BB" → "INT3450"`；两处复位函数改用极性宏 | 控制器不匹配；极性宏化 |
| `fingerprint/integration/prestart-recover/gxfp51a0-prestart-recover.c` | 芯片标签 `"INT34BB" → "INT3450"` | 该恢复助手同样写死标签 |
| `fingerprint/driver/goodix51a0/SOURCE_MANIFEST.sha256` | 更新被改两文件的 SHA-256 | 构建脚本会 `sha256sum -c`，否则拒绝构建 |

关键常量：

```c
#define GX51_RESET_LINE 259u
#define GX51_RESET_ASSERT  1
#define GX51_RESET_RELEASE 0
#define GX51_EXPECTED_HWIRQ 79u
```

---

## 5. 验证证据

`journalctl -u fprintd -b`：

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

设备可被 Claim：`fprintd-enroll` 会打印
`Using device /net/reactivated/Fprint/Device/0`。随后 `EnrollStart` 被 polkit 拒绝，
这是策略而非驱动问题（`net.reactivated.fprint.device.enroll` 的 `allow_active` 为
`auth_self_keep`，非图形会话没有 polkit 代理）。

---

## 6. 已知限制与风险

1. **上游是 QA 候选**：S4 休眠未认证，第一触成功率在参考机上也波动；本机只验证了
   冷启动准备与握手。**必须保留密码登录**。
2. **固件绑定**：驱动多处硬比较 `GF_ST411SEC_APP_14115`。本机通过；若厂商刷新固件，
   可能直接 init 失败，且没有绕过开关。
3. **引脚写死**：`79/259` 来自当前 BIOS 的 GNVS 配置，**升级 BIOS 后需重新推导**
   （附录 A）。
4. **极性写死**：`GX51_RESET_ASSERT=1`。换主板/机型必须重测。
5. **锁屏可用，登录界面不可用**：KDE 锁屏由 `kscreenlocker` 自带的
   `/usr/lib/pam.d/kde-fingerprint`（内含 `pam_fprintd.so`）提供，开箱即用；
   但 SDDM 的 `/etc/pam.d/sddm` 没有集成 fprintd，图形登录界面仍需另行配置。
6. **包冲突**：`libfprint-goodix51a0` 与官方 `libfprint` 互斥。若日后有包强制拉取
   `libfprint`，会与当前包冲突，需要重新构建或回滚。

---

## 附录 A：如何重新推导引脚（BIOS 更新或换机）

1. **导出并反编译 ACPI 表**

   ```bash
   sudo acpidump -o /tmp/t.dat
   cd /tmp && acpixtract -a t.dat && iasl -d *.dat
   ```

   在 `.dsl` 中找 `Device (FPNT)`，确认 `_CRS` 里仍是
   `SPIN = GNUM (GFPS)` / `GPIN = GNUM (GFPI)`，并记录两个 `CreateWordField` 偏移。

2. **读取 GNVS 中的 GFPS/GFPI**

   `/dev/mem` 被 `CONFIG_STRICT_DEVMEM` 拒绝；`/proc/kcore` 不含 ACPI NVS 段
   （该段是 e820 reserved，不在内核直接映射里，`phys_to_virt` 会 oops）。
   必须用 `ioremap_cache`：

   ```c
   void __iomem *base = ioremap_cache(0x8FB83298, 0x800);
   u32 gfps = readl(base + 0x465);
   u32 gfpi = readl(base + 0x469);
   iounmap(base);
   ```

   可直接使用 `tools/gnvsmod/`（先 `make`，再 `insmod`，读 `dmesg`，最后 `rmmod`）。

3. **查 GPCH 组基址并计算**

   ```bash
   grep -A150 'Name (GPCH' /tmp/dsdt.dsl
   ```

   每组第 7 个元素即基址，`GPIO = base(group) + offset`。

4. **实测复位极性**

   编译 `tools/fp_probe.c`，在 `assert_level = 0/1`、`cs_high = 0/1` 组合下各跑一次，
   看 MISO 是否返回 `A0 …` 开头的有效帧。**不要只依据 ACPI 的 PullUp 推断极性。**

---

## 附录 B：诊断工具（均在 `tools/`）

| 文件 | 用途 |
|---|---|
| `probe-gxfp51a0.sh` | 只读取证：ACPI 设备、GPIO 控制器、`_CRS` 解析（sudo 运行）|
| `gnvsmod/gnvsread2.c` | 只读内核模块：`ioremap_cache` 读 GNVS 的 GFPS/GFPI |
| `fp_probe.c` | 独立探针：直接操作 gpiochip + spidev，发 A8 命令并打印 MISO 原始字节 |

`fp_probe` 正常输出：

```
== assert_level=1 cs_high=1 ==
MISO 前 32 字节: A0 06 00 A6 B0 03 00 A8 03 4C 4C 4C 4C ...
```

`assert_level=0` 时返回全 `FF`。

---

## 附录 C：调试历程与教训

| 现象 | 根因 | 处理 |
|---|---|---|
| 直接安装后设备 open 失败 | 标签写成 `INT34BB`，本机是 `INT3450` | 改标签 |
| 按 DSDT 文本取 0/8，无响应 | 两个值是占位符，真实值在 GNVS | 读 GNVS + GPCH 换算 |
| 按 `PullUp` 推断低有效，无响应 | 实测为高有效 | 用探针四组组合实测 |
| `phys_to_virt` 读 GNVS 触发 oops | ACPI NVS 不在内核直接映射 | 改用 `ioremap_cache` |
| `makepkg` 拒绝构建 | 改了源码未同步 `SOURCE_MANIFEST` | 重算哈希 |
| heredoc 接到 `sudo -S`，触发 PAM faillock | 密码管道与 heredoc 混用 | 分开执行，锁定十分钟后自动解除 |

> 调试期间加载的只读探针模块 `gnvsread` 曾因上述 oops 卡住、`rmmod` 不掉，
> 引用计数为 1。它不占 CPU、不影响功能，**重启即清除**。
