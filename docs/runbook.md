# FRD-WX9 复刻手册（照抄执行）

> **对象**：HONOR FRD-WX9（BIOS 3.06），Arch Linux。
> **结果**：可用的 Goodix GXFP51A0 指纹设备 + fprintd 集成。
> **耗时**：15–20 分钟（编译约 2 分钟）。
> **前提**：联网（构建时从 `gitlab.freedesktop.org` 拉取 libfprint 源码）、可用的 sudo。

本仓库的 `fingerprint/` 子树**已经包含移植补丁**，不需要再应用 `port/frd-wx9.patch`。

每步给出 ▶ 执行 / ✅ 预期 / ⛔ 校验点。校验点不过就停下，先看第 8 节。

---

## GATE 0：确认设备一致

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
/sys/devices/pci0000:00/INT3450:00/gpiochip0      <- 必须是 INT3450
6.x 或 7.x
```

⛔ 任一项不符 → 停止。引脚号来自本机 BIOS，换机型/BIOS 必须重新推导
（见 [port-record.md](port-record.md) 附录 A）。

---

## 1. 安装依赖

```bash
sudo pacman -S --needed --noconfirm \
  base-devel git python pkgconf cairo glib2-devel libgusb
```

✅ 预期：正常结束，无 `error:`。

> `libgusb` 是 libfprint 的硬依赖，缺它 `makepkg` 会在依赖检查阶段直接失败。

---

## 2. 获取仓库

```bash
mkdir -p ~/build && cd ~/build
git clone git@github.com:takumijie/frd-wx9-fingerprint.git
cd frd-wx9-fingerprint
```

若 SSH 22 端口不通（国内网络常见），临时走 443：

```bash
GIT_SSH_COMMAND='ssh -p 443' git clone ssh://git@ssh.github.com:443/takumijie/frd-wx9-fingerprint.git
```

---

## 3. 构建

```bash
./scripts/build.sh
```

✅ 预期结尾：

```
==> 完成创建：libfprint-goodix51a0 1.94.100.goodix51a0.qa59-2 (...)
构建完成：
libfprint-goodix51a0-1.94.100.goodix51a0.qa59-2-x86_64.pkg.tar.zst
```

⛔ 校验点：上面的 `.pkg.tar.zst` 文件确实存在。

> 构建脚本会先做 `sha256sum -c SOURCE_MANIFEST.sha256`。若你改过驱动源码却没同步清单，
> 会在这里失败——用 `scripts/sync-upstream.sh` 或手工重算哈希。

---

## 4. 安装

```bash
./scripts/install.sh
```

它会依次：`pacman -U` → 装 `fprintd` → 重新触发 SPI 的 udev → 启动 fprintd → 跑 `verify.sh`。

手工等价步骤：

```bash
sudo pacman -U --noconfirm fingerprint/packaging/arch/libfprint-goodix51a0-*.pkg.tar.zst
sudo pacman -S --needed --noconfirm fprintd
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=spi
sudo systemctl enable --now fprintd
```

> 若系统原本装着官方 `libfprint`，`pacman -U` 会提示移除它（`conflicts=libfprint`）。
> 同意即可；本包同时提供 `libfprint-2.so=2-64`，`fprintd` 的 soname 依赖不会断。

⛔ **GATE 2**：

```bash
basename "$(readlink -f /sys/bus/spi/devices/spi-GXFP51A0:00/driver)"
ls -l /dev/spidev1.0
```

✅ 预期：`spidev` 和 `crw------- root root ... /dev/spidev1.0`。

---

## 5. 验证驱动

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
结果：全部通过。
```

⛔ **GATE 3**：如果 `TLS 握手成功` 或 `冷启动准备成功` 是 FAIL，不要继续，跳到第 8 节。

手工确认：

```bash
sudo journalctl -u fprintd -b --no-pager | grep -E 'fw_version|tls_attempt|full_capture_context'
busctl --system call net.reactivated.Fprint /net/reactivated/Fprint/Manager \
  net.reactivated.Fprint.Manager GetDefaultDevice
```

---

## 6. 录入指纹

传感器是 **press（按压）** 类型：手指放上去**保持不动**，等提示再抬起，约 10 次。

### 6.1 图形界面（推荐）

本机桌面：**系统设置 → 用户 → 选中账户 → 指纹 → 添加**。
找不到入口用 `kcmshell6 kcm_users`。

### 6.2 命令行

必须处于活动本地会话，否则 polkit 会拒绝（`auth_self_keep`）：

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

默认不启用。确认 `fprintd-verify` 通过后再做，**并保持一个 root 终端开着**。

```bash
sudo cp -a /etc/pam.d/kde /etc/pam.d/kde.bak.$(date +%F)
```

在 `/etc/pam.d/kde` 的 `auth` 段最前面加一行：

```
auth sufficient pam_fprintd.so
```

验证：

```bash
sudo -k && sudo true      # 密码仍可用
loginctl lock-session     # 锁屏应出现指纹提示，同时密码可用
```

出问题立即还原：

```bash
sudo cp -a /etc/pam.d/kde.bak.* /etc/pam.d/kde
```

> 有把自己锁在外面的风险。不确定就跳过——设备本身已经可用。

---

## 8. 故障排查

| 症状 | 原因 | 处理 |
|---|---|---|
| `makepkg` 缺 `gusb` | 没装 libgusb | `sudo pacman -S libgusb` |
| `makepkg` 报 `SOURCE_MANIFEST` 校验失败 | 源码与清单不一致 | 重算哈希（见 `sync-upstream.sh` 内的 Python 片段）|
| 日志找不到 gpiochip / 无 `INT3450` | 控制器不符 | 本仓库不适用，需重新推导引脚 |
| 日志反复 `Stage2E A8 ACK failed` | 引脚号或复位极性不符 | 看 [port-record.md](port-record.md) 附录 A |
| `PMK ... invalid` 但 `success=1` | 首次启动的正常现象 | 忽略，第二次启动走缓存 |
| `fprintd-enroll` 报 `Not Authorized` | 非活动会话 / 无 polkit 代理 | 用图形界面，或 `pkttyagent --process $$ &` |
| `Device already in use` | 被其他进程占用 | `sudo systemctl restart fprintd` |
| 锁屏没有指纹选项 | `/etc/pam.d/kde` 未配置 | 见第 7 节 |
| `git clone` 卡住 | SSH 22 被墙 | 用第 2 节的 443 方式 |

实时日志：

```bash
sudo journalctl -u fprintd -f
systemctl status fprintd
lsmod | grep spidev
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

---

## 10. 验收清单

- [ ] GATE 0：DMI `FRD-WX9`、ACPI `GXFP51A0`、gpiochip 父设备 `INT3450`
- [ ] `scripts/build.sh` 产出 `libfprint-goodix51a0-*.pkg.tar.zst`
- [ ] `readlink /sys/bus/spi/devices/spi-GXFP51A0:00/driver` = `spidev`
- [ ] `/dev/spidev1.0` 存在
- [ ] `scripts/verify.sh` 全部 PASS
- [ ] 录入成功，`fprintd-list` 能看到手指
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

会重新导出 `fingerprint/`、重放 `port/frd-wx9.patch`、重算清单哈希。
补丁冲突时按 [port-record.md](port-record.md) 的说明手工合并，然后：

```bash
git diff -- fingerprint > port/frd-wx9.patch
```

并更新 `docs/port-record.md` 与 `PROVENANCE.md` 里的基线提交。
