# 操作手册：从零到可用

> 对象：HONOR FRD-WX9（BIOS 3.06）+ Arch Linux。
> 目标：构建并安装本仓库的指纹驱动，使设备在 fprintd 中可用。
> 耗时：15–20 分钟（编译约 2 分钟）。
> 前提：联网（构建时从 `gitlab.freedesktop.org` 拉取 libfprint 源码）、可用 sudo。

仓库已自带移植补丁，**不需要**再应用 `port/frd-wx9.patch`。

全文用三种标记：

- **▶ 执行** —— 直接复制到终端
- **✅ 预期** —— 正常输出
- **⛔ 校验点** —— 不通过就停下，看第 8 节

---

## 0. 快速路径

确认设备一致（第 1 节）后，四条命令即可：

```bash
sudo pacman -S --needed base-devel git python pkgconf cairo glib2-devel libgusb
git clone git@github.com:takumijie/frd-wx9-fingerprint.git && cd frd-wx9-fingerprint
./scripts/build.sh
./scripts/install.sh
```

`install.sh` 末尾会跑 10 项校验，全 PASS 即可进入第 6 节录入。
下面的分步说明是为了在校验失败时定位问题。

---

## 1. GATE 0：确认设备一致

▶ 执行：

```bash
cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name /sys/class/dmi/id/board_name
grep -l 'acpi:GXFP51A0:' /sys/bus/spi/devices/*/modalias
readlink -f /sys/bus/gpio/devices/gpiochip0
uname -r
```

✅ 预期：

```
HONOR
FRD-WX9
FRD-WX9-PCB
/sys/bus/spi/devices/spi-GXFP51A0:00/modalias
/sys/devices/pci0000:00/INT3450:00/gpiochip0      ← 必须是 INT3450
6.x 或 7.x
```

⛔ 判定：

| 检查 | 通过条件 |
|---|---|
| DMI | `HONOR` / `FRD-WX9` / `FRD-WX9-PCB` |
| ACPI | 存在 `spi-GXFP51A0:00`，modalias 含 `acpi:GXFP51A0:` |
| GPIO | gpiochip 的父设备是 `INT3450` |

任一项不符 → **停止**。引脚 79/259 来自本机 BIOS 的 ACPI NVS 配置，
换机型或换 BIOS 必须重新推导（[port-record.md](port-record.md) 附录 A）。

---

## 2. 安装依赖

▶ 执行：

```bash
sudo pacman -S --needed --noconfirm \
  base-devel git python pkgconf cairo glib2-devel libgusb
```

✅ 预期：正常结束，无 `error:`。

> `libgusb` 是 libfprint 的硬依赖；缺它 `makepkg` 会在依赖检查阶段直接失败。

---

## 3. 获取与构建

▶ 执行：

```bash
mkdir -p ~/build && cd ~/build
git clone git@github.com:takumijie/frd-wx9-fingerprint.git
cd frd-wx9-fingerprint
./scripts/build.sh
```

✅ 预期结尾：

```
==> 完成创建：libfprint-goodix51a0 1.94.100.goodix51a0.qa59-2 (...)
构建完成：
libfprint-goodix51a0-1.94.100.goodix51a0.qa59-2-x86_64.pkg.tar.zst
```

⛔ 校验点：上述 `.pkg.tar.zst` 确实存在。

> 构建第一步会做 `sha256sum -c SOURCE_MANIFEST.sha256`。
> 若你改过驱动源码却没同步清单，会在这里失败。

---

## 4. 安装

▶ 执行：

```bash
./scripts/install.sh
```

它依次完成：`pacman -U` 安装驱动包 → 安装 `fprintd` → 重新触发 SPI 的 udev →
启动 fprintd → 运行 `verify.sh`。

手工等价步骤（便于知道每一步在做什么）：

```bash
sudo pacman -U --noconfirm fingerprint/packaging/arch/libfprint-goodix51a0-*.pkg.tar.zst
sudo pacman -S --needed --noconfirm fprintd
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=spi
sudo systemctl enable --now fprintd
```

> 若系统原本装着官方 `libfprint`，`pacman -U` 会提示移除它（本包 `conflicts=libfprint`）。
> 同意即可：本包同时提供 `libfprint-2.so=2-64`，`fprintd` 的 soname 依赖不会断。

⛔ **GATE 2** —— SPI 是否绑上：

```bash
basename "$(readlink -f /sys/bus/spi/devices/spi-GXFP51A0:00/driver)"
ls -l /dev/spidev*
```

✅ 预期：`spidev`，以及 `crw------- root root ... /dev/spidev1.0`。

---

## 5. 验证驱动

▶ 执行：

```bash
./scripts/verify.sh
```

✅ 预期：

```
FRD-WX9 指纹安装校验
kernel: ...

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

结果：全部通过。可以开始录入指纹（见 docs/runbook.md 第 6 节）。
```

⛔ **GATE 3**：`TLS 握手成功` 或 `冷启动准备成功` 为 FAIL → 停止，看第 8 节。

手工确认：

```bash
sudo journalctl -u fprintd -b --no-pager | grep -E 'fw_version|tls_attempt|full_capture_context'
busctl --system call net.reactivated.Fprint /net/reactivated/Fprint/Manager \
  net.reactivated.Fprint.Manager GetDefaultDevice
```

✅ 预期：`o "/net/reactivated/Fprint/Device/0"`。

---

## 6. 录入指纹

传感器是 **press（按压）** 类型：手指放上去**保持不动**，等提示再抬起，约 10 次。
建议再录一根备用手指。

### 6.1 图形界面（推荐）

本机桌面：**系统设置 → 用户 → 选中账户 → 指纹 → 添加**。
找不到入口用 `kcmshell6 kcm_users`。

### 6.2 命令行

必须处于活动的本地会话，否则 polkit 拒绝（`net.reactivated.fprint.device.enroll` 要求 `auth_self_keep`）：

```bash
pkttyagent --process $$ &
fprintd-enroll -f right-index-finger
```

### 6.3 验证

```bash
fprintd-list takumi
fprintd-verify -f right-index-finger takumi     # 期望 Verified
```

---

## 7. （可选）KDE 锁屏启用指纹

默认不启用。确认 `fprintd-verify` 已通过，**并在另一个终端留一个 root shell** 再操作。

```bash
sudo cp -a /etc/pam.d/kde /etc/pam.d/kde.bak.$(date +%F)
```

在 `/etc/pam.d/kde` 的 `auth` 段最前面加一行：

```
auth sufficient pam_fprintd.so
```

验证：

```bash
sudo -k && sudo true      # 密码仍然可用
loginctl lock-session     # 锁屏应出现指纹提示，同时保留密码输入
```

出问题立即还原：

```bash
sudo cp -a /etc/pam.d/kde.bak.* /etc/pam.d/kde
```

> 这一步有把自己锁在系统外的风险。不确定就跳过——跳过不影响设备本身可用。

---

## 8. 故障排查

| 症状 | 原因 | 处理 |
|---|---|---|
| `makepkg` 报缺 `gusb` | 未装 libgusb | `sudo pacman -S libgusb` |
| `makepkg` 报 `SOURCE_MANIFEST` 校验失败 | 源码与清单不一致 | 重算哈希（`sync-upstream.sh` 内有实现）|
| 日志找不到 gpiochip / 没有 `INT3450` | 控制器不符 | 本仓库不适用，需重新推导引脚 |
| 日志反复 `Stage2E A8 ACK failed` | 引脚号或复位极性不符 | [port-record.md](port-record.md) 附录 A |
| `PMK ... invalid` 但 `success=1` | 首次启动的正常现象 | 忽略，第二次启动走缓存 |
| `fprintd-enroll` 报 `Not Authorized` | 非活动会话 / 无 polkit 代理 | 图形界面，或 `pkttyagent --process $$ &` |
| `Device already in use` | 被其他进程占用 | `sudo systemctl restart fprintd` |
| 锁屏没有指纹选项 | `/etc/pam.d/kde` 未配置 | 见第 7 节 |
| `git clone` 卡住 | SSH 22 被墙 | 见第 3 节的 443 方式 |

实时观察：

```bash
sudo journalctl -u fprintd -f
systemctl status fprintd
lsmod | grep spidev
```

辅助诊断工具（只读）：

```bash
sudo tools/probe-gxfp51a0.sh        # ACPI 设备、GPIO 控制器、_CRS 解析
```

---

## 9. 回滚

```bash
sudo pacman -R libfprint-goodix51a0
sudo pacman -S libfprint fprintd
sudo systemctl restart fprintd
```

源码侧：

```bash
git checkout -- fingerprint/
```

> 若做过第 7 节的 PAM 修改，记得一并还原。

---

## 10. 验收清单

- [ ] GATE 0：DMI `FRD-WX9`、ACPI `GXFP51A0`、gpiochip 父设备 `INT3450`
- [ ] `./scripts/build.sh` 产出 `libfprint-goodix51a0-*.pkg.tar.zst`
- [ ] `readlink /sys/bus/spi/devices/spi-GXFP51A0:00/driver` = `spidev`
- [ ] `/dev/spidev*` 存在
- [ ] `./scripts/verify.sh` 全部 PASS
- [ ] `fprintd-list` 能看到已录入的手指
- [ ] `fprintd-verify` 返回 Verified
- [ ] 密码登录仍然可用

---

## 附录 A：参考输出

首次冷启动（PMK 未缓存）：

```
GXFP51A0 RESUME_STAGE_QA stage=driverstate elapsed_ms=12 ack=1 sleep_boundary=0
GXFP51A0 RESUME_STAGE_QA stage=fw_version elapsed_ms=13
GXFP51A0 RESUME_STAGE_QA stage=tls_attempt attempt=1 config_ok=1 handshake_ok=1 \
    pmk_cache=0 config_ms=2089 handshake_ms=53
GXFP51A0 RESUME_STAGE_QA stage=full_capture_context elapsed_ms=3952 total_cold_ms=3978 success=1
GXFP51A0 FAST_READY in 89 ms: FDT alive touch=0x00 mean=349 floor=325
```

缓存建立后：

```
GXFP51A0 RESUME_STAGE_QA stage=full_capture_context elapsed_ms=2075 total_cold_ms=2100 success=1
```

设备名：`Goodix GXFP51A0 SPI (ST411 / experimental)`

## 附录 B：版本基线

| 组件 | 版本 |
|---|---|
| 系统 | Arch Linux（rolling）|
| 内核 | 7.2.14-zen1-1-zen |
| `libfprint-goodix51a0` | 1.94.100.goodix51a0.qa59-2 |
| `fprintd` | 1.94.5-2 |
| `libgusb` | 0.4.9-2 |
| 上游基线 | `0eebade95521dc17317235a1b27017ad73f44c16` |

## 附录 C：同步上游新版本

```bash
scripts/sync-upstream.sh <新的上游提交>
```

脚本会重新导出 `fingerprint/`、重放 `port/frd-wx9.patch`、重算清单哈希。
补丁冲突时按 [port-record.md](port-record.md) 的说明手工合并，然后：

```bash
git diff -- fingerprint > port/frd-wx9.patch
```

并更新 `port-record.md` 与 `PROVENANCE.md` 中的基线提交。
