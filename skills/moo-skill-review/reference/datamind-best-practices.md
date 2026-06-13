# 正面教材：datamind/SKILL.md 好实践拆解

> 本文是"为什么 datamind/SKILL.md 是好范本"的逐项拆解，review 别的 skill 时可以拿来对照。
> 引用路径：`<datamind 仓库>/skills/datamind/SKILL.md`。

datamind/SKILL.md 是经过 6 轮以上真实 Agent 失败迭代打磨出来的，下面 8 个实践都对应**实际踩过的坑 + 实际生效的修复**。

---

## 实践 1 — `<EXTREMELY-IMPORTANT>` 铁律区块（6 条）

### 做法

skill 顶部用 `<EXTREMELY-IMPORTANT>` 标签包裹 6 条**跨子命令通用**的强约束：

1. 定位 CLI 二进制：必须在 SKILL.md 真实所在目录找
2. 高危写操作：两轮确认 + 强制红线
3. 任务状态查询的参数名是 `--task-id`，禁止猜
4. `export status` 已自带下载链接，禁止再调 download；轮询用官方模板
5. 用户说"按文件里的 ID"：必须用 `--id-file`，禁止展开文件内容
6. `upload` 默认通道是公共通道，必须先确认 `--channel`

每条都注明「**违反任意一条都会导致 Agent 给用户错误指引或被 CLI 直接拒绝**」。

### 为什么是好实践

- **数量克制**：只 6 条，每条都跨子命令通用 → Agent 一眼能记住
- **明确优先级**：开篇写"本节内容优先级高于本 skill 其它任何章节" → Agent 不会被后面的细则带偏
- **每条都有报错指纹**：违反后会出现什么报错形态明确写出 → Agent 看到报错能瞬间反向定位违反了哪条

### 可借鉴的写法

```markdown
<EXTREMELY-IMPORTANT>
以下是 <skill 名> 的**铁律**，跨子命令通用，违反任意一条都会导致
Agent 给用户错误指引或被 CLI 直接拒绝执行。
**任何 <skill 名> 命令调用前必须先满足这些前置条件**，
本节内容优先级高于本 skill 其它任何章节。

### 1. <第一条标题>
<内容>

### 2. <第二条标题>
<内容>

...
</EXTREMELY-IMPORTANT>
```

---

## 实践 2 — 把 5 条防抄红线和 ✅/❌/💡 三态对齐

datamind/SKILL.md 的 token 规则段落（铁律 §1）写法：

```markdown
🚨 三条防抄红线（违反必 401，无一例外）：

1. **禁止把"含 ... / xxxxxx / … 的样例 token"原样抄进命令**
2. **禁止照抄 find_dm.sh 自动加载提示里出现的"长度 51"等数字**
3. **禁止跨 Shell 调用依赖 $API_TOKEN**

❌ **典型错误**：以为上一条 source 过了，第二条直接写 $DM ...
  报错形态固定：command not found: --token / --gateway / 或 --<任何首个 flag>
  ——只要看到这个 pattern，100% 是漏掉了 source

💡 写法成本极低：把 unset SKILL_DIR DM && source ... && "$DM" ...
   当成 datamind 命令的"必备前缀"
```

### 为什么是好实践

- 🚨 标记**绝对红线**（违反必出错）
- ❌ 标记**典型错误**（带具体报错形态指纹）
- 💡 标记**柔性建议**（"成本极低，每次都加上"）

三种 emoji 形成视觉锚点，Agent 扫一眼就知道这一段哪些是必须、哪些是推荐。

---

## 实践 3 — 报错速查表（让 Agent 反向匹配）

datamind/SKILL.md「找到 CLI 二进制 → 报错速查」一节给了一张 7 行表：

```markdown
| 报错 | 真正原因 | 修法 |
|------|---------|------|
| ❌ 找不到二进制: <某路径>/moo-dm-... | 把不相关目录当 SKILL_DIR 硬编码 | 用平台真实路径重新 source |
| command not found: --help（紧跟 source 之后） | 把 source ... && $DM --help 写成同一行 | 用 && 串联整段 |
| command not found: --token / --gateway | 本次 Shell 调用没 source，$DM 是空字符串 | 把 source ... 当必备前缀，每条都加 |
| 401 unauthorized / 403 forbidden | 按概率排：① 没 source ② source 失败仍引 $TOKEN ③ 占位串 ④ 真过期 | 见对应修法 |
| ...
```

### 为什么是好实践

- Agent 拿到的报错信息**指纹明确**——表格里能精准查到
- 每行给「**真正原因**」（不是表面原因），帮 Agent 跳过自我怀疑
- 修法**可执行**——直接给步骤，不是空话

review 别的 skill 时，凡是有 CLI 调用的 skill 都应该有类似一张报错速查表。

---

## 实践 4 — 给"项目 ID 备忘"和"频道枚举备忘"省调用

datamind/SKILL.md「项目与字段」一节里有两张速查表：

1. **常用 `project_id` 备忘**（5 个最高频项目）
2. **常用频道（type）枚举备忘**（37 行 type↔频道名映射）

并且明确：

> 这是把 `project field-values --field type` 的结果**缓存**到 SKILL 里，避免每次都去调一次。
> 不在表里的小众/新增频道仍走标准 option 流程，不要猜。

### 为什么是好实践

- **真实降本**：原本每次导出都要先 `project field-values` 拿枚举值——这一步现在被表替代
- **明确"缓存"语义**：告诉 Agent "这是缓存，不是规则改了"，所以查不到时仍走标准流程
- **不破坏一致性**：表里的写法（数字 value）与 `field-values` 真实输出**完全一致**，Agent 学到的"option 字段必须用真实 value"规则不被破坏

### 可借鉴的写法

任何「**高频枚举值** + **每次都要调一次接口拿**」的场景都可以做这种缓存表。但必须满足：

- 表里的值与接口真实返回**保持一致**
- 表外的情况**回退到原流程**（要写明）
- 表自身**有维护周期**（建议加注释 `更新于 2026-04`）

---

## 实践 5 — 高危场景的「两轮确认」模板

datamind/SKILL.md 对所有写操作（`export create` / `clean create` / `dashboard create` / `cronjob create` / `upload`）强制两轮确认：

1. **第一轮（自然语言层）**：用中文复述理解结果，等用户回复"是/确认/继续"
2. **第二轮（系统参数层）**：展示翻译后的真实参数（project_id、filter JSON 等），再次等待确认

并且**第一轮必须"一次问清"**——如果用户原话里没给出 `--fields` / `--format` / `--translate-values`，Agent **必须在第一轮的同一条消息**里把这些缺失项一并列出来让用户补，不允许"先确认意图再问字段"的二段式。

### 为什么是好实践

- **防"我以为你说的是 A，你以为我理解了 B"**的最后一道防线
- **第一轮一次问清**减少 ping-pong → 用户体验显著提升
- **缺任意一轮 → 禁止执行**写得很硬，没有解释空间

### 可借鉴的写法

```markdown
### <写操作子命令>

**两轮确认原则**：
1. **第一轮（自然语言层）**：用中文展示理解到的<操作>意图，等待用户明确回复"是"/"确认"/"继续"
2. **第二轮（系统参数层）**：展示翻译后的真实参数（<参数列表>），再次等待确认后才执行

> 💡 **第一轮要"一次问清"**：如果用户原话没给出 <关键参数 1> / <关键参数 2>，
>    Agent 必须在第一轮同一条消息里一并列出来让用户补；不允许二段式。

**两轮确认期间的禁止行为：**
- ❌ 不得在用户未回复前自动进入下一步
- ❌ 不得将"好的"、"明白"、"知道了"视为确认（必须明确"是"/"确认"/"继续"）
- ❌ 不得跳过第一轮直接展示第二轮参数
- ❌ 不得在第二轮确认前执行命令
```

---

## 实践 6 — 官方轮询模板 + 反模式列表

datamind/SKILL.md 铁律 §4 给了「**一行 jq 拿状态 + 下载链接**」+「**循环模板**」+「**4 条反模式**」三件套：

```bash
# ✅ 一行版（首选）
"$DM" ... export status --task-id <id> \
  | tee /tmp/export_status.json \
  | jq -r '"status=\(.status) ... url=\((.steps[]|...).download_url)"'

# ✅ 循环版（最多 10 分钟）
for _ in $(seq 1 60); do
  resp=$("$DM" ... export status --task-id <id>)
  st=$(printf '%s' "$resp" | jq -r '.status')
  case "$st" in
    completed|failed) ... ; break ;;
  esac
  sleep 10
done

# ⛔ 禁止的反模式
- 🚫 resp=$(... 2>/dev/null) 拿到空字符串就断言"stdout 没东西"
- 🚫 同一个 task_id 在 30 秒内连续查超过一次
- 🚫 任务已 completed 还去调 export download
- 🚫 用 python3 -c json.load 替代 jq
```

### 为什么是好实践

- **"首选" + "次选"两段模板** → Agent 知道默认走哪个
- **明确给出反模式的报错链** → 一旦反模式出现，Agent 能瞬间认出
- **1 行 jq 模板带 `tee`** → 状态落盘，避免"再查一次确认"的冗余调用

review 任何含「创建任务 → 等结果」的 skill 都应该有这一组 3 件套。

---

## 实践 7 — 「场景→文件索引」表

datamind/SKILL.md 末尾有一张 14 行索引表：

```markdown
| 我想做… | 读这里 |
|---------|--------|
| 了解平台能力全貌 | references/welcome.md |
| 导出数据（完整流程 + 跨维度 + 示例） | references/operations-guide.md §一「数据导出」 |
| 清洗数据（两轮确认 + 文件上传 + 示例） | references/operations-guide.md §零「数据清洗」 |
| 数据巡检（规则 CRUD / dryrun / 告警排障） | references/cli-reference.md §inspect + references/operations-guide.md §八 |
| 任意命令的完整参数 | references/cli-reference.md |
| ...
```

### 为什么是好实践

- **意图驱动** → "我想做什么" 而不是 "查阅 cli-reference"
- **精确到文件 + 章节锚点** → Agent 不用再二次搜索
- **覆盖最高频意图** → 14 条覆盖 80% 用户场景

### 可借鉴的写法

```markdown
**需要详细操作说明，按场景查阅以下文件：**

| 我想做… | 读这里 |
|---------|--------|
| <场景 1> | `references/<file>.md` §<章节> |
| <场景 2> | `references/<file>.md` §<章节> |
| ...
```

---

## 实践 8 — 把"动态看板创建"放在 SKILL.md 里强约束（其它放 references）

datamind/SKILL.md 把绝大部分子命令的细节都迁到 `references/`，但**唯独**「动态看板创建」（`dashboard create --render-mode dynamic`）放在 SKILL.md 主文件里：

- 第一步：收集必填信息（12 项 checklist）
- 第二步：校验规则（7 项校验项）
- 第三步：展示完整 meta.json 供用户确认
- 第四步：执行创建并验证

### 为什么是好实践

- 这个流程**强制配置规则极多**（图片宽高比、tag 必须有 options、字段名映射等），且**配错 → 看板不可用**
- 放 references 容易被 Agent 跳过；放 SKILL.md 主文件确保**每次创建动态看板都按这套流程走**
- **示范一种取舍原则**：高危 / 高频配错 / 配错后果严重的场景 → 留在 SKILL.md；其它细节 → 迁 references

### 可借鉴的判断

把场景留在 SKILL.md 还是迁 references，按**配错代价**决定：

| 配错代价 | 放哪 |
|---------|------|
| 配错 = 命令报错（一目了然） | references |
| 配错 = 数据写错（可追溯可回滚） | references + SKILL 加红线 |
| 配错 = 用户拿到不可用产物（无报错但失败） | SKILL 主文件强约束 |
| 配错 = 数据泄露/不可逆破坏 | SKILL 主文件 + 铁律 |

---

## 总结：datamind/SKILL.md 的「不可见」最佳实践

最后总结 4 条**不在文档表面**但贯穿整份 datamind/SKILL.md 的设计哲学：

1. **规则先于细节** → 铁律 6 条永远在最顶部，Agent 加载时第一眼看到
2. **报错指纹优先** → 每条规则都附"违反后会出现什么报错"，让 Agent 反向匹配
3. **缓存优于调用** → 高频枚举（频道 type / 项目 ID）做成表减少 RPC 往返
4. **正反例配对** → 每个易错点都有 ✅ 正例 + ❌ 反例 + 报错形态，三件套齐全

review 时把别的 skill 拿来对照这 4 条，能 80% 准确判断"这份 skill 是不是能在生产 Agent 里跑稳"。
