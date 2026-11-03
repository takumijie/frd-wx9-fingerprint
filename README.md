# FRD-WX9 指纹驱动（Goodix GXFP51A0）

把 [GodsQuantum/huawei-matebook-13-linux](https://github.com/GodsQuantum/huawei-matebook-13-linux)
的 Goodix GXFP51A0 / GF3658 ST411 指纹驱动移植到 **HONOR FRD-WX9**，做成可直接构建安装的独立仓库。

上游驱动的目标机是 Huawei MateBook 13（`WRTB-WXX9`）。本仓库在原驱动基础上修正了
GPIO 控制器、GPIO 引脚与复位极性，使其在本机工作。

## 支持的设备（严格匹配）

| 项 | 要求 |
|---|---|
| 机型 | HONOR FRD-WX9（product family `HONOR HUNTER`）|
| 主板 | `FRD-WX9-PCB`，BIOS 3.06 |
| 传感器 | ACPI `GXFP51A0`，位于 `\_SB.PCI0.SPI1.FPNT` |
| GPIO 控制器 | **`INT3450`**（Comet Lake-H PCH）|
| GPIO 引脚 | 中断 **79**、复位/上电 **259**（来自 BIOS 的 GNVS 配置）|
| 复位极性 | **高有效**（HIGH 断言 → LOW 释放）|
| 系统 | Arch Linux（驱动是用户态，内核 ≥ 6.x 均可）|

**其他华为/荣耀机型不要直接用**：引脚号在 ACPI 里是运行时占位符，不同 BIOS 取值不同。
换机型请按 [docs/port-record.md](docs/port-record.md) 附录 A 重新推导。

## 当前状态

本机（FRD-WX9 / Arch / kernel 7.2.14-zen）实测：

```
GXFP51A0 stage=fw_version elapsed_ms=13
GXFP51A0 stage=tls_attempt attempt=1 config_ok=1 handshake_ok=1 handshake_ms=53
GXFP51A0 stage=full_capture_context elapsed_ms=2075 total_cold_ms=2100 success=1
GXFP51A0 FAST_READY in 89 ms
```

> **上游项目仍是 QA 候选**：S4 休眠未认证，第一触成功率在参考机上也有波动。
> 请保留密码登录，不要只依赖指纹。本仓库只保证"设备可用、握手成功"。

## 快速开始

```bash
sudo pacman -S --needed base-devel git python pkgconf cairo glib2-devel libgusb

git clone git@github.com:takumijie/frd-wx9-fingerprint.git
cd frd-wx9-fingerprint

./scripts/build.sh      # 构建，不需要 root，约 2 分钟
./scripts/install.sh    # 安装 + 绑定 spidev + 启动 fprintd + 自动校验
```

校验通过后录入指纹（传感器为**按压式**，按住不动）：

- 图形界面：系统设置 → 用户 → 指纹
- 或命令行：`pkttyagent --process $$ &` 然后 `fprintd-enroll -f right-index-finger`

完整的逐步说明、校验点与故障排查见 **[docs/runbook.md](docs/runbook.md)**。

## 目录结构

```
.
├── fingerprint/                 # 上游 driver-only 分发（vendored，已含移植补丁）
│   ├── driver/goodix51a0/       #   libfprint 驱动源码 + SOURCE_MANIFEST
│   ├── scripts/                 #   上游的 libfprint 构建脚本
│   └── packaging/arch/          #   PKGBUILD
├── port/frd-wx9.patch           # 本机移植补丁（4 个文件）
├── docs/
│   ├── port-record.md           # 移植记录：为什么这么改、如何重新推导
│   └── runbook.md               # 复刻手册：照着做
├── scripts/
│   ├── build.sh                 # 构建
│   ├── install.sh               # 安装 + 校验
│   ├── verify.sh                # 只读校验（8 项）
│   └── sync-upstream.sh         # 重新同步上游子树并重放补丁
└── tools/                       # 诊断工具（只在排查时用）
```

## 关键改动

相对上游基线 `0eebade`，只动了 4 个文件：

| 文件 | 改动 |
|---|---|
| `fingerprint/driver/goodix51a0/gx51_transport.h` | `RESET_LINE 264→259`、`EXPECTED_HWIRQ 48→79`、新增复位极性宏 |
| `fingerprint/driver/goodix51a0/gx51_transport.c` | 芯片标签 `INT34BB→INT3450`；复位改用极性宏 |
| `fingerprint/integration/prestart-recover/gxfp51a0-prestart-recover.c` | 芯片标签 `INT34BB→INT3450` |
| `fingerprint/driver/goodix51a0/SOURCE_MANIFEST.sha256` | 同步被改文件的哈希 |

改动原因与推导过程见 [docs/port-record.md](docs/port-record.md)。

## 回滚

```bash
sudo pacman -R libfprint-goodix51a0
sudo pacman -S libfprint fprintd
sudo systemctl restart fprintd
```

## 许可与出处

- 上游 `fingerprint/` 子树按其原有许可分发：驱动与 libfprint 集成代码为
  **LGPL-2.1-or-later**（见 `fingerprint/driver/goodix51a0/COPYING`），
  其余项目材料为 **GPL-2.0-only**（见 [LICENSE](LICENSE) 与 [LICENSES.md](LICENSES.md)）。
- 本仓库新增的 `scripts/`、`tools/`、`docs/`、`port/` 与根许可一致，为 **GPL-2.0-only**。
- 上游来源、基线提交与改动清单见 [PROVENANCE.md](PROVENANCE.md)。
- 不包含任何专有固件、Windows 驱动二进制、指纹模板或按设备唯一的密钥材料。

## 致谢

- [GodsQuantum/huawei-matebook-13-linux](https://github.com/GodsQuantum/huawei-matebook-13-linux)
  —— 驱动本体与 GXFP51A0 协议实现
- [libfprint](https://gitlab.freedesktop.org/libfprint/libfprint) —— 指纹框架
