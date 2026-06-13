# C4 — 轮询 / 状态查询

## 标准

任何"创建任务 → 等结果 → 取下载链接"类流程，SKILL 必须给**两段官方模板**（一行版 + 循环版），并显式禁止 Agent 自创 for + python 解析。

## 真实翻车 case（必看）

Agent 自创轮询：

```bash
for i in 1..12; do
  resp=$("$CLI_BIN" ... export status --task-id $ID 2>/dev/null)
  echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status'))"
  st=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status'))")
  if [ "$st" = "completed" ]; then break; fi
  sleep 5
done
```

问题链：

1. `2>/dev/null` 把所有 stderr 吞了；source 时 find_cli.sh 的 stderr 提示 → 进 stderr 不影响。但 Agent **看不到**自己出错时的提示。
2. `python3 -c json.load(sys.stdin)` 在 stdin 为空时抛 `JSONDecodeError`；Agent **以为 stdout 没东西**。
3. Agent 于是**单独再调一次** `export status` 验证，浪费一次完整调用。

修复：SKILL 直接给"已经验证过"的官方模板。

## 官方模板（直接复制到 SKILL.md / cli-reference.md）

### 一行版（首选）

```bash
unset SKILL_DIR CLI_BIN && source "<SKILL_DIR>/find_cli.sh" \
  && "$CLI_BIN" --token "$API_TOKEN" --gateway <url> export status --task-id <ID> \
  | jq '{status, progress, download_url: (.steps[]?.output.download_url // .download_url // empty)}'
```

适用：手动单次查；或 Agent 已知任务即将完成时的最后一查。

### 循环版（最多等 10 分钟）

```bash
unset SKILL_DIR CLI_BIN && source "<SKILL_DIR>/find_cli.sh" || exit 1
TASK_ID=<ID>
for i in $(seq 1 60); do
  resp=$("$CLI_BIN" --token "$API_TOKEN" --gateway <url> export status --task-id "$TASK_ID")
  status=$(echo "$resp" | jq -r '.status // "unknown"')
  echo "poll #$i status=$status"
  case "$status" in
    completed) echo "$resp" | jq '{status, download_url: (.steps[]?.output.download_url // .download_url)}'; exit 0 ;;
    failed)    echo "$resp" | jq '{status, error}'; exit 1 ;;
  esac
  sleep 10
done
echo "timeout after 10 minutes" >&2
exit 1
```

要点：

- **不**用 `2>/dev/null`：业务输出在 stdout，stderr 留着看 source 提示。
- 用 `jq` 不用 python：`jq` 兼容 stdin 空、错误更清晰。
- `case`/`exit` 即时退出，避免 Agent "再保险查一次"。
- `sleep 10` 而不是 `sleep 5`：减少无效轮询；后端通常 10s+ 才更新一次。

## 检查项

- [ ] SKILL 含**官方一行版** + **官方循环版**，命名清晰（如 `## 轮询模板（必用）`）。
- [ ] 标注「**禁止 Agent 自创轮询脚本**」，并列出反模式（不要 `2>/dev/null`、不要 `python -c json.load`）。
- [ ] 模板里 status 已 `completed`，**不要**再调 `<resource> download` / 重复 status；下载链接直接从 status 输出抽取。
- [ ] CLI **真实**支持下载链接放在 status 里（不放就让后端先放）。
- [ ] 状态机所有终态枚举都列出（`completed` / `failed` / `cancelled` ...），SKILL 与 CLI 实现一致。
- [ ] `--task-id` 等关键 flag 名固定下来，不允许 SKILL 与 CLI 不一致（典型案例：`--task` vs `--task-id`，Agent 无脑试错 3-5 次）。

## SKILL 文案建议（直接抄）

````markdown
### 任务状态查询：用官方模板，不要自创

示例平台的所有"创建任务后查状态"流程统一参数 `--task-id`（**不是** `--task` / `--id`）。
请直接复制下面两段，不要自己写循环。

#### 单次查（首选）

```bash
unset SKILL_DIR CLI_BIN && source "<SKILL_DIR>/find_cli.sh" \
  && "$CLI_BIN" --token "$API_TOKEN" --gateway <url> export status --task-id <ID>
```

返回 JSON 中：
- `.status == "completed"` → 完成，下载链接在 `.steps[].output.download_url`
- `.status == "failed"`    → 失败，原因在 `.error`
- `.status == "running"`   → 等

#### 循环（最多 10 分钟）

[贴上循环版]

#### 反模式（禁止）

- ❌ `2>/dev/null` 后用 python json.load 解析 → stdin 空时抛错，会误判
- ❌ `--task` / `--id` 等参数名 → CLI 只认 `--task-id`
- ❌ 看到 completed 后再调 `export download` → status 输出已自带 download_url
````
