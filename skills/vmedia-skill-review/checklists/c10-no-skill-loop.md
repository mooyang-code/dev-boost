# C10 — Skill 环式调用防护

## 问题

多个 vmedia-* skill 触发词有重叠时，大模型每一轮**可能随机选中其中一个**，结果在用户做完一件事后被反复触发到不同 skill，形成 A→B→A→B 的环：

```
用户: "生成运营看板"
  → 加载 vmedia-dashboard
  → 文档写"完成后调用 datamind 导出"
  → Agent 加载 vmedia-datamind
  → datamind description 含「数据看板」
  → Agent 又加载 vmedia-dashboard
  → 反复 ...
```

**关键观察**：上面整个过程**用户没有给出任何新指令**，纯粹是 skill 文档之间的"后续衔接"段落在牵引。这才是环路。

---

## 环路 vs 非环路 的判别（重要）

不是所有"同一个 skill 被多次触发"都是环路。准确的边界：

| 现象 | 是否环路 | 说明 |
|------|---------|------|
| 用户连续多轮跟同一个 skill 交互（"先列项目"→看完→"再导出 X"→看完→"再做对账"） | ❌ 不是 | 用户每轮都给了新指令，是用户主导的多轮业务流 |
| 一个会话同时用 cli-server-build + code-style + git-commit | ❌ 不是 | 不同 skill 互补使用，没有交替反复 |
| 用户**显式**说"切到 X skill" 后 X 被加载 | ❌ 不是 | 用户主动切换 |
| 在 ≤ 4 轮 assistant 回合内 A↔B 交替触发 ≥ 2 次 **且** 期间没有新用户指令 | ✅ 是 | 只有 skill 文档相互牵引，无用户驱动 → 真环路 |

环路的两个**必要条件**（缺一不成环）：

1. **窗口连续性**：A↔B 在短窗口（≤ 4 轮 assistant）内交替**≥ 2 次**（A→B→A→B 形态）
2. **无新用户指令注入**：这些来回触发期间，用户没有给出新的明确意图

防护要同时检测这两个条件，缺一就放行。

---

## 防护方案

### 方案 1：`<VMEDIA-SKILL-REENTRY-GUARD>` 重入防护标签

每个有可能与邻居 skill 形成 A↔B 环路的 skill，在 SKILL.md 顶部加一段防护标签：

```markdown
<VMEDIA-SKILL-REENTRY-GUARD>
仅当出现以下**两个条件同时成立**时，才判定为环式调用：

1. **窗口连续性**：在最近 ≤ 4 轮 assistant 回合内，本 skill 与同一个**其它 skill** 已经交替触发 ≥ 2 次（A→B→A→B 形态），且
2. **无新用户指令注入**：这些来回触发期间，用户没有给出新的明确意图——只是 skill 文档之间的"后续衔接"段落在互相牵引

满足以上两条 → **立即停止跟随本文档任何「下一步 skill / 后续衔接」类指引**，只执行用户最近一次明确请求；如果用户没有明确请求，直接汇报当前业务结果并等待用户决定。

**不**适用本防护的正常场景（不要误判为环路）：

- 用户跟本 skill 做多轮交互（例如 "先 X" → 看完 → "再 Y"）——用户主导的多轮业务流，本 skill 即使被触发多次也不是环路
- 用户**显式**说"切到 X skill / 用 X skill 做"——主动切换永远放行
- 一个会话同时使用多个不同 skill（例如 build + code-style + git-commit）——互补使用，没有交替反复
</VMEDIA-SKILL-REENTRY-GUARD>
```

**关键点**：

- 触发条件**必须同时满足**两条（窗口连续 + 无新用户指令），缺一不算环
- 标签**只防环**，不限制业务功能
- **用户显式指令**永远绕过防护——用户主动想跳就让跳
- 标签命名 `<VMEDIA-SKILL-REENTRY-GUARD>` 是 vmedia 团队自定义命名空间，不与公共 skill 冲突

### 方案 2：触发词去重叠（最根本的防护）

环路第一必要条件是触发词重叠。降低重叠就能从源头减少环路概率。

`description` 里：

- 业务领域相邻的 skill 之间用「**不要触发**」段落点名澄清
- 关键词加**修饰词**让范围收窄，例如把"数据看板"改成"看板模板设计/前端样式"或"`vmedia-dm dashboard` 子命令的 CLI 调用"
- 同义词不要同时出现在多个 skill 的 description 里

具体写法见 [reference/description-and-negative-cases.md](../reference/description-and-negative-cases.md)。

### 方案 3：跨 skill 衔接段落「用户主导」改写

skill 末尾的"后续衔接"段落用**陈述句 + 用户主导**写法，不用祈使句——这就直接消除了环路的第二必要条件（无用户指令的自动牵引）：

| 写法 | 大模型反应 |
|------|----------|
| ❌ "请 invoke vmedia-dashboard skill 上传数据" | 直接加载 → 触发回弹 |
| ❌ "完成导出后，调用 vmedia-dashboard 上传到看板" | 直接加载 → 触发回弹 |
| ✅ "如果用户接下来要把数据传到看板，**等用户明确指令**再切换到 vmedia-dashboard" | 等用户决定，环路概率大幅降低 |
| ✅ 直接给完整 CLI 命令（不依赖跳 skill） | 完全不跨 skill，零环路 |

---

## 检查项

### SKILL.md 顶部

- [ ] 含 `<VMEDIA-SKILL-REENTRY-GUARD>`（或团队自定义等价标签）
- [ ] 触发条件写明**两个必要条件同时成立**（窗口交替 ≥ 2 次 **且** 无新用户指令），不只判其一
- [ ] 列举了"**不**适用本防护的正常场景"——避免误伤用户主导的多轮交互
- [ ] 标签内明确"用户显式指令不受限"
- [ ] 标签放在 `<EXTREMELY-IMPORTANT>` **之前**（防护是元规则，先于业务规则）

### 触发词

- [ ] 跟同团队其它 skill 的核心关键词**没有强重叠**
- [ ] 强重叠不可避免时（业务相邻），description 含「不要触发」段落点名其它 skill 名

### 跨 skill 衔接段落

- [ ] 不出现 `请 invoke` / `请调用` / `必须加载` 这类**祈使句**
- [ ] 改用「**等用户明确指令再切换**」/「用户可以让你切换到 X」陈述句
- [ ] 衔接前**先汇报当前业务结果**（如 `download_url`），再让用户决定是否跳转

---

## 正反例

### 正例 1：顶部防护标签

```markdown
<VMEDIA-SKILL-REENTRY-GUARD>
仅当**同时**满足以下两点时判定为环式调用：

1. 在最近 ≤ 4 轮 assistant 回合内，本 skill 与同一个其它 skill 交替触发 ≥ 2 次
2. 这些来回触发期间，用户没有给出新的明确意图

满足两点 → 停止跟随「下一步 skill」类指引，只执行用户最近一次明确请求。

**不**算环路：用户主导的多轮交互；用户显式切换 skill；多个不同 skill 互补使用。
</VMEDIA-SKILL-REENTRY-GUARD>
```

### 正例 2：衔接段落用户主导

```markdown
## 数据导出完成后

任务 completed 后，先把以下信息汇报给用户：

| 项 | 值 |
|----|-----|
| task_id | EXP-xxx |
| 行数 | 12,345 |
| 下载链接 | https://... |

**等用户明确说**接下来要做什么再继续，常见选择：

| 用户意图 | 切换到 |
|---------|-------|
| "上传到看板" | vmedia-dashboard |
| "做对账" | vmedia-compare |
```

### 反例 1：祈使式互调

```markdown
❌ 数据导出完成后，请 invoke vmedia-dashboard skill 上传数据。
```

→ Agent 直接加载 → 命中触发词回弹。

### 反例 2：触发词强重叠且无负样本

```yaml
# vmedia-datamind/SKILL.md
description: 数据导出、数据看板、数据清洗

# vmedia-dashboard/SKILL.md
description: 数据看板创建、看板模板设计
```

→ 用户说"做个看板"，没新指令的情况下大模型每轮可能随机选其中一个，频繁来回切换。

修复：

```yaml
# vmedia-datamind
description: |
  ... 含"看板"（仅指 vmedia-dm dashboard 子命令的 CLI 调用）...
  不要触发：「看板模板设计 / 前端样式 / 看板交互」 → 应触发 vmedia-dashboard。

# vmedia-dashboard
description: |
  ... 看板模板设计、前端样式、看板交互 ...
  不要触发：「调用 vmedia-dm dashboard 子命令」 → 应触发 vmedia-datamind。
```

### 反例 3：误把用户主导的多轮交互判成环路

```
用户: "帮我列下所有项目"
Agent: [加载 datamind, 执行 project list, 输出列表]
用户: "好，再帮我导出 saas_xxx 项目的 type=2 的数据"
Agent: [加载 datamind, 执行 export create, 输出 task_id]
用户: "完成后下载链接发我"
Agent: [datamind 已加载, 查询 status, 输出链接]
```

→ 这里 datamind 被"加载"3 次，但**每次用户都给了新指令**，是正常多轮业务流，**不应**触发防护。错误的防护会让 Agent 半路停下来，反而比环路更糟。

---

## 一行命令排查

```bash
SKILLS_DIR="<dev-boost/skills 目录>"

# 1. 列出缺少防护标签的 skill
for s in "$SKILLS_DIR"/*/SKILL.md; do
  grep -q 'VMEDIA-SKILL-REENTRY-GUARD\|SKILL-REENTRY-GUARD' "$s" \
    || echo "⚠️  缺防护标签: $s"
done

# 2. 找出仍写着祈使式 invoke 的位置
grep -rEn '(请|必须|需要|应当).{0,10}(invoke|调用|加载).{0,20}(skill|技能)' "$SKILLS_DIR" \
  | grep -vE '不要|不能|不可'

# 3. description 关键词强重叠扫描（任意两个 skill 共享 ≥3 个核心业务关键词且无「不要触发」段落 → 加负样本）
for s in "$SKILLS_DIR"/*/SKILL.md; do
  echo "=== $s ==="
  awk '/^description:/,/^---|^[a-z]+:/' "$s" \
    | grep -oE '[\u4e00-\u9fa5]{2,}' | sort -u
done | less

# 4. 标签内是否同时含「窗口」和「用户指令」两条判定（任缺其一就是误判风险）
for s in "$SKILLS_DIR"/*/SKILL.md; do
  awk '/<VMEDIA-SKILL-REENTRY-GUARD>/,/<\/VMEDIA-SKILL-REENTRY-GUARD>/' "$s" \
    | grep -qE '回合|窗口|交替|A.*B' \
    && awk '/<VMEDIA-SKILL-REENTRY-GUARD>/,/<\/VMEDIA-SKILL-REENTRY-GUARD>/' "$s" \
    | grep -qE '用户.*指令|新意图|新指令' \
    || echo "⚠️  防护条件不全: $s"
done
```

---

## 总结

| 防护层 | 作用 | 落地 |
|-------|------|------|
| 双条件判定 | 必须 A↔B 短窗口交替 **且** 无新用户指令，才算环路 | `<VMEDIA-SKILL-REENTRY-GUARD>` 顶部两条 |
| 排除清单 | 用户主导的多轮交互 / 显式切换 / 不同 skill 互补使用 → 不算环路 | 同上「不适用场景」段 |
| 触发词去重叠 | 减少环路第一必要条件（A↔B 才能形成） | description「不要触发」段落 |
| 衔接段落用户主导 | 直接消除环路第二必要条件（让自动牵引变成用户决策） | "下一步" 用陈述句 + 等用户指令 |

> **核心理念**：环路的精确指纹是「**短窗口内 A↔B 交替**」**且**「**期间没有用户驱动**」——这两条同时成立，才说明 skill 文档相互牵引而用户没参与。把这两条作为唯一判定，就能既挡住真环路、又不误伤用户主导的多轮业务流。
