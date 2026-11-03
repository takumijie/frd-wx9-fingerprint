# FRD-WX9 指纹驱动（Goodix GXFP51A0）

HONOR FRD-WX9 上 Goodix GXFP51A0 / GF3658 ST411 指纹传感器的 Linux 驱动。
基于 [GodsQuantum/huawei-matebook-13-linux](https://github.com/GodsQuantum/huawei-matebook-13-linux)
的 driver-only 分发，修正了本机的 GPIO 控制器、引脚与复位极性，做成可直接构建安装的独立仓库。

本仓库**自带完整的驱动源码与构建脚本**，不依赖上游仓库即可编译安装。

## 支持矩阵

| 项 | 要求 |
|---|---|
| 机型 | HONOR FRD-WX9（product family `HONOR HUNTER`）|
| 主板 / BIOS | `FRD-WX9-PCB` / 3.06 |
| 传感器 | ACPI `GXFP51A0`，位于 `\_SB.PCI0.SPI1.FPNT`，SPI1 mode 0 |
| GPIO 控制器 | **`INT3450`**（Comet Lake-H PCH）|
| GPIO 引脚 | 中断 **79**、复位/上电 **259** |
| 复位极性 | **高有效**（HIGH 断言 → LOW 释放）|
| 系统 | Arch Linux（驱动是用户态，内核 ≥ 6.x 均可）|
| 依赖 | `libgusb`、`fprintd`、`base-devel` |

> **不要用在其他华为/荣耀机型上。** ACPI 里的引脚号是运行时占位符，
> 不同 BIOS 会填进不同值。换机型请按 [docs/port-record.md](docs/port-record.md) 附录 A 重新推导。

## 当前状态

本机（FRD-WX9 / Arch / kernel 7.2.14-zen）实测通过：

```
GXFP51A0 stage=fw_version elapsed_ms=13
GXFP51A0 stage=tls_attempt attempt=1 config_ok=1 handshake_ok=1 handshake_ms=53
GXFP51A0 stage=full_capture_context elapsed_ms=2075 total_cold_ms=2100 success=1
GXFP51A0 FAST_READY in 89 ms
```

设备在 D-Bus 上呈现为 `Goodix GXFP51A0 SPI (ST411 / experimental)`。

维护状态：**个人单机移植，非上游官方支持**。上游项目本身是 QA 候选
（S4 休眠未认证、第一触成功率在参考机上也有波动），因此：

- 请保留密码登录，不要只依赖指纹；
- 本仓库只保证"设备可用、TLS 握手成功、冷启动准备成功"，不保证登录场景的长期可靠性。

## 快速开始

```bash
# 1. 依赖
sudo pacman -S --needed base-devel git python pkgconf cairo glib2-devel libgusb

# 2. 获取（若 22 端口被墙，用文末的 443 方式）
git clone git@github.com:takumijie/frd-wx9-fingerprint.git
cd frd-wx9-fingerprint

# 3. 构建（不需要 root，约 2 分钟）
./scripts/build.sh

# 4. 安装 + 绑定 spidev + 启动 fprintd + 自动校验
./scripts/install.sh
```

`install.sh` 结束时会打印 10 项校验结果：

```
PASS  ACPI 设备 GXFP51A0 存在
PASS  GPIO 控制器是 INT3450
PASS  SPI 设备已绑定 spidev
PASS  /dev/spidev1.0 存在
PASS  libfprint-goodix51a0 1.94.100.goodix51a0.qa59-2
PASS  fprintd 1.94.5-2
PASS  fprintd 运行中
PASS  TLS 握手成功
PASS  冷启动准备成功
PASS  D-Bus 默认设备已就绪
```

全部 PASS 后录入指纹（传感器为**按压式**：手指放上去保持不动，等提示再抬起）：

- 图形界面：**系统设置 → 用户 → 指纹**
- 命令行（需活动会话）：`pkttyagent --process $$ &` 然后 `fprintd-enroll -f right-index-finger`

逐步说明、校验点与故障排查见 **[docs/runbook.md](docs/runbook.md)**。

## 工作原理

```
udev 规则 (acpi:GXFP51A0)  →  把 SPI 设备绑定到 spidev (/dev/spidev1.0)
                                        │
fprintd  ←─ D-Bus ─←  libfprint  ←─ goodix51a0 插件
                                        │
                          /dev/gpiochip0 行 79 (中断轮询) / 行 259 (复位)
```

- 驱动是 **libfprint 插件**，不涉及内核模块/DKMS；
- udev 规则来自构建产物 `70-libfprint-2.rules`；
- GPIO 通过 Linux GPIO chardev v2 API 访问，复位序列为 HIGH 300 ms → LOW 600 ms。

## 目录结构

```
.
├── fingerprint/                 # 上游 driver-only 分发（vendored，已含移植补丁）
│   ├── driver/goodix51a0/       #   驱动源码、libfprint 补丁、SOURCE_MANIFEST
│   ├── scripts/                 #   上游的 libfprint 构建脚本
│   └── packaging/arch/          #   PKGBUILD 与安装钩子
├── port/frd-wx9.patch           # 本机移植补丁（4 个文件）
├── docs/
│   ├── port-record.md           # 技术记录：为什么是 79/259、如何重新推导
│   └── runbook.md               # 操作手册：逐步执行 + 校验点
├── scripts/
│   ├── build.sh                 # 构建
│   ├── install.sh               # 安装 + udev + 服务 + 校验
│   ├── verify.sh                # 只读校验（10 项）
│   └── sync-upstream.sh         # 重新同步上游子树并重放补丁
├── tools/                       # 诊断工具（排查时才需要）
├── PROVENANCE.md                # 上游来源、改动清单、许可分层
└── LICENSES.md / LICENSE        # 上游许可原文
```

## 与上游的差异

相对上游基线 `0eebade`，只改动 4 个文件：

| 文件 | 改动 |
|---|---|
| `fingerprint/driver/goodix51a0/gx51_transport.h` | `RESET_LINE 264→259`、`EXPECTED_HWIRQ 48→79`、新增复位极性宏 |
| `fingerprint/driver/goodix51a0/gx51_transport.c` | 芯片标签 `INT34BB→INT3450`；复位改用极性宏 |
| `fingerprint/integration/prestart-recover/gxfp51a0-prestart-recover.c` | 芯片标签 `INT34BB→INT3450` |
| `fingerprint/driver/goodix51a0/SOURCE_MANIFEST.sha256` | 同步被改文件的哈希 |

推导过程与证据见 [docs/port-record.md](docs/port-record.md)。

## 常见问题

| 现象 | 处理 |
|---|---|
| `makepkg` 报缺 `gusb` | `sudo pacman -S libgusb` |
| `makepkg` 报 `SOURCE_MANIFEST` 校验失败 | 源码被改过而清单未更新，见 runbook §8 |
| 日志反复 `A8 ACK failed` | 引脚/极性不符，本仓库不适用于该机器 |
| `fprintd-enroll` 报 `Not Authorized` | 非活动会话，用图形界面或 `pkttyagent` |
| 锁屏不弹指纹 | `/etc/pam.d/kde` 未配置，见 runbook §7 |

完整排查表见 [docs/runbook.md](docs/runbook.md) 第 8 节。

## 回滚

```bash
sudo pacman -R libfprint-goodix51a0
sudo pacman -S libfprint fprintd
sudo systemctl restart fprintd
```

## 许可与出处

- `fingerprint/` 子树按其原有许可分发：驱动与 libfprint 集成代码为 **LGPL-2.1-or-later**
  （`fingerprint/driver/goodix51a0/COPYING`），其余项目材料为 **GPL-2.0-only**
  （见 [LICENSE](LICENSE)、[LICENSES.md](LICENSES.md)）。
- 本仓库新增的 `scripts/`、`tools/`、`docs/`、`port/` 为 **GPL-2.0-only**。
- 上游来源、基线提交与改动清单见 [PROVENANCE.md](PROVENANCE.md)。
- 不包含专有固件、Windows 驱动二进制、指纹模板或按设备唯一的密钥材料。

## 致谢

- [GodsQuantum/huawei-matebook-13-linux](https://github.com/GodsQuantum/huawei-matebook-13-linux)
  —— 驱动本体与 GXFP51A0 协议实现
- [libfprint](https://gitlab.freedesktop.org/libfprint/libfprint) —— 指纹框架

## 附：22 端口不可用时的克隆方式

```bash
GIT_SSH_COMMAND='ssh -p 443' \
  git clone ssh://git@ssh.github.com:443/takumijie/frd-wx9-fingerprint.git
```
