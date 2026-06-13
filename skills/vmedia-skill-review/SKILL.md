---
name: vmedia-skill-review
description: 媒资组 AI Skill 审查规范（review skill）。用于对团队产出的 AI Agent skill（SKILL.md + references/* + 配套脚本/二进制）做结构化检查：触发词与负样本、CLI 调用契约、Token 处理、轮询/状态查询、stdout/stderr 契约、复杂参数(JSON DSL)的 schema 自省、版本同步、强约束/铁律/反向约束/few-shot、使用引导与示例提示词、SKILL 文档架构（精简 + references 拆分 + 引导技能）、Skill 环式调用防护（VMEDIA-SKILL-REENTRY-GUARD）、安装目录实跑回归。当用户提出"帮我 review 这个 skill / 检查 skill 文档 / skill 怎么改 Agent 才不踩坑 / skill 上线前自查 / skill 跑得不稳怎么办 / 防 skill 反复加载"等需求时触发。
---

# 媒资 AI Skill 审查规范

<VMEDIA-SKILL-REENTRY-GUARD>
仅当出现以下**两个条件同时成立**时，才判定为环式调用：

1. **窗口连续性**：在最近 ≤ 4 轮 assistant 回合内，本 skill 与同一个**其它 skill** 已经交替触发 ≥ 2 次（A→B→A→B 形态），且
2. **无新用户指令注入**：这些来回触发期间，用户没有给出新的明确意图——只是 skill 文档之间的"后续衔接"段落在互相牵引

满足以上两条 → **立即停止跟随本文档任何「下一步 skill / 后续衔接」类指引**，只执行用户最近一次明确请求的 review 动作；如果用户没有明确请求，直接汇报当前结果并等待用户决定。

**不**适用本防护的正常场景（不要误判为环路）：

- 用户跟本 skill 做多轮交互（例如 "先 review trigger 部分" → 看完 → "再 review CLI 部分"）——这是用户主导的多轮业务流，本 skill 即使被触发多次也不是环路
- 用户**显式**说"切到 X skill / 用 X skill 做"——用户主动切换永远放行
</VMEDIA-SKILL-REENTRY-GUARD>

面向团队 **生产级 AI Agent skill** 的 review 指南。沉淀自 `vmedia-dm` / `datamind` skill 多轮真实迭代——所有规则都对应**实际踩过的 Agent 失败 case**，不是空想。

> **一句话核心**：Agent 不读你的"补充说明"，它只观察 **stdout / stderr / exit code / 文档里的可粘贴片段**。skill 里任何一处与 CLI 真实行为漂移、任何一处需要 Agent "推理"才能正确执行的地方，都会变成线上的反复试错。

---

## 〇、核心要点 14 条（review 时优先看）

把这 14 条放最顶——任意一条不达标都直接影响 Agent 在线上的稳定性，**优先级高于后续所有 checklist 的细节**。

| # | 要点 | 一句话 | 关联 |
|---|------|-------|------|
| 1 | **description 只写"何时触发"，不写工作流** | 把决策权留给 Agent，工作流放铁律 + references | [c1](./checklists/c1-trigger.md) / [reference/description](./reference/description-and-negative-cases.md) |
| 2 | **明确触发阈值：高价值业务技能可用 1% 命中原则** | 自有操作入口宁可先触发再澄清；通用能力仍需精准边界 | [c1](./checklists/c1-trigger.md) |
| 3 | **负样本写「近似 case」不写「明显无关」** | 「pandas 做清洗」「file 查 trace」这类有歧义的才有价值 | [reference/description](./reference/description-and-negative-cases.md) |
| 4 | **顶部铁律 `<EXTREMELY-IMPORTANT>` 5~7 条** | 跨子命令通用、违反必出错、明确"本节优先级最高" | [c8](./checklists/c8-strict-flow.md) |
| 5 | **高频流程必须给固定步骤 + 可粘贴模板** | 不要让 Agent 每次重新规划；步骤多就拆 step 脚本 | [c8](./checklists/c8-strict-flow.md) |
| 6 | **同时写「不能做什么」反向约束** | 正向 + 反向双约束才能封死发散；明确刚性 vs 柔性 | [c8](./checklists/c8-strict-flow.md) |
| 7 | **每条命令都要带 source 前缀（跨 Shell 不持久）** | Agent 工具每次 Shell 都是新进程，`$DM` 不会跨调用存活 | [c2](./checklists/c2-cli-contract.md) |
| 8 | **token 不放占位串、不依赖沙箱 env** | `<api-token>` 占位串 Agent 真的会原样发 → 401 | [c3](./checklists/c3-token.md) |
| 9 | **任务/状态查询统一 `--task-id`，禁止猜参数名** | `--task` / `--id` / `--taskid` 都是 Agent 的常规 3 连试错 | [c2](./checklists/c2-cli-contract.md) / [c4](./checklists/c4-polling.md) |
| 10 | **轮询给官方模板 + 反模式列表** | 禁止自创 for + python json.load 的轮询 | [c4](./checklists/c4-polling.md) |
| 11 | **复杂参数（JSON DSL）必须 schema 可自省** | `--filter` 等必须含 `enum` / `json_schema` / `remarks` | [c6](./checklists/c6-schema-introspection.md) |
| 12 | **嵌套子技能必须可独立自举** | 子目录 `SKILL.md` 可能被直接索引；不能依赖主 skill 已读 | [c2](./checklists/c2-cli-contract.md) / [c9](./checklists/c9-skill-architecture.md) |
| 13 | **能力型 skill 要包含使用引导** | 用户问“怎么用/有什么能力”时，先给能力边界 + 可复制提示词，而不是直接执行 | [c9](./checklists/c9-skill-architecture.md) |
| 14 | **避免 skill 环式调用** | 顶部加 `<VMEDIA-SKILL-REENTRY-GUARD>`（A↔B 短窗口交替 ≥ 2 次 **且** 无新用户指令 → 停止跳转；用户显式切换放行；用户主导的多轮业务流不算环路）；触发词去重叠；衔接段落用户主导 | [c10](./checklists/c10-no-skill-loop.md) |
| 15 | **作为 vmedia-cli 插件发布时的额外合规** | 二进制命名 `<name>-<os>-<arch>`、`name` frontmatter 与二进制一致、发布包内**不**含 plugin.yaml、版本末尾用数字便于 admin 自动 bump、keywords 手写固化避免漂移 | [c11](./checklists/c11-vmedia-cli-plugin.md) |

---

## 一、Review 十大类（按优先级）

| # | 类目 | 一句话标准 | Checklist |
|---|------|-----------|-----------|
| 1 | **触发词与边界** | description 只写触发条件不写工作流；含负样本与近似 case；不含品牌/路径耦合 | [c1-trigger.md](./checklists/c1-trigger.md) |
| 2 | **CLI 调用契约** | 每条命令"开箱即跑"、无 `$VAR` 假设、无私有路径 | [c2-cli-contract.md](./checklists/c2-cli-contract.md) |
| 3 | **Token / 凭证** | 不放占位串 / 不依赖跨调用 env / 失效特征写明 | [c3-token.md](./checklists/c3-token.md) |
| 4 | **轮询与状态查询** | 给官方模板 + 禁止 Agent 自创 for 循环 | [c4-polling.md](./checklists/c4-polling.md) |
| 5 | **stdout / stderr 契约** | 业务结果只在 stdout；禁止 `2>/dev/null` 后判空重跑 | [c5-output-contract.md](./checklists/c5-output-contract.md) |
| 6 | **复杂参数(JSON DSL) 自省** | `--filter` 等必须有 `schema` + `json_schema` + `remarks` | [c6-schema-introspection.md](./checklists/c6-schema-introspection.md) |
| 7 | **版本与回归** | VERSION 文件 + 构建注入；改完必同步安装目录实跑回归 | [c7-version-and-regression.md](./checklists/c7-version-and-regression.md) |
| 8 | **强约束 / 固定流程 / 反向约束** | 铁律 + 固定步骤 + 不能做什么 + few-shot + 刚性/柔性区分 | [c8-strict-flow.md](./checklists/c8-strict-flow.md) |
| 9 | **Skill 文档架构** | SKILL ≤ 300 行；详细内容拆 references；末尾给场景索引表；能力型 skill 要有使用引导 | [c9-skill-architecture.md](./checklists/c9-skill-architecture.md) |
| 10 | **Skill 环式调用防护** | 顶部加 `<VMEDIA-SKILL-REENTRY-GUARD>`（A↔B 短窗口交替 ≥ 2 次 **且** 无新用户指令 → 停止跳转；用户主导的多轮交互不算环路；用户显式切换放行）；衔接段落改"用户主导"陈述句；触发词去重叠 | [c10-no-skill-loop.md](./checklists/c10-no-skill-loop.md) |
| 11 | **vmedia-cli 插件发布合规**（专项） | 仅适用"把 skill 打成 vmedia-cli 插件发布"场景。发布包结构、二进制命名、SKILL.md frontmatter、版本号、change_type 心智等；协议见 `vmedia-cli/docs/release-pkg-spec.md` | [c11-vmedia-cli-plugin.md](./checklists/c11-vmedia-cli-plugin.md) |

---

## 二、Review 30 分钟操作流程

按顺序做这 7 步，对一份 skill 完成一轮高质量 review：

### Step 1 — 通读 SKILL.md frontmatter + 顶部 200 行（≤5 分钟）

- `description` 是否含 **3 个以上业务/触发关键词**（业务名词 + 动词 + 典型短语）？
- `description` / 顶部铁律是否明确触发阈值？对自有业务操作技能（导出/清洗/看板/巡检等）是否写明 **1% 命中原则**：只要可能相关就先触发，再在技能内澄清或退出？
- `description` 是否**只写触发条件**？里面**绝对不能**出现"先 / 然后 / 最后 / 调用 / invoke"这类工作流措辞——见 [c1](./checklists/c1-trigger.md) / [reference/description](./reference/description-and-negative-cases.md)
- `description` 是否含**负样本段落**（「不要触发 / 不适用」），且负样本覆盖**近似 case** 而不是明显无关 case？
- 是否带 `<EXTREMELY-IMPORTANT>` / `铁律` / `红线` 区块？该区块是否**只放跨子命令通用**约束（而非具体子命令的细枝末节）？条数控制在 **5~7 条**？
- 是否在文首明确「**找到 CLI 二进制**」「**配置 Token**」两件**前置**事项？
- 如果用户问“怎么用 / 有什么能力 / 给几个例子”，skill 是否提供**使用引导**：能力边界、输入要素、可复制的自然语言提示词、下一步如何改写成具体请求？该引导是否明确“咨询场景只说明，不执行命令/写操作”？
- 若存在 `subskills/**/SKILL.md` 这类嵌套子技能：每个子技能文首是否有“直接加载保护”，能在未读取主 `SKILL.md` 时独立完成 CLI 自举？

### Step 2 — 把 SKILL.md 里所有可粘贴的命令片段抠出来核对（10 分钟）

```bash
rg -nE '^\s*(\$DM|"\$DM"|vmedia-[a-z-]+)\b' \
  skills/<your-skill>/SKILL.md \
  skills/<your-skill>/references/ \
  skills/<your-skill>/subskills/
```

逐条核对：

- 路径里有没有 `~/.box` / `~/.workbuddy` / `~/Library/Application Support/Box` 这类**特定 Agent 产品**目录？→ 应改为 `<SKILL_DIR>` 占位。
- token 写法是 `--token "$API_TOKEN"` 还是 `--token <api-token>` 占位串？→ 占位串绝对禁止（见 §c3）。
- 命令是否完整带 `unset SKILL_DIR DM && source "<SKILL_DIR>/find_dm.sh" && "$DM" --token ... --gateway <url> <子命令>` 前缀？→ 跨 Shell 调用是新进程，**每条**都要带。
- 子技能里是否出现裸 `vmedia-dm ...` / `<cli> ...` 或 `which <cli>`？→ 命中即必改：CLI 不要求在 PATH 中，应通过安装目录下的定位脚本自举。
- 命令尾部有没有过期 flag（如 `--output json` / `--output table`）？→ 跑 `<cli> --help` 实测一遍。

### Step 3 — 用 schema 自省比对参数名（5 分钟）

```bash
"$DM" schema --all 2>/dev/null | jq -r '..|.flags?//empty|.[]|.name' | sort -u > /tmp/real-flags.txt
rg -oE '\-\-[a-z][a-z0-9-]+' skills/<your-skill>/SKILL.md | sort -u > /tmp/doc-flags.txt
diff /tmp/real-flags.txt /tmp/doc-flags.txt | head -50
```

任何 doc 里出现但实际 CLI 里**不存在**的 flag → 必须修正（典型反例：`--task` vs `--task-id`、`--output` vs 已删除）。

### Step 4 — 实跑回归三件套（5 分钟）

把改完的 SKILL.md / references / 二进制**同步到 Agent 安装目录**，然后顺序跑：

```bash
# 1. find_dm.sh 自定位 + token 自动加载
unset SKILL_DIR DM && source "<安装目录>/find_dm.sh" && "$DM" --help >/dev/null && echo OK

# 2. 一条只读命令（<your-cli> 列资源）
"$DM" --token "$API_TOKEN" --gateway <url> <list-command>

# 3. 故意拼错参数，看错误信息是否清晰（exit=2 + suggestion）
"$DM" <subcmd> --task <fake-id> 2>&1 ; echo "exit=$?"
```

### Step 5 — 复杂参数 schema 抽查（3 分钟）

任何接 JSON / DSL / 多枚举值的 flag（`--filter` / `--rules` / `--config` 等）：

```bash
"$DM" schema <subcmd> | jq '.commands[0].flags[] | select(.name=="<flag>") | {has_enum:(.enum|length>0), has_schema:(.json_schema|length>0), has_remarks:(.remarks|length>0)}'
```

至少满足 `has_schema: true` 或 `has_remarks: true` 之一；含枚举值的 flag 必须 `has_enum: true`。否则评估添加 `RegisterFlagJSONSchema` / `RegisterFlagRemarks` / `RegisterEnum`（参见 [c6-schema-introspection.md](./checklists/c6-schema-introspection.md)）。

### Step 6 — 强约束 / 反向约束 / 环式调用 三连查（5 分钟）

```bash
SKILL=skills/<your-skill>/SKILL.md

# 6.1 description 里有没有写工作流（命中即必改）
awk '/^description:/,/^---|^[a-z]+:/' "$SKILL" | grep -E "(先|然后|最后|首先|接着|调用|invoke|加载)"

# 6.2 description 有没有「不要触发」段落（必须有）
awk '/^description:/,/^---|^[a-z]+:/' "$SKILL" | grep -E "(不要触发|不适用|以下场景不要)"

# 6.3 找祈使式 invoke / 调用 skill（命中即必改：应改为「用户可以让你切到 X」陈述句）
grep -nE '(请|必须|需要|应当).{0,10}(invoke|调用|加载).{0,20}(skill|技能)' "$SKILL" \
  | grep -vE '不要|不能|不可'

# 6.4 检查环式调用防护标签（每个 skill 顶部都应有 VMEDIA-SKILL-REENTRY-GUARD）
grep -n 'VMEDIA-SKILL-REENTRY-GUARD\|SKILL-REENTRY-GUARD' "$SKILL" \
  || echo "  ⚠️  缺 REENTRY-GUARD 标签：建议加上「A↔B 短窗口交替 ≥ 2 次 且 无新用户指令 → 停止跳转」"

# 6.5 铁律区块是否存在 + 条数（业务 skill 应在 5~7 条；元 skill / 引导 skill 可为 0）
awk '/<EXTREMELY-IMPORTANT>/,/<\/EXTREMELY-IMPORTANT>/' "$SKILL" | grep -cE '^### [0-9]+\.'

# 6.6 反向约束（❌ / 🚫 / 禁止）的密度（建议每 50 行至少 1 处）
total=$(wc -l < "$SKILL")
neg=$(grep -cE '❌|🚫|禁止|⛔' "$SKILL")
echo "lines=$total negative_marks=$neg ratio=1/$((total / (neg + 1)))"
```

### Step 7 — 给一段简短 review 报告（2 分钟）

按本 skill 的 [reference/review-report-template.md](./reference/review-report-template.md) 输出，**让作者一眼能 patch**。

---

## 三、Review 时最常见的 17 个反模式（一定要查）

> 以下每条都对应**一个实际发生过的 Agent 翻车 case**，按出现频率倒序排列。

| # | 反模式 | 典型现象 | 正解 |
|---|-------|---------|------|
| 1 | **跨 Shell 调用复用 `$DM` / `$TOKEN`** | Agent 第二条命令报 `command not found: --token` | SKILL 里写明：每条命令都要带 `source ... &&` 前缀 |
| 2 | **占位串当 token** | `--token "<api-token>"` / `--token "$TOKEN"` 在没 source 的命令里 → 401 | token 必须是真实 ~110 字符全串；含 `.` 段；用 `$API_TOKEN` 时**必须**与 `source` 同一条命令 |
| 3 | **猜参数名** | `--task` / `--id` / `--taskid` / `-t` 全都试一遍 | SKILL 里加铁律「全 CLI 任务相关一律 `--task-id`」+ 列出涉及子命令清单 |
| 4 | **stdout 被 `2>/dev/null` 误判为空** | Agent 拿到完整 JSON 却以为没拿到，再多查一次 | SKILL 里点明「业务结果**永远在 stdout**；空 = 命令报错（看 exit code 或 `2>&1`）」 |
| 5 | **轮询自创 for + python json.load** | 解析失败 → "补偿性"再单独查一次 → 翻倍调用 | 给**官方一行 jq 模板** + **官方 60 次 sleep 10 模板**，禁止自创 |
| 6 | **`completed` 后再调 `<resource> download`** | 链接已在 status 里 → 冗余调用 | SKILL 红线："status 已自带链接，禁止再调 download" |
| 7 | **猜 filter 操作符** | 凭印象写 `like` / `contains` / `regex` → 全部 unsupported op | 给 schema + json_schema + remarks，并在 SKILL 里写"先 schema 再传参" |
| 8 | **option 字段直接传中文 / 业务名** | `value:"published"` 而真实是 `value:4` → 命中 0 条但不报错 | SKILL + schema remarks 中明确："option 字段必须先 `field-values`，传内部 value 不传 label" |
| 9 | **路径里写死品牌目录** | `~/.box` / `~/Library/Application Support/Box` / `~/.workbuddy` | 一律改 `<SKILL_DIR>` 占位，由平台告知 |
| 10 | **过期 flag 残留** | `--output json` 在 CLI 已删除后 doc 没改 → cobra `unknown flag` | 用 `<cli> schema --all` 与 doc 做 diff 校对 |
| 11 | **`<EXTREMELY-IMPORTANT>` 滥用** | 把"版本号"也塞进去；agent 真正应遵守的红线被淹没 | 只放跨子命令通用、违反必出错的 5~7 条；其它放正文 |
| 12 | **写完不实跑回归** | 文档里改了，安装目录里没同步；下次 Agent 还是踩老坑 | 每次改 skill 必跑 §Step 4 三件套，并把回归命令写进 README |
| 13 | **description 里写工作流** | "先调用 X，然后 Y，最后 Z…" → Agent 决策权被抢走，反而僵化 | description **只写触发条件**，工作流放铁律 + references |
| 14 | **负样本只写"明显无关"** | 「帮我订咖啡」这种没价值；近似 case 才有用 | 列「pandas 做清洗」「file 查 trace」「Python 直连 MySQL」等近似但不该触发的场景 |
| 15 | **Skill 之间触发词重叠 + 衔接祈使句 → 环式调用** | `dashboard` 文档说"调用 datamind 导出"，`datamind` description 又含「数据看板」字样 → 大模型在没有用户新指令的情况下在两者之间随机选一个，A→B→A→B 反复加载 | 顶部加 `<VMEDIA-SKILL-REENTRY-GUARD>`（A↔B 短窗口交替 ≥ 2 次 **且** 无新用户指令 → 停止跳转）+ 衔接段落改用户主导陈述句 + 触发词去重叠（关键词加修饰词、加「不要触发」段落） |
| 16 | **嵌套子技能依赖主 skill 前置说明** | Agent 直接触发 `datamind-export`，裸跑 `vmedia-dm project list`，再用 `which vmedia-dm` 误判未安装 | 每个 `subskills/**/SKILL.md` 都加“直接加载保护”：说明可能未读主 skill；每条命令必须 `source "<SKILL_DIR>/find_dm.sh" && "$DM" ...`；禁止 `which <cli>` 判安装 |
| 17 | **能力咨询没有使用引导** | 用户问“数据导出怎么用/有什么能力”，Agent 要么直接开始执行，要么只泛泛说“支持导出” | 在 skill 中增加“怎么用/有什么能力”场景：给能力边界 + 3~6 条可复制自然语言提示词；明确这类咨询只输出说明，不跑 CLI、不输出写操作确认卡片 |

---

## 四、好实践速查（datamind/SKILL.md 8 条精华）

> 想看「写得好」长什么样，先读这一节。完整拆解在 [reference/datamind-best-practices.md](./reference/datamind-best-practices.md)。

| # | 好实践 | 一句话 |
|---|-------|-------|
| 1 | **铁律 6 条克制 + 跨子命令通用** | 数量克制（6 条），每条都跨子命令；明确"本节优先级最高" |
| 2 | **🚨 / ❌ / 💡 三态 emoji 区分刚性与柔性** | 视觉锚点让 Agent 一眼区分"必须 / 典型错误 / 建议" |
| 3 | **报错速查表（让 Agent 反向匹配）** | `报错 → 真正原因 → 修法` 三列表，跳过 Agent 的自我怀疑 |
| 4 | **「项目 ID / 频道枚举」预缓存表** | 把高频 `field-values` 调用结果缓存进 SKILL，省一次 RPC |
| 5 | **写操作两轮确认 + 第一轮一次问清** | 减少 ping-pong；明确禁止"先确认意图再问字段"二段式 |
| 6 | **轮询模板三件套：一行版 + 循环版 + 反模式列表** | 默认走哪条、为什么不能走另一条，全说清 |
| 7 | **「场景→文件索引」表（14 行覆盖 80% 用户意图）** | 意图驱动，精确到文件 + 章节锚点 |
| 8 | **高危场景留 SKILL 主文件、其它迁 references** | 按"配错代价"判断保留位置，而非按字数判断 |

四条**不可见的设计哲学**贯穿其中：
1. **规则先于细节**（铁律永远在最顶部）
2. **报错指纹优先**（每条规则附"违反后会出现什么报错"）
3. **缓存优于调用**（高频枚举做表减少 RPC）
4. **正反例配对**（每个易错点都有 ✅ + ❌ + 报错形态）

---

## 五、Review 输出格式

请见 [reference/review-report-template.md](./reference/review-report-template.md)。一份合格的 review 报告应包括：

1. **总评**（一句话：能用 / 有改进空间 / 阻塞上线）
2. **必改项**（带文件:行号 + 问题归类编号 c1~c10 + 修复建议）
3. **建议项**（非阻塞，但 Agent 体验会显著提升）
4. **回归命令**（review 完作者按这段一键跑通验证）

---

## 六、配套子文档

### Checklists（10 类细则）

- [`checklists/c1-trigger.md`](./checklists/c1-trigger.md) — description 与触发词
- [`checklists/c2-cli-contract.md`](./checklists/c2-cli-contract.md) — CLI 调用契约
- [`checklists/c3-token.md`](./checklists/c3-token.md) — Token 处理
- [`checklists/c4-polling.md`](./checklists/c4-polling.md) — 轮询/状态查询模板
- [`checklists/c5-output-contract.md`](./checklists/c5-output-contract.md) — stdout/stderr 契约
- [`checklists/c6-schema-introspection.md`](./checklists/c6-schema-introspection.md) — schema 自省（json_schema / remarks / enum）
- [`checklists/c7-version-and-regression.md`](./checklists/c7-version-and-regression.md) — 版本同步与实跑回归
- [`checklists/c8-strict-flow.md`](./checklists/c8-strict-flow.md) — 强约束 / 固定流程 / 反向约束 / few-shot
- [`checklists/c9-skill-architecture.md`](./checklists/c9-skill-architecture.md) — SKILL 文档架构（精简 + references 拆分）
- [`checklists/c10-no-skill-loop.md`](./checklists/c10-no-skill-loop.md) — Skill 环式调用防护（VMEDIA-SKILL-REENTRY-GUARD 标签 + 触发词去重叠 + 衔接段落用户主导）

### Reference（深度文档）

- [`reference/description-and-negative-cases.md`](./reference/description-and-negative-cases.md) — description 调优 5 原则 + 负样本设计
- [`reference/datamind-best-practices.md`](./reference/datamind-best-practices.md) — datamind/SKILL.md 8 条好实践逐项拆解
- [`reference/anti-patterns-casebook.md`](./reference/anti-patterns-casebook.md) — 反模式案例库（含真实 Agent 失败转录）
- [`reference/review-report-template.md`](./reference/review-report-template.md) — review 报告模板

---

## 七、与其它 vmedia-* skill 的关系

| 邻居 skill | 协作方式 |
|-----------|---------|
| `vmedia-golang-cli-design` | review **CLI 端**实现（stdout 契约 / 退出码 / schema / dry-run）。本 skill review **skill 文档**与 CLI 的契合度。两者配套使用。 |
| `vmedia-golang-code-style` | 涉及 skill 里嵌入 Go 代码片段时的代码规范。 |
| `vmedia-git-commit` | review 完后提交修复的 commit 写法。 |

> **顺序建议**：先用 `vmedia-golang-cli-design` 把 CLI 改稳，再用 `vmedia-skill-review` 检查 skill 文档与 CLI 的契合。**反过来做必返工**——文档迁就一个待重构的 CLI 没价值。
>
> ⚠️ **本 skill 自身也遵守 c10 防护规则**：仅当本 skill 与某个其它 skill 在 ≤ 4 轮 assistant 回合内交替触发 ≥ 2 次 **且** 期间没有新用户指令时，才停止跟随本文档「下一步 / 后续衔接」类指引；用户主导的多轮 review 交互（如"先 review trigger 部分→再 review CLI 部分"）不算环路；用户显式说"切到 X skill"不受此防护限制。
