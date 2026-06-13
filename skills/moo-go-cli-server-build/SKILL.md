---
name: moo-go-cli-server-build
description: 媒资组 Go 项目构建体系，当搭建含 cmd/server 与 cmd/cli 双入口结构的 Go 项目时触发。提供 Makefile + custom-build.sh 模板，支持 CLI 全平台固定构建、Server 按需编译、skills zip 打包分发。
---

# Go CLI + Server 构建体系

适用于 `cmd/server` + `cmd/<cli>` 双入口的 Go 项目，提供 Makefile + custom-build.sh 构建脚手架。

## 核心设计

**CLI 和 Server 构建策略不同：**

| 产物 | 构建策略 | 原因 |
|------|---------|------|
| **CLI** | 固定全平台（linux/darwin/windows），带后缀，打入 zip | 供用户下载，需覆盖所有平台 |
| **Server** | 受 `-p`/`-s` 控制，只编译目标部署平台 | 部署到特定环境，只需一个平台 |

**最终产物：`<name>_skills.zip`**，内含全平台 CLI 二进制 + skill 文件，用于分发给 AI Agent 使用。

## 项目结构前提

```
project/
├── cmd/
│   ├── server/main.go    # 服务端入口
│   └── <cli>/main.go     # CLI 入口
├── skills/
│   └── <skill-name>/     # skill 文件（SKILL.md 等）
├── Makefile
└── custom-build.sh
```

## custom-build.sh 用法

```bash
./custom-build.sh                      # server 当前平台无后缀 + CLI 全平台 + 打包 zip
./custom-build.sh -p linux             # server linux/amd64 带后缀 + CLI 全平台 + 打包 zip
./custom-build.sh -p linux -s          # server linux 去后缀（部署用）+ CLI 全平台 + 打包 zip
./custom-build.sh -p darwin            # server darwin（amd64+arm64）带后缀
./custom-build.sh -p windows           # server windows 带后缀
```

### 适配新项目（只改脚本顶部 6 个变量）

```bash
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
```

> ⚠️ `ZIP_FOLDER` 必须与 SKILL.md 中的 `name` 字段一致，Claude 解压后才能正确识别 skill 目录。

## 产物结构

### zip 内容（`myapp_skills.zip`）

```
myapp/
├── myapp-cli-linux-amd64
├── myapp-cli-darwin-amd64
├── myapp-cli-darwin-arm64
├── myapp-cli-windows-amd64.exe
├── SKILL.md
└── references/
    └── ...
```

### 各场景产物

| 命令 | Server 产物 | CLI 产物 | zip |
|------|------------|---------|-----|
| `./custom-build.sh` | `myapp`（当前平台） | 全平台带后缀 | ✅ |
| `./custom-build.sh -p linux` | `myapp-linux-amd64` | 全平台带后缀 | ✅ |
| `./custom-build.sh -p linux -s` | `myapp`（去后缀） | 全平台带后缀 | ✅ |

## Makefile 核心 target

| 命令 | 说明 |
|------|------|
| `make build` | 编译当前平台 server + CLI |
| `make server` | 仅编译 server（当前平台） |
| `make build-linux-server` | 交叉编译 server linux/amd64 |
| `make build-linux-cli` | 交叉编译 CLI linux/amd64 |
| `make build-darwin-cli` | 交叉编译 CLI darwin（amd64 + arm64） |
| `make build-windows-cli` | 交叉编译 CLI windows/amd64 |
| `make clean` | 清理所有平台产物 |

完整模板见 [templates/Makefile](templates/Makefile) 和 [templates/custom-build.sh](templates/custom-build.sh)。

## 常见错误

| 问题 | 原因 | 修复 |
|------|------|------|
| zip 内 skill 目录名与 skill name 不一致 | `ZIP_FOLDER` 写错 | 必须与 SKILL.md `name` 字段一致 |
| CLI zip 后被误删 | 脚本会清理根目录 CLI 二进制 | 正常，CLI 已在 zip 内 |
| darwin 只产出一个架构 | `build-darwin-cli` 只编了 amd64 | Makefile 的 darwin-cli target 需同时编 amd64 + arm64 |
| `-s` 后 server 仍有后缀 | for 循环未匹配到文件 | 检查 `${SERVER_BIN}-${PLATFORM}-*` glob 是否与实际文件名一致 |
