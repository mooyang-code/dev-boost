# C2 — CLI 调用契约

## 标准

skill 里**所有可粘贴命令**必须满足：

1. **跨 Shell 自洽**：每条命令都自带「定位 + 加载 + 执行」三段，不假设上一条的环境变量还在。
2. **平台中立**：路径用 `<SKILL_DIR>` 占位，不写死任何 Agent 产品的安装目录。
3. **flag 与真实 CLI 一致**：每个 flag 都能在 `<cli> --help` / `<cli> schema` 中找到。
4. **子技能可独立启动**：任何可能被单独索引的 `subskills/**/SKILL.md` 都不能依赖主 `SKILL.md` 已被读取。

## 为什么强调"每条都要带前缀"

Agent 工具调用的每一次 `Shell` 调用通常是**新的子进程**：

```bash
# Agent 第 1 次调用：source 设置了 $DM
unset SKILL_DIR DM && source "<SKILL_DIR>/find_dm.sh" && "$DM" --help

# Agent 第 2 次调用：是新进程，$DM 已经空了
"$DM" --token ... --gateway ... project list
# → zsh:1: command not found: --token   （$DM 展开为空，--token 被当成命令）
```

这是**真实发生过**的反复试错 case。修复方法只有一个：SKILL 里写明每条命令必须带 `source` 前缀，并提供完整模板。

## 检查项

- [ ] 所有可粘贴命令都以 `unset SKILL_DIR DM && source "<SKILL_DIR>/find_dm.sh" && "$DM" ...` 开头。
- [ ] 如果存在嵌套子技能，每个 `subskills/**/SKILL.md` 顶部都有“直接加载保护”：说明子技能可能被 Agent 直接触发，并给出完整自举命令模板。
- [ ] 子技能不出现裸 `<cli> ...` / `vmedia-dm ...` 示例；CLI 不要求在 `PATH` 中，所有示例都走 `"$DM"`。
- [ ] 文档不引导 `which <cli>` / `command -v <cli>` 判断 CLI 是否安装；正确判断方式是 `source "<SKILL_DIR>/find_dm.sh"` 是否能定位安装目录内二进制。
- [ ] 路径中不出现任何具体安装目录（`~/.box` / `~/Library/Application Support/Box` / `~/.workbuddy`）。
- [ ] 用 `<cli> schema --all` / `<cli> --help` 校对每个 flag，不存在过期 flag（如已删除的 `--output`）。
- [ ] 任务/状态相关 flag 名字统一（团队约定例：`--task-id`，**不是** `--task` / `--id` / `--taskid`）。
- [ ] 网关/服务地址用 `<gateway-url>` 占位，或在文首集中给一个示例值，正文不重复硬编码。
- [ ] **必须实跑一遍**：把命令直接复制到一个干净 shell（不预先 source 任何东西）粘贴执行，能跑通才算通过。

## 反模式 → 正解

### 反模式 A — 跨调用复用 `$DM`

```bash
# ❌ skill 里这样写：
$DM --token "$API_TOKEN" --gateway http://gw.test project list
```

```bash
# ✅ 改成：
unset SKILL_DIR DM && source "<SKILL_DIR>/find_dm.sh" \
  && "$DM" --token "$API_TOKEN" --gateway http://gw.test project list
```

### 反模式 B — 写死品牌目录

```bash
# ❌
source "/Users/mooyang/.box/Workspace/find_dm.sh"
# ❌
source "/Users/mooyang/Library/Application Support/Box/engine/skills/user/datamind/find_dm.sh"
```

```bash
# ✅
source "<SKILL_DIR>/find_dm.sh"
```

`<SKILL_DIR>` 应在 SKILL 顶部明确说明：「由你的 Agent 平台告知，通常是 `~/.<your-agent>/skills/datamind` 或类似目录」。

### 反模式 C — 子技能直接触发后裸跑 CLI

真实日志：

```text
datamind-export 被正确触发
Agent 执行：vmedia-dm project list
Agent 执行：which vmedia-dm || echo "vmedia-dm not found in PATH"
Agent 结论：DataMind CLI 还没有安装或配置
```

根因：平台可能把 `subskills/export/SKILL.md` 当成独立入口直接加载。Agent 没读主 `SKILL.md`，只看到子技能流程，于是按命令名裸跑。

修复：每个子技能入口都要内联最小自举块：

````markdown
## 直接加载保护（必须先做）

本子技能可能被 Agent 直接触发，而不会先读取 `../../SKILL.md`。因此执行任何命令前必须先完成 CLI 自举：

```bash
unset SKILL_DIR DM && source "<SKILL_DIR>/find_dm.sh" \
  && "$DM" --token "$API_TOKEN" --gateway <gateway-url> <subcommand> [args...]
```

- `<SKILL_DIR>` 必须是用户安装后的 skill 根目录，里面有 `SKILL.md`、`find_<cli>.sh`、`<cli>-*`；不是 `subskills/<name>/`，也不是仓库源码目录。
- 如果只知道当前子技能文件路径，`<SKILL_DIR>` 取当前目录向上两级（`subskills/<name>/../..`）。
- 禁止直接执行 `<cli> ...`；CLI 不要求在 `PATH` 中。
- 禁止用 `which <cli>` 判断未安装；应检查是否正确 `source "<SKILL_DIR>/find_<cli>.sh"`。
````

### 反模式 D — 用了 CLI 已删除的 flag

最近一次实际事故：CLI 把 `--output` 整体移除（强制 stdout 永远 JSON），但 SKILL 各处仍残留 `--output json` / `--output table`，导致：

```text
$ "$DM" project list --output json
Error: unknown flag: --output
exit 2
```

review 必查：

```bash
"$DM" schema --all 2>/dev/null | jq -r '..|.flags?//empty|.[]|.name' | sort -u > /tmp/real-flags.txt
rg -oE '\-\-[a-z][a-z0-9-]+' \
  skills/<your-skill>/SKILL.md \
  skills/<your-skill>/references/ \
  skills/<your-skill>/subskills/ | \
  sed -E 's/.*(--[a-z][a-z0-9-]+).*/\1/' | sort -u > /tmp/doc-flags.txt
comm -23 /tmp/doc-flags.txt /tmp/real-flags.txt
```

输出非空 = 文档里有实际不存在的 flag，必须删。

## 强烈推荐：在 SKILL 里加「命令模板」段

```bash
# 通用模板（每条命令都按这个格式拼）
unset SKILL_DIR DM && source "<SKILL_DIR>/find_dm.sh" \
  && "$DM" --token <真实-token-字符串> --gateway <gateway-url> <子命令> [flags]
```

让 Agent 直接复制这个模板替换尾部，不再自己拼凑。
