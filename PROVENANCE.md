# 出处与改动清单

## 上游

| 项 | 值 |
|---|---|
| 仓库 | https://github.com/GodsQuantum/huawei-matebook-13-linux |
| 基线提交 | `0eebade95521dc17317235a1b27017ad73f44c16` |
| 提交日期 | 2026-11-02 |
| 提交标题 | `feat(gxfp): HUAWEI installs QA59 with preserved fingerprint templates (#70)` |
| 引入的子树 | `fingerprint/`（370 个文件，约 1.7 MB）|
| 引入方式 | `git archive <commit> fingerprint/ \| tar -x` |

`fingerprint/` 是上游官方提供的 **driver-only 分发**（不含 GPU 管理器、HUAWEI 控制中心与
KDE 定制补丁），因此可以单独成仓。

## 本仓库的改动

相对基线，只修改了 4 个文件，全部在 `fingerprint/` 内：

```
fingerprint/driver/goodix51a0/gx51_transport.h
fingerprint/driver/goodix51a0/gx51_transport.c
fingerprint/integration/prestart-recover/gxfp51a0-prestart-recover.c
fingerprint/driver/goodix51a0/SOURCE_MANIFEST.sha256
```

完整补丁见 [`port/frd-wx9.patch`](../port/frd-wx9.patch)，SHA-256：

```
d14e743e505f2358cea92d7c243c8b6b740020d1c05869b7a0a00aff0acb0497
```

校验方式：

```bash
sha256sum port/frd-wx9.patch
git apply --check --reverse port/frd-wx9.patch   # 若工作树已含补丁，反向检查应通过
```

改动内容与推导依据见 [port-record.md](port-record.md)。

## 如何验证来源

```bash
# 1. 子树是否与上游一致（除 4 个文件外）
git log --oneline -- fingerprint | tail -2     # 应有 "vendor: ..." 提交

# 2. 补丁是否完整
git apply --check --reverse port/frd-wx9.patch && echo "工作树已包含完整补丁"
```

## 如何重新同步上游

```bash
scripts/sync-upstream.sh <新的上游提交>
```

脚本会：重新导出 `fingerprint/` 子树 → 重放 `port/frd-wx9.patch` → 重算源码清单哈希。
若上游改动了同一批文件，补丁会冲突，需要手工合并后重新生成补丁并更新
`docs/port-record.md` 里的基线提交。

## 许可分层

| 内容 | 许可 |
|---|---|
| `fingerprint/` 内的驱动与 libfprint 集成代码 | LGPL-2.1-or-later（`fingerprint/driver/goodix51a0/COPYING`）|
| `fingerprint/` 内其余上游材料 | GPL-2.0-only（根目录 `LICENSE`）|
| 本仓库新增的 `scripts/`、`tools/`、`docs/`、`port/` | GPL-2.0-only |
| 根目录 `LICENSES.md`、`SECURITY.md` | 沿用上游原文 |

## 不包含的内容

- 任何 Huawei/Goodix Windows 驱动或固件二进制
- 指纹模板、PMK、按设备唯一的密钥材料
- 构建产物（`fingerprint/packaging/arch/src|pkg`、`*.pkg.tar.zst`）
- 上游仓库中的 GPU 管理、KDE 定制补丁、HUAWEI 控制中心
