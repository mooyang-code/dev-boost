# 反模式案例库（来自真实 Agent 失败转录）

> 本文档记录 `vmedia-dm` / `datamind` skill 迭代过程中**真实发生过**的 Agent 翻车 case。每条都给出 **症状 / 根因 / 修复**，方便 review 时按图索骥。

---

## Case 1 — `command not found: --token`（跨 Shell 调用 `$DM` 为空）

### 症状

```
$ $DM --token "$API_TOKEN" --gateway https://api.github.com/repos/mooyang-code/dev-boost project list
zsh:1: command not found: --token
[Exit code: 127]
```

### 根因

Agent 上一次工具调用里执行了 `source find_dm.sh` 设置了 `$DM`。但当前调用是**新的子进程**——`$DM` 不在新进程的环境里，于是 `$DM` 展开为空，shell 把 `--token` 当成命令。

### 修复

SKILL 里写明：每条 datamind 命令都要带 source 前缀。

```bash
unset SKILL_DIR DM && source "<SKILL_DIR>/find_dm.sh" \
  && "$DM" --token "$API_TOKEN" --gateway <url> <subcmd>
```

并在 SKILL 顶部"通用模板"区把这个写成模板，让 Agent 直接拷贝。

### 关联 checklist

[C2 — CLI 调用契约](../checklists/c2-cli-contract.md)

---

## Case 2 — 401 Unauthorized：token 被截短（正则少了 `.`）

### 症状

```
$ "$DM" --token "$API_TOKEN" --gateway <url> project list
{"error":"401 Unauthorized","message":"PAT Token 无效或已过期"}
```

### 根因

`find_dm.sh` 用 `grep -oE 'tai_pat_[A-Za-z0-9_-]{30,}'` 从 `~/.zshrc` 抓 token——**正则缺 `.`**。真实 token 含 `.` 段分隔（例：`tai_pat_xxx.yyy.zzz`，约 110 字符），正则在第一个 `.` 处截断 → 抓出 51 字符的"假 token" → 401。

### 修复

```bash
# 把字符类加 .
grep -oE 'tai_pat_[A-Za-z0-9_.-]{30,}'

# 加长度健全检查
if [ -n "${API_TOKEN:-}" ] && [ ${#API_TOKEN} -lt 70 ]; then
  echo "⚠️ API_TOKEN 长度异常 (${#API_TOKEN})；可能被截断" >&2
fi
```

### 关联 checklist

[C3 — Token / 凭证](../checklists/c3-token.md)

---

## Case 3 — `❌ 找不到二进制：~/.box/Workspace/vmedia-dm-darwin-arm64`

### 症状

Agent 复制 SKILL 里给的命令：

```
$ source "/Users/mooyang/Library/Application Support/Box/engine/skills/user/datamind/find_dm.sh" && $DM project list --output json
❌ 找不到二进制: /Users/mooyang/.box/Workspace/vmedia-dm-darwin-arm64
```

### 根因

SKILL 里写死了某个 Agent 产品（Box）的路径 `~/.box/Workspace`。Agent 在不同产品（Workbuddy / Box / Cursor）下安装目录完全不同，写死 → 全错。

另外 `find_dm.sh` 依赖 `${BASH_SOURCE[0]}` 解析自身路径，但 zsh 下行为略不同，需要兼容性处理。

### 修复

1. SKILL 里所有路径用 `<SKILL_DIR>` 占位，并说明"由你的 Agent 平台告知"。
2. `find_dm.sh` 自身：

```bash
# 兼容 zsh / bash 的脚本自路径
_self="${BASH_SOURCE[0]:-${(%):-%x}}"
SKILL_DIR="$(cd "$(dirname "$_self")" && pwd)"
export SKILL_DIR
```

3. 给二进制做权限自动修复：

```bash
[ -x "$DM" ] || chmod +x "$DM" 2>/dev/null
# macOS quarantine
command -v xattr >/dev/null 2>&1 && xattr -d com.apple.quarantine "$DM" 2>/dev/null || true
```

### 关联 checklist

[C2 — CLI 调用契约](../checklists/c2-cli-contract.md)

---

## Case 4 — `--task` vs `--task-id`，Agent 试错 3 次

### 症状

Agent 自行猜测：

```
$ "$DM" export status --task EXPxxx
Error: unknown flag: --task

$ "$DM" export status --id EXPxxx
Error: unknown flag: --id

$ "$DM" export status --help | head
... 翻 help 才发现是 --task-id
```

### 根因

SKILL 文档里轮询模板用的是 `--task-id`，但其它示例参差混入了 `--task`，加上 Agent 倾向"猜短的"，于是反复试错。

### 修复

1. SKILL 加铁律：「**所有任务/状态相关命令统一参数 `--task-id`**」，并列出涉及子命令清单。
2. 用 `<cli> schema --all` 与文档做 diff：

```bash
"$DM" schema --all | jq -r '..|.flags?//empty|.[]|.name' | sort -u > /tmp/real-flags.txt
rg -oE '\-\-[a-z][a-z0-9-]+' SKILL.md references/ | sed -E 's/.*(--[a-z][a-z0-9-]+).*/\1/' | sort -u > /tmp/doc-flags.txt
comm -23 /tmp/doc-flags.txt /tmp/real-flags.txt   # 应为空
```

### 关联 checklist

[C2 — CLI 调用契约](../checklists/c2-cli-contract.md)

---

## Case 5 — `2>/dev/null` 吞 stderr 后误判 stdout 为空 → 多查一次

### 症状

Agent 写了循环：

```bash
for i in 1..12; do
  resp=$("$DM" export status --task-id EXPxxx 2>/dev/null)
  echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status'))"
  ...
done
```

跑完后 Agent 自我怀疑："响应被 `2>/dev/null` 丢弃了有效内容——可能 source 的自动加载提示进了 stderr，不影响，但命令本身输出没到 stdout。直接单独查一次："

→ 又**单独**调一次 `export status` 浪费一次完整调用。

### 根因

1. python `json.load(sys.stdin)` 在 stdin 为空时抛 `JSONDecodeError`，print 也跟着失败 → Agent 看不到任何输出 → 误以为 stdout 没东西。
2. 真实情况：`2>/dev/null` 没影响 stdout；只是 source 时 `find_dm.sh` 输出了 token mask 提示进 stderr 被吞了。

### 修复

SKILL 给**官方循环模板**，明确：
- 用 `jq` 不用 `python json.load`（jq 对 stdin 空更友好）
- 不要 `2>/dev/null` 吞 stderr
- 已经看到 `completed`，**禁止再单独查一次**

```bash
unset SKILL_DIR DM && source "<SKILL_DIR>/find_dm.sh" || exit 1
TASK_ID=<ID>
for i in $(seq 1 60); do
  resp=$("$DM" --token "$API_TOKEN" --gateway <url> export status --task-id "$TASK_ID")
  status=$(echo "$resp" | jq -r '.status // "unknown"')
  echo "poll #$i status=$status"
  case "$status" in
    completed) echo "$resp" | jq '{status, download_url: (.steps[]?.output.download_url // .download_url)}'; exit 0 ;;
    failed)    echo "$resp" | jq '{status, error}'; exit 1 ;;
  esac
  sleep 10
done
exit 1
```

### 关联 checklist

[C4 — 轮询](../checklists/c4-polling.md)，[C5 — 输出契约](../checklists/c5-output-contract.md)

---

## Case 6 — `completed` 后再调 `export download`（命令不存在）

### 症状

```
$ "$DM" export download --task-id EXPxxx
Error: unknown command "download" for "vmedia-dm export"
```

### 根因

Agent 习惯"任务完成 → 单独取下载链接"两步走。但 datamind 的设计是：`export status` 输出里**已经包含** `steps[].output.download_url`，不需要单独 download 命令。

### 修复

SKILL 红线：「`export status` 已自带下载链接，禁止再调 `export download`」。
官方模板里直接抽取：

```bash
"$DM" ... export status --task-id <ID> \
  | jq '{status, download_url: (.steps[]?.output.download_url // .download_url // empty)}'
```

### 关联 checklist

[C4 — 轮询](../checklists/c4-polling.md)

---

## Case 7 — `--filter` 写 `op:"like"` → unsupported

### 症状

```
$ "$DM" export create ... --filter '{"logic":"and","groups":[{"conditions":[{"field":"title","op":"like","value":"庆余年"}]}]}'
Error: unsupported op: like
```

### 根因

Agent 凭 SQL/ES 印象写 `like`。真实合法 op：`eq, ne, in, wildcard, prefix, gt, gte, lt, lte, range, exists, not_exists`。

CLI 端 schema 输出不含 `--filter` 的合法 op 清单，Agent 没办法不靠猜。

### 修复

CLI 端给 `--filter` 注入 `json_schema`（含 op enum + 多条 examples）和 `remarks`（讲清 wildcard / prefix 区别、为什么没有 like）：

```go
RegisterFlagJSONSchema(exportCreateCmd, "filter", exportFilterJSONSchema)
RegisterFlagRemarks(exportCreateCmd, "filter", exportFilterRemarks)
```

SKILL 加铁律：拼 `--filter` 前必须先 `schema export create`。

### 关联 checklist

[C6 — schema 自省](../checklists/c6-schema-introspection.md)

---

## Case 8 — option 字段写业务名 → 命中 0 条但不报错

### 症状

```
$ "$DM" export estimate ... --filter '{"logic":"and","groups":[{"conditions":[{"field":"status","op":"eq","value":"published"}]}]}'
{"estimate":0}
```

Agent 以为没数据，反复改 filter 各种试。

### 根因

`status` 字段在存储中是数字 `4`，业务名 `published` 是 UI 上的 label，不参与匹配。option 类型字段必须先 `project field-values --field status` 拿到 `value=4` 再传。

CLI 不报错（`value:"published"` 类型合法），但**永远 0 条**。

### 修复

1. CLI `--filter` 的 `json_schema.value.description` 明确："field_type=option 必须用枚举内部 value，例如 status「已上架」对应 4 则写 4，不要写 published"。
2. SKILL 红线：option 字段先 `project field-values`，传 value 不传 label。
3. 示例统一用真实 value：

```json
{"field":"status","op":"eq","value":4}
```

### 关联 checklist

[C6 — schema 自省](../checklists/c6-schema-introspection.md)

---

## Case 9 — `--output json` 残留 → `unknown flag`

### 症状

```
$ "$DM" project list --output json
Error: unknown flag: --output
```

### 根因

CLI 删了 `--output` flag（强制 stdout 永远 JSON），但 SKILL 文档各处仍有大量 `--output json` 残留。Agent 照着写就 cobra 报错。

### 修复

```bash
# 1. 全文搜
rg -nE '\-\-output\s+(json|table|csv)' skills/<skill>/

# 2. 全部删除
rg -lE '\-\-output\s+(json|table|csv)' skills/<skill>/ | xargs sed -i '' -E 's/ --output (json|table)//g'

# 3. SKILL 加输出契约段
```

### 关联 checklist

[C5 — 输出契约](../checklists/c5-output-contract.md)

---

## Case 10 — `permission denied: vmedia-dm-darwin-arm64`

### 症状

```
$ "$DM" --help
zsh:1: permission denied: /path/to/vmedia-dm-darwin-arm64
[Exit code: 126]
```

### 根因

zip 解压后二进制丢失 +x 权限；macOS 还会加 `com.apple.quarantine` xattr 阻止运行。早期 `find_dm.sh` 对此**无声失败**。

### 修复

`find_dm.sh` 在定位完二进制后：

```bash
[ -x "$DM" ] || chmod +x "$DM" 2>/dev/null

# macOS：去 quarantine
if [ "$(uname -s)" = "Darwin" ] && command -v xattr >/dev/null 2>&1; then
  xattr -d com.apple.quarantine "$DM" 2>/dev/null || true
fi

# 顺手给同目录下其它 vmedia-dm-* 都加 +x
chmod +x "$(dirname "$DM")"/vmedia-dm-* 2>/dev/null || true
```

### 关联 checklist

[C2 — CLI 调用契约](../checklists/c2-cli-contract.md)

---

## Case 11 — 子技能直接触发后裸跑 `vmedia-dm`

### 症状

用户请求：

```text
导出迪丽热巴主演的电视剧
```

Agent 正确触发了 `datamind-export` 子技能，但随后执行：

```bash
vmedia-dm project list
vmedia-dm project fields --type 电视剧
which vmedia-dm || echo "vmedia-dm not found in PATH"
```

最终错误结论：

```text
DataMind CLI (vmedia-dm) 还没有安装或配置。
```

### 根因

平台可能会索引所有 `SKILL.md`，包括 `subskills/export/SKILL.md`。当子技能被直接加载时，Agent 不一定读过主 `datamind/SKILL.md`，也就看不到主文档里的：

- `source "<SKILL_DIR>/find_dm.sh"` 前缀
- `<SKILL_DIR>` 是安装后的 `datamind/` 根目录
- CLI 二进制不要求在 `PATH` 中
- 禁止用 `which vmedia-dm` 判断是否安装

子技能如果只写“先查字段，再导出”的业务流程，Agent 会凭命令名裸跑 `vmedia-dm`，然后把 PATH 中找不到误判成未安装。

### 修复

每个嵌套子技能都要内联“直接加载保护”，不能只引用主 skill 或 reference：

````markdown
## 直接加载保护（必须先做）

本子技能可能被 Agent 直接触发，而不会先读取 `../../SKILL.md`。因此执行任何命令前必须先完成 CLI 自举：

```bash
unset SKILL_DIR DM && source "<SKILL_DIR>/find_dm.sh" \
  && "$DM" --token "$API_TOKEN" --gateway <gateway-url> <subcommand> [args...]
```

- `<SKILL_DIR>` 必须是用户安装后的 skill 根目录，里面有 `SKILL.md`、`find_dm.sh`、`vmedia-dm-*`；不是 `subskills/<name>/`，也不是仓库源码目录。
- 如果只知道当前子技能文件路径，`<SKILL_DIR>` 取当前目录向上两级（`subskills/<name>/../..`）。
- 禁止直接执行 `vmedia-dm ...`；CLI 不要求在 `PATH` 中。
- 禁止用 `which vmedia-dm` 判断未安装；应检查是否正确 `source "<SKILL_DIR>/find_dm.sh"`。
````

### 关联 checklist

[C2 — CLI 调用契约](../checklists/c2-cli-contract.md)，[C9 — Skill 文档架构](../checklists/c9-skill-architecture.md)

---

## 用法

review 时遇到 Agent 翻车现象，先查本 casebook 是否有相同 case。
- 有：直接按"修复"段操作；同时把"症状"截图归档到本仓库 issue 里。
- 没有：先按 7 大类 checklist 排查，定位根因后**追加到本 casebook**。

> 一个原则：**反模式案例库只增不删**。即使 CLI 后续修了，案例本身仍是 review 训练素材。
