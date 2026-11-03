#!/usr/bin/env bash
# 从上游重新同步 fingerprint/ 子树，并重放 FRD-WX9 移植补丁
#
# 用法: scripts/sync-upstream.sh <upstream-commit>
# 例:   scripts/sync-upstream.sh 0eebade95521dc17317235a1b27017ad73f44c16
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/GodsQuantum/huawei-matebook-13-linux.git}"
COMMIT=${1:-}

if [[ -z ${COMMIT} ]]; then
  echo "用法: $0 <upstream-commit>" >&2
  exit 2
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "==> 获取上游 $COMMIT"
git clone --filter=blob:none --no-checkout "$UPSTREAM_URL" "$tmp/up" >/dev/null 2>&1
git -C "$tmp/up" checkout --detach "$COMMIT" >/dev/null 2>&1

echo "==> 替换 fingerprint/ 子树"
rm -rf "$ROOT/fingerprint"
git -C "$tmp/up" archive "$COMMIT" fingerprint | tar -x -C "$ROOT"

echo "==> 重放 port/frd-wx9.patch"
if git -C "$ROOT" apply --check port/frd-wx9.patch 2>/dev/null; then
  git -C "$ROOT" apply port/frd-wx9.patch
  echo "    补丁已应用"
else
  echo "    补丁无法直接应用（上游改动过相关文件）" >&2
  echo "    请手工把同样的 4 处改动应用到 fingerprint/ 后，再更新补丁：" >&2
  echo "    git -C \"$ROOT\" diff -- fingerprint > port/frd-wx9.patch" >&2
  exit 1
fi

echo "==> 同步源码清单哈希"
python3 - "$ROOT" <<'PY'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1]) / "fingerprint/driver/goodix51a0"
man = root / "SOURCE_MANIFEST.sha256"
out = []
for ln in man.read_text().splitlines(True):
    parts = ln.split()
    if len(parts) == 2 and (root / parts[1]).is_file():
        out.append(f"{hashlib.sha256((root / parts[1]).read_bytes()).hexdigest()}  {parts[1]}\n")
    else:
        out.append(ln)
man.write_text("".join(out))
print("    清单已更新")
PY

echo
echo "完成。请检查 git diff，然后更新 port/frd-wx9.patch 与 docs/port-record.md 中的基线提交。"
