#!/usr/bin/env bash
# scripts/lint-stdout.sh
# 检查 cmd/<your-cli>/*.go 中是否存在违规的 stdout 写入。
#
# 规则：
#   - 只有 output.go 允许调用 fmt.Print / fmt.Printf / fmt.Println（业务结果统一出口）
#   - 其他文件必须使用 progressf / progressln / hintln（写入 stderr）
#
# 退出码：
#   0 - 全部通过
#   1 - 发现违规
#
# 用法（在项目根的 Makefile 加 target）：
#
#   lint-cli:
#       @bash scripts/lint-stdout.sh
#
# 适配：把下面 CLI_DIR 改成你的 CLI 目录（默认假设是 cmd/cli）。

set -euo pipefail

# === 按项目修改 ===
CLI_DIR="$(cd "$(dirname "$0")/.." && pwd)/cmd/cli"
ALLOWED=("output.go")          # 允许写 stdout 的白名单文件
# ==================

if [[ ! -d "$CLI_DIR" ]]; then
    echo "ERROR: CLI dir not found: $CLI_DIR" >&2
    exit 1
fi

violations=0
while IFS= read -r -d '' file; do
    name="$(basename "$file")"

    skip=false
    for allow in "${ALLOWED[@]}"; do
        if [[ "$name" == "$allow" ]]; then
            skip=true
            break
        fi
    done
    if [[ "$skip" == "true" ]]; then
        continue
    fi

    if [[ "$name" == *_test.go ]]; then
        continue
    fi

    # 匹配 fmt.Print / fmt.Printf / fmt.Println 调用（行首允许有空白）
    if matches=$(grep -nE '^\s*fmt\.(Print|Printf|Println)\(' "$file" 2>/dev/null); then
        echo "VIOLATION: $name 直接写 stdout，请改用 progressf / progressln / hintln" >&2
        echo "$matches" >&2
        violations=$((violations + 1))
    fi
done < <(find "$CLI_DIR" -maxdepth 1 -name '*.go' -print0)

if [[ "$violations" -gt 0 ]]; then
    echo "" >&2
    echo "FAILED: 发现 $violations 个文件存在 stdout 污染。" >&2
    echo "修复方法：把 fmt.Printf/Println 替换为 progressf/progressln（写入 stderr）" >&2
    exit 1
fi

echo "OK: cmd/cli stdout 纪律检查通过"
