# 出处与改动清单

## 上游

| 项 | 值 |
|---|---|
| 仓库 | https://github.com/GodsQuantum/huawei-matebook-13-linux |
| 基线提交 | `0eebade95521dc17317235a1b27017ad73f44c16` |
| 提交日期 | 2026-11-02 |
| 提交标题 | `feat(gxfp): HUAWEI installs QA59 with preserved fingerprint templates (#70)` |
| 引入的子树 | `fingerprint/`（370 个文件）|
| 引入方式 | `git archive <commit> fingerprint/ \| tar -x` |

上游的 `fingerprint/` 是官方提供的 **driver-only 分发**——不含 GPU 电源管理器、
HUAWEI 控制中心与 KDE 定制补丁，因此可以独立成仓。本仓库正是以它为底座。

## 本仓库的组成

| 部分 | 来源 |
|---|---|
| `fingerprint/` | 上游 `fingerprint/` 子树 + 本机移植补丁（4 个文件）|
| `LICENSE`、`LICENSES.md`、`SECURITY.md` | 上游原文，未改动 |
| `port/frd-wx9.patch` | 本机改动（见下）|
| `docs/`、`scripts/`、`tools/` | 本仓库新增 |

## 改动清单

相对上游基线，只修改了 4 个文件，全部在 `fingerprint/` 内：

```
fingerprint/driver/goodix51a0/gx51_transport.h
fingerprint/driver/goodix51a0/gx51_transport.c
fingerprint/integration/prestart-recover/gxfp51a0-prestart-recover.c
fingerprint/driver/goodix51a0/SOURCE_MANIFEST.sha256
```

内容：

- GPIO 控制器标签 `INT34BB` → `INT3450`
- 中断脚 48 → **79**、复位脚 264 → **259**（来自 ACPI GNVS 的 GFPI/GFPS）
- 复位极性宏化为高有效（`ASSERT=1` / `RELEASE=0`），已实测
- `SOURCE_MANIFEST.sha256` 同步被改文件的哈希

完整补丁：[`port/frd-wx9.patch`](port/frd-wx9.patch)，SHA-256：

```
d14e743e505f2358cea92d7c243c8b6b740020d1c05869b7a0a00aff0acb0497
```

<!-- 若补丁更新，请同时更新上面的哈希与 docs/port-record.md 第 4 节 -->

推导依据见 [docs/port-record.md](docs/port-record.md)。

## 如何验证来源

```bash
# 1. 补丁文件未被篡改
sha256sum port/frd-wx9.patch

# 2. 工作树确实包含完整补丁
git apply --check --reverse port/frd-wx9.patch && echo "工作树已包含完整补丁"

# 3. 除上述 4 个文件外，子树与上游一致
git show --stat $(git log --format=%H --reverse | head -1) -- fingerprint | tail -1
```

第 3 条的 "vendor" 提交中包含的就是上游原样子树；之后只有 "port" 与 "docs" 两个提交。

## 如何重新同步上游

```bash
scripts/sync-upstream.sh <新的上游提交>
```

脚本会：重新导出 `fingerprint/` → 重放 `port/frd-wx9.patch` → 重算 `SOURCE_MANIFEST.sha256`。

若上游改动了同一批文件，补丁会冲突。此时：

1. 手工把同样的 4 处改动应用到新树上；
2. 重新生成补丁：`git diff -- fingerprint > port/frd-wx9.patch`；
3. 更新本文件的补丁哈希与基线提交；
4. 更新 `docs/port-record.md` 第 2 节的基线提交。

## 许可分层

| 内容 | 许可 |
|---|---|
| `fingerprint/` 内的驱动与 libfprint 集成代码 | LGPL-2.1-or-later（`fingerprint/driver/goodix51a0/COPYING`）|
| `fingerprint/` 内其余上游材料 | GPL-2.0-only（根目录 [LICENSE](LICENSE)）|
| 本仓库新增的 `scripts/`、`tools/`、`docs/`、`port/` | GPL-2.0-only |
| [LICENSES.md](LICENSES.md)、[SECURITY.md](SECURITY.md) | 沿用上游原文 |

## 不包含的内容

- 任何 Huawei/Goodix Windows 驱动或固件二进制
- 指纹模板、PMK、按设备唯一的密钥材料
- 构建产物（`fingerprint/packaging/arch/src|pkg`、`*.pkg.tar.zst`）
- 上游仓库中的 GPU 管理、KDE 定制补丁、HUAWEI 控制中心
