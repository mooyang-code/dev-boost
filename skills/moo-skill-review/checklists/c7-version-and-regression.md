# C7 — 版本同步与实跑回归

## 标准

skill 是「文档 + CLI 二进制 + 配套脚本」的**三位一体**产物。任何一处变更都必须：

1. 有 **VERSION 文件**记录当前版本（独立文件，**不在 SKILL.md 里硬编码**）。
2. 构建脚本（`custom-build.sh` / `Makefile`）支持 `--bump [patch|minor|major]`，从 VERSION 文件读 + 增 + 写回。
3. 版本号通过 **build-time ldflags** 注入 CLI 二进制：`<cli> --version` 输出 JSON 含 `version / buildTime / gitCommit`。
4. **实跑回归**：每次改 skill，必须把更新同步到 Agent 安装目录，跑一遍 SKILL 文档里给的「新手三连」命令。

## 真实踩坑

### 坑 1 — VERSION 与 SKILL.md 双写漂移

早期把版本号写进 SKILL.md 顶部 `<EXTREMELY-IMPORTANT>` 块；忘了更新 SKILL.md → Agent 加载到老的 SKILL.md → 用了老规则。后来去掉 SKILL.md 里的版本号，**只在 VERSION 文件里维护**，由构建脚本 + `<cli> --version` 暴露。

### 坑 2 — 改完没同步到安装目录

Agent 安装目录（每个产品不一样：`~/.box/...` / `~/Library/Application Support/Box/.../skills/datamind/` / `~/.workbuddy/skills/datamind/`）。dev-boost 仓库改完了，但**没同步**过去 → Agent 仍在跑老 SKILL + 老二进制 → 反复试错你以为修过的坑。

### 坑 3 — `custom-build.sh` 没传 `--bump` 也炸

早期实现把 VERSION_FILE 解析放在 `--bump` 之外，触发 `set -u` 的 `unbound variable`。修复：所有版本相关变量都在「确认 `--bump` 传入」分支内引用，普通构建路径**完全不读** VERSION 文件。

## 检查项

### 文件层

- [ ] 仓库根（或 skill 目录下）有 `VERSION` 文件，单行 `vMAJOR.MINOR.PATCH`（如 `v1.2.3`）。
- [ ] **SKILL.md 内不出现版本号字符串**（避免双写漂移）。
- [ ] `custom-build.sh` 实现 `--bump patch|minor|major`，仅在 `--bump` 传入时读写 VERSION。
- [ ] 普通构建命令（不带 `--bump`）即使 VERSION 文件不存在也能跑通。

### CLI 层

- [ ] `<cli> --version` 输出 JSON：`{"version":"v1.2.3","buildTime":"...","gitCommit":"..."}`。
- [ ] `<cli> version` 子命令存在且与 `--version` 输出一致。
- [ ] 通过 `-ldflags` 注入：

```bash
go build -ldflags "
  -X 'main.version=$VERSION'
  -X 'main.buildTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)'
  -X 'main.gitCommit=$(git rev-parse --short HEAD)'
" ./cmd/cli
```

### 回归层（每次改完必做）

```bash
# 1. 查老安装目录在哪（举例：用户全局搜）
ls "$HOME/.workbuddy/skills/datamind" 2>/dev/null
ls "$HOME/Library/Application Support/Box/engine/skills"/*/datamind 2>/dev/null

# 2. 同步 SKILL + references + find_dm.sh + 二进制
INSTALL_DIR="<上一步找到的目录>"
cp skills/datamind/SKILL.md "$INSTALL_DIR/"
cp -r skills/datamind/references "$INSTALL_DIR/"
cp skills/datamind/find_dm.sh "$INSTALL_DIR/"
cp dist/moo-dm-*  "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/"moo-dm-*

# 3. 跑 SKILL 顶部的新手三连
unset SKILL_DIR DM && source "$INSTALL_DIR/find_dm.sh" && "$DM" --version
unset SKILL_DIR DM && source "$INSTALL_DIR/find_dm.sh" \
  && "$DM" --token "$API_TOKEN" --gateway <url> project list | jq '.items|length'
unset SKILL_DIR DM && source "$INSTALL_DIR/find_dm.sh" \
  && "$DM" --token "$API_TOKEN" --gateway <url> schema export create \
  | jq '.commands[0].flags|map(.name)'
```

任何一条不通过 → 回到对应 checklist 修。

## SKILL 文案建议

在 SKILL 顶部「快速验证」一节给：

````markdown
## 快速验证（怀疑是否最新版时跑这三条）

```bash
# 1. 查 CLI 版本
unset SKILL_DIR DM && source "<SKILL_DIR>/find_dm.sh" && "$DM" --version

# 2. 跑一条只读命令验证 token + 网关
unset SKILL_DIR DM && source "<SKILL_DIR>/find_dm.sh" \
  && "$DM" --token "$API_TOKEN" --gateway <url> project list | jq '.items|length'

# 3. 看复杂参数 schema 是否带 json_schema + remarks
unset SKILL_DIR DM && source "<SKILL_DIR>/find_dm.sh" \
  && "$DM" --token "$API_TOKEN" --gateway <url> schema export create \
  | jq '.commands[0].flags[] | select(.name=="filter") | {has_schema:(.json_schema|length>0), has_remarks:(.remarks|length>0)}'
```

任一条失败 → skill 没装对，先 `<install/upgrade 命令>`。
````
