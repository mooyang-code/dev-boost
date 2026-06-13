# C8 — 强约束 / 固定流程 / 反向约束

## 标准

「让 Agent 跑得稳」的核心不是给它**更多**自由度，而是把可固化的部分**固化掉**——再用「不能做什么」把发散空间封死。一个合格的 skill 同时具备：

1. **铁律区块**：跨子命令通用、违反必出错的前置约束
2. **可粘贴的固定流程**：高频场景一步一步该怎么走，连命令模板都给好
3. **反向约束**：明确"禁止做什么"——能比正向描述更精准缩小发散面
4. **few-shot 示例**：正例 + 反例配对，让 Agent 形成"看一眼就会"的肌肉记忆
5. **刚性 vs 柔性区分**：哪些是必须遵守的红线、哪些是允许灵活的部分

## 原则一：铁律区块（`<EXTREMELY-IMPORTANT>`）

### 规范用法

skill 顶部用 `<EXTREMELY-IMPORTANT>` 标签 + 大写 / 醒目格式包裹**跨子命令通用**的强约束：

```markdown
<EXTREMELY-IMPORTANT>

以下是 <skill 名> 的**铁律**，跨子命令通用，违反任意一条都会导致 Agent 给用户错误指引或被 CLI 直接拒绝。
**任何 <skill 名> 命令调用前必须先满足这些前置条件**，本节内容优先级高于本 skill 其它任何章节。

### 1. <第一条铁律标题>
<具体内容 + ✅ 正例 + ❌ 反例 + 报错形态指纹>

### 2. <第二条铁律标题>
...

</EXTREMELY-IMPORTANT>
```

### 检查项

- [ ] 标签在 SKILL.md 顶部，且与 `frontmatter` 之间不夹无关章节
- [ ] 每条铁律都满足「跨子命令通用 + 违反必出错」两个条件——只影响一个子命令的细枝末节**不该**进铁律
- [ ] 总条数控制在 **5~7 条**（datamind 实战是 6 条），多于这个数说明你在塞**子命令规则**而非**通用红线**
- [ ] 每条铁律自带「报错指纹」：`命令: xxx` / `报错: yyy` → `修法: zzz`，让 Agent 一眼对号入座
- [ ] 不写版本号 / build time / 其它易漂移信息（这类信息要么进 VERSION 文件 + `<cli> --version`，要么进具体子命令章节）
- [ ] **铁律区块的优先级**在 SKILL.md 里要明确写出（"本节优先级高于本 skill 其它任何章节"）

### 反例

```markdown
❌ <EXTREMELY-IMPORTANT>
本 skill 当前版本 v1.2.3，构建时间 2026-04-25，git commit abc123。
请使用最新版。
</EXTREMELY-IMPORTANT>

→ 错。版本不属于 Agent 行为约束，应放 `<cli> --version` 输出 + 文档「快速验证」一节。
```

```markdown
❌ <EXTREMELY-IMPORTANT>
1. export create 时 --filter 必须用 JSON
2. clean create 的输入文件必须先 upload
3. dashboard create 必须先 dryrun
4. compare run 的两侧字段类型必须一致
5. inspect run 的规则必须先 activate
... <已经 15 条了>
</EXTREMELY-IMPORTANT>

→ 错。这些都是单子命令规则，应进各子命令对应章节；铁律只放跨命令通用约束（如 token、source、参数命名规范、状态查询统一参数 等）。
```

## 原则二：固定流程（让 Agent 不再"发挥"）

### 标准

高频/高危场景必须在 SKILL（或 references）里写清楚 **N 步标准流程**，每一步都给：

- 一句话说明这步要干什么
- 完整可粘贴的命令模板
- 这步成功 / 失败的判断标准
- 失败后跳到哪一步

datamind 的「数据导出」标准 5 步：

```
1. project list                  → 拿到候选 project_id（已有则跳过）
2. project fields --project X    → 拿字段清单与 field_type
3. project field-values          → 仅对 field_type=option 的字段查枚举
4. schema export create          → 拿 --filter 的 json_schema + remarks
5. export estimate               → 验证条数（不要用 preview 验 filter）
6. 用户确认 → export create      → 创建任务
7. export status --task-id       → 单次或循环查状态，自带 download_url
```

### 检查项

- [ ] **每个高频/高危场景**在 references/ 下有专门的 step-by-step 章节
- [ ] 每步都给**可粘贴命令模板**，不是"调用 xxx 命令"这种伪指令
- [ ] 步骤之间的**判断条件**清晰（`status==completed → 下一步`，`status==failed → 看 error 字段重启`）
- [ ] 流程图 / 决策树（可选但推荐）把"什么情况下走哪个分支"画清楚
- [ ] **能用脚本固化的**就别让 LLM 重新分析（参考材料：拆 Step 脚本）；流程里如有"先做 A 再做 B 再做 C"的死板顺序，直接给一个 `step1.sh / step2.sh / step3.sh` 模板组

### 流程脚本化的取舍

| 对比项 | 单一大脚本 | 拆分 Step 脚本 |
|-------|-----------|---------------|
| Agent 感知每步结果 | ❌ | ✅ |
| 失败精确定位 | ❌ | ✅ |
| 符合"Agent 是决策者，脚本是工具" | ❌ | ✅ |
| 可并发优化 | 难 | ✅ |

→ 多步流程**优先拆分 Step 脚本**，每步执行完把关键产物（`task_id`、`csv 路径`、`download_url`）写进 stdout，让 Agent 拿去做下一步决策。

## 原则三：反向约束（明确"禁止做什么"）

### 为什么需要

正向描述「应该做 A」常常不够——Agent 一遇到不确定就会"凭经验"或"图省事"自创路径。反向约束等于在地图上把所有死路标红，强制 Agent 走主路。

### 检查项

- [ ] 每条铁律 / 每个流程步骤都有对应的 ❌ 反例段落
- [ ] **反向约束至少覆盖**：
  - 不要凭经验猜参数名（必须先 `schema` / `--help`）
  - 不要凭直觉选 op（必须先看 `json_schema.enum`）
  - 不要图省事跳确认轮次（必须两轮）
  - 不要自创轮询脚本（必须用官方模板）
  - 不要自创打印格式（必须 `jq`）
  - 不要在新 Shell 里假设上一条命令的环境变量还在
- [ ] 用「报错形态」做反向约束的反向锚点：写明"看到 `xxx` 报错 100% 是 yyy 原因"——让 Agent 不再去猜其它原因

### datamind 实战的反向约束样板

```markdown
🚨 三条防抄红线（违反必 401，无一例外）：

1. 禁止把"含 ... / xxxxxx / … 的样例 token"原样抄进命令
2. 禁止照抄 find_dm.sh 自动加载提示里出现的"长度 51"等数字
3. 禁止跨 Shell 调用依赖 $API_TOKEN
```

每条都明确「禁止 + 后果（必 401）」，Agent 看一遍就不会再踩。

## 原则四：few-shot（正例 + 反例配对）

### 标准

任何复杂参数 / 易混淆步骤都配一对 **✅ 正例 + ❌ 反例**，反例后面跟「这样写会发生什么」：

```bash
# ✅ 正例：source 与 "$DM" 串在同一条命令里
unset SKILL_DIR DM && source "<SKILL_DIR>/find_dm.sh" \
  && "$DM" --token "$API_TOKEN" --gateway <url> project list

# ❌ 错例 1：上一条已经 source 过了，下一条直接 $DM ...
$DM --token "$API_TOKEN" --gateway ... project fields ...
# → zsh:1: command not found: --token   (新进程里 $DM 为空)

# ❌ 错例 2：没 source 就引用 $API_TOKEN
"$DM" --token "$API_TOKEN" --gateway ... project list
# → 401 unauthorized   (沙箱里 $API_TOKEN 是空)

# ❌ 错例 3：把含 ... 的占位串当 token
... --token "<api-token>..." ...
# → 401 unauthorized   (CLI 收到非法 token)
```

### 检查项

- [ ] 高频参数 / 易混淆 flag 都有正反例对照
- [ ] 反例后面**必须**跟实际报错形态（`zsh:1: command not found: --token`），不是"这是错的"这种空洞说法
- [ ] 反例覆盖**已经发生过的真实 case**（参考 [reference/anti-patterns-casebook.md](../reference/anti-patterns-casebook.md)），而不是凭空想象的反例

## 原则五：刚性 vs 柔性区分

### 标准

skill 文档里的「规则」要分两类，**用排版明确区分**：

| 类别 | 排版标记 | 例子 |
|------|---------|------|
| 刚性（必须遵守） | ⛔ / 🚫 / 🚨 / "禁止" / "必须" / "硬前置" | "禁止把含 `...` 的占位串当 token" |
| 柔性（推荐 / 可灵活） | 💡 / "推荐" / "建议" / "首选" | "推荐用 jq 不用 python" |

### 反例

把「推荐」写成「必须」会让 Agent 在合理变通时反复纠结；把「必须」写成「推荐」会让 Agent 跳过关键约束。两边都会引起线上问题。

### 检查项

- [ ] SKILL.md 里所有"规则"都明确标注是刚性还是柔性
- [ ] 刚性规则集中在 `<EXTREMELY-IMPORTANT>` 区块；柔性建议分散在各子命令章节
- [ ] 不出现「应该 / 最好 / 一般来说」这种含糊措辞——要么硬要求，要么明确"可灵活"

## 原则六：工具链衔接（可选但推荐）

skill.md 里可以**指定**当前技能调用之后下一步该用哪个 skill，形成工具链：

```markdown
## 后续衔接

完成数据导出后，常见的下一步：

- 数据上传到看板：参见 `moo-dashboard` skill
- 数据对账：参见 `moo-compare` skill
- 提交修复 PR：参见 `moo-git-commit` skill
```

⚠️ **避免环式调用**：衔接段落用「用户主导」陈述句（"用户可以让你切到 X"），不写「请 invoke X」这类祈使句；skill 顶部加 `<MOO-SKILL-REENTRY-GUARD>`（A↔B 短窗口交替 ≥ 2 次 **且** 无新用户指令 → 停止跳转；用户主导的多轮交互不算环路），关键词与邻居 skill 重叠时加「不要触发」段落。详见 [c10-no-skill-loop.md](./c10-no-skill-loop.md)。
