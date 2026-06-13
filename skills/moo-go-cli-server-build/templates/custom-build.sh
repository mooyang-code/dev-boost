#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# custom-build.sh — 构建 server & CLI，并打包 skills zip
#
# CLI 固定编译全平台带后缀版本（供用户下载，不受 -p/-s 影响）：
#   <CLI_BIN>-linux-amd64
#   <CLI_BIN>-darwin-amd64
#   <CLI_BIN>-darwin-arm64
#   <CLI_BIN>-windows-amd64.exe
#
# Server 受 -p / -s 参数控制（部署到指定环境）：
#   ./custom-build.sh                      # server 当前平台无后缀：<SERVER_BIN>
#   ./custom-build.sh -p linux             # server linux/amd64 带后缀：<SERVER_BIN>-linux-amd64
#   ./custom-build.sh -p darwin            # server darwin 带后缀（amd64+arm64）
#   ./custom-build.sh -p windows           # server windows 带后缀：<SERVER_BIN>-windows-amd64.exe
#   ./custom-build.sh -p linux --no-suffix # server linux 去掉后缀：<SERVER_BIN>
#   ./custom-build.sh -p linux -s          # 同上，简写
#
# 最终打包：所有平台 CLI 二进制 + skills/<SKILL_NAME>/ → <SKILL_NAME>_skills.zip
# ---------------------------------------------------------------------------

# ===== 按项目修改以下变量 =====
SERVER_BIN="myapp"
CLI_BIN="myapp-cli"
SKILLS_DIR="skills/myapp"      # skill 目录路径（相对项目根）
ZIP_NAME="myapp_skills.zip"    # 产物 zip 名
ZIP_FOLDER="myapp"             # zip 内顶层文件夹名（必须与 skill name 一致）
CLI_BINS=(
  "${CLI_BIN}-linux-amd64"
  "${CLI_BIN}-darwin-amd64"
  "${CLI_BIN}-darwin-arm64"
  "${CLI_BIN}-windows-amd64.exe"
)
# =============================

PLATFORM=""
NO_SUFFIX=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform|-p)
      PLATFORM="${2:-}"
      shift 2
      ;;
    --no-suffix|-s)
      NO_SUFFIX=true
      shift
      ;;
    *)
      echo "未知参数: $1" >&2
      echo "用法: $0 [-p linux|darwin|windows] [--no-suffix|-s]" >&2
      exit 1
      ;;
  esac
done

if [[ -n "$PLATFORM" ]] && [[ "$PLATFORM" != linux && "$PLATFORM" != darwin && "$PLATFORM" != windows ]]; then
  echo "不支持的平台: $PLATFORM（可选：linux darwin windows）" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 第一步：构建 Server（受 -p / -s 控制）
# ---------------------------------------------------------------------------
echo ""
echo "=== 构建 Server ==="

if [[ -z "$PLATFORM" ]]; then
  # 无 -p：当前平台，无后缀
  make server
else
  # 指定平台：交叉编译 server
  make "build-${PLATFORM}-server"

  if [[ "$NO_SUFFIX" = true ]]; then
    echo ""
    echo ">>> 去除 server 平台后缀"
    if [[ "$PLATFORM" = windows ]]; then
      mv -f "${SERVER_BIN}-windows-amd64.exe" "${SERVER_BIN}.exe"
      echo "    ${SERVER_BIN}-windows-amd64.exe  →  ${SERVER_BIN}.exe"
    else
      for f in "${SERVER_BIN}-${PLATFORM}"-*; do
        [[ -f "$f" ]] || continue
        mv -f "$f" "${SERVER_BIN}"
        echo "    $f  →  ${SERVER_BIN}"
        break  # 只取第一个（amd64）
      done
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 第二步：构建 CLI 全平台（固定带后缀，不受 -p / -s 影响）
# ---------------------------------------------------------------------------
echo ""
echo "=== 构建 CLI（全平台）==="

make build-linux-cli
make build-darwin-cli
make build-windows-cli

# ---------------------------------------------------------------------------
# 第三步：打包 skills zip
#   结构：<ZIP_FOLDER>/
#           ├── <CLI_BIN>-linux-amd64
#           ├── <CLI_BIN>-darwin-amd64
#           ├── <CLI_BIN>-darwin-arm64
#           ├── <CLI_BIN>-windows-amd64.exe
#           └── <skills 目录下的所有文件>
# ---------------------------------------------------------------------------
echo ""
echo "=== 打包 ${ZIP_NAME} ==="

TMP_DIR="$(mktemp -d)"
PKG_DIR="${TMP_DIR}/${ZIP_FOLDER}"
mkdir -p "$PKG_DIR"

# 复制全平台 CLI 二进制到顶层文件夹
for bin in "${CLI_BINS[@]}"; do
  if [[ -f "$bin" ]]; then
    cp -f "$bin" "${PKG_DIR}/${bin}"
    echo "    + ${bin}"
  else
    echo "    ⚠️  ${bin} 不存在，跳过"
  fi
done

# 复制 skill 文件（保留子目录结构）
if [[ -d "$SKILLS_DIR" ]]; then
  cp -r "$SKILLS_DIR"/. "${PKG_DIR}/"
  echo "    + ${SKILLS_DIR}/ (skill 文件)"
else
  echo "    ⚠️  ${SKILLS_DIR} 目录不存在，跳过 skill 文件"
fi

# 打包：从 TMP_DIR 出发，zip 内自带 <ZIP_FOLDER>/ 顶层文件夹
rm -f "$ZIP_NAME"
(cd "$TMP_DIR" && zip -r - "${ZIP_FOLDER}") > "$ZIP_NAME"
rm -rf "$TMP_DIR"

# 清理根目录下的 CLI 二进制（已打入 zip，不再需要）
echo ""
echo ">>> 清理根目录 CLI 二进制"
for bin in "${CLI_BINS[@]}"; do
  if [[ -f "$bin" ]]; then
    rm -f "$bin"
    echo "    removed: ${bin}"
  fi
done

echo ""
echo "    Done: ./${ZIP_NAME}"
echo ""
echo "zip 内容："
unzip -l "$ZIP_NAME" | tail -n +4 | head -n -2 | awk '{print "    " $NF}'
