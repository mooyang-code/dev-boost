# C9 — Skill 文档架构（精简 + 拆分 + 引导技能）

## 标准

skill 不是越长越好——上下文越长，Agent 越容易**找不到关键信息**。一个合格的 skill 文档架构应满足：

1. **SKILL.md 精简**：核心指令 + 场景索引，控制在 **200~300 行**（example-cli 实战 ~600 行偏长，但因为铁律 + 完整工作流模板需要集中展示，可接受；常规 skill 控制在 200 行内）
2. **references/ 拆分**：详细参数 / 操作流程 / 场景案例拆到子文件，Agent 按需读取
3. **场景→文件索引**：SKILL.md 末尾给一张「我想做什么 → 读哪个 reference 文件」的映射表
4. **嵌套子技能可自举**：如果使用 `subskills/**/SKILL.md` 做模块拆分，每个子技能都必须能在未读取主 skill 时独立启动
5. **使用引导**：能力型 skill 要回答“怎么用 / 有什么能力 / 给几个例子”，提供能力边界 + 可复制提示词
6. **引导技能（可选）**：跨多个 skill 的初始化 / 路由说明放专门的"引导 skill"，每次会话开头加载

## 推荐目录结构

```
skills/<skill-name>/
├── SKILL.md                       # 核心指令 + 铁律 + 场景索引（≤300 行）
├── VERSION                        # 单行 vMAJOR.MINOR.PATCH
├── find_<cli>.sh                  # CLI 定位 + token 自加载脚本
├── <cli>-darwin-arm64             # 平台二进制
├── <cli>-darwin-amd64
├── <cli>-linux-amd64
├── <cli>-linux-arm64
└── references/
    ├── welcome.md                 # 平台/工具能力全景
    ├── cli-reference.md           # 完整命令参数（可较长）
    ├── operations-guide.md        # 标准操作流程 + 示例
    ├── <子场景-1>.md              # 高频/特殊场景独立文件
    └── <子场景-2>.md
```

如果确实需要让子模块也带 `SKILL.md`：

```
skills/<skill-name>/
├── SKILL.md
├── find_<cli>.sh
├── <cli>-*
├── references/
└── subskills/
    ├── export/SKILL.md            # 必须包含“直接加载保护”
    ├── clean/SKILL.md             # 必须包含“直接加载保护”
    └── dashboard/SKILL.md         # 必须包含“直接加载保护”
```

> 注意：很多 Agent 平台会索引目录里的所有 `SKILL.md`。`subskills/export/SKILL.md` 可能绕过主 `SKILL.md` 被直接加载，所以子技能不能只写“见 ../../references/core-guardrails.md”，必须内联最小启动规则。

## 检查项

### SKILL.md 层

- [ ] frontmatter `description` **只写触发条件**，不写工作流（详见 [reference/description-and-negative-cases.md](../reference/description-and-negative-cases.md)）
- [ ] `<EXTREMELY-IMPORTANT>` 铁律 5~7 条，跨子命令通用
- [ ] 「执行操作」一节只列**子命令清单 + 对应 reference 文件**，不展开每个子命令的细节
- [ ] 末尾「场景→文件索引」表 ≥ 5 条，覆盖最高频的用户意图
- [ ] 对能力型 skill，包含「怎么用 / 有什么能力」使用引导：说明能力边界、用户需要提供哪些信息、给 3~6 条可复制自然语言提示词
- [ ] 使用引导明确咨询场景只输出说明和示例，不执行 CLI、不创建任务、不进入写操作确认卡片；用户选择或改写成具体请求后才进入执行流程
- [ ] **不出现版本号字符串**（避免与 VERSION 文件 / `<cli> --version` 双写漂移）
- [ ] 整体行数控制：常规 ≤ 300 行；含完整工作流脚本可放宽到 600 行

### references/ 层

- [ ] **每个高频场景**有独立 .md 文件（不要一股脑塞进 operations-guide）
- [ ] 单个 reference 文件 ≤ 1500 行；超长说明该拆
- [ ] 文件命名清晰，能从文件名直接看出适用场景（`dashboard-create-flow.md` 而不是 `notes2.md`）
- [ ] 文件之间**有交叉引用**：`详见 cli-reference.md §export`

### subskills/ 层（如果存在）

- [ ] 每个 `subskills/**/SKILL.md` 文首都有“直接加载保护”：说明本子技能可能未先读取主 `SKILL.md`
- [ ] 每个子技能都内联 CLI 自举模板：`unset SKILL_DIR CLI_BIN && source "<SKILL_DIR>/find_<cli>.sh" && "$CLI_BIN" ...`
- [ ] 子技能明确 `<SKILL_DIR>` 是安装后的 skill 根目录，不是当前 `subskills/<name>/` 目录；必要时说明“从当前子技能目录向上两级”
- [ ] 子技能禁止裸跑 `<cli> ...`，也禁止用 `which <cli>` 判断未安装
- [ ] 子技能可引用公共 `references/`，但不能把“找到 CLI / 配置 token / 命令前缀”等启动前置只放在主 skill 或 reference 里

### 索引层

- [ ] SKILL.md 末尾「场景→文件索引」用 markdown 表格
- [ ] 表格格式：`| 我想做… | 读这里 |`
- [ ] 索引项 ≥ 5 条；每条对应一个用户高频意图

## 反例

### 反例 1 — 一切塞 SKILL.md

```text
SKILL.md  3500 行
references/  空
```

→ Agent 加载 3500 行上下文，关键的 token 配置规则被淹没在第 1800 行。Agent "看不到"重点 → 反复试错。

修复：把每个子命令的详细参数迁到 `references/cli-reference.md`，把每个标准流程迁到 `references/operations-guide.md`，SKILL.md 只留索引和铁律。

### 反例 2 — 只有一个 references/notes.md

```text
SKILL.md         200 行
references/
  └── notes.md   2800 行混合内容
```

→ Agent 不知道该读 notes.md 的哪一段，于是**整文件加载** → context 爆掉。

修复：按场景拆 → `cli-reference.md` / `operations-guide.md` / `dashboard-create.md` / `clean-flow.md` ...

### 反例 3 — 索引表伪指令

```markdown
| 我想做… | 读这里 |
|---------|--------|
| 导出数据 | 参考前面的内容 |
| 清洗数据 | 见 operations-guide |
```

→ "前面的内容"指代不明；"operations-guide" 没给路径也没给章节锚点 → Agent 还要再搜一次。

修复：

```markdown
| 我想做… | 读这里 |
|---------|--------|
| 导出数据（完整流程） | `references/operations-guide.md` §一「数据导出」 |
| 清洗数据（两轮确认 + 文件上传） | `references/operations-guide.md` §零「数据清洗」 |
```

精确到文件 + 章节锚点。

### 反例 4 — 子技能只写业务流程，启动前置全靠主 skill

```text
skills/example-cli/
├── SKILL.md                       # 有 find_cli.sh / token / source 规则
├── find_cli.sh
└── subskills/
    └── export/SKILL.md            # 只写“先 project fields，再 export create”
```

真实结果：Agent 直接触发 `export subskill`，没有读主 `example-cli/SKILL.md`，于是执行 `<cli> project list`，再用 `which <cli>` 误判 CLI 未安装。

修复：每个子技能开头加“直接加载保护”，明确：

- 本子技能可能被直接触发，不保证主 skill 已读
- 每条命令必须 `source "<SKILL_DIR>/find_<cli>.sh" && "$CLI_BIN" ...`
- `<SKILL_DIR>` 是安装后的 skill 根目录；若从子技能目录定位，向上两级
- 禁止裸跑 `<cli>`，禁止用 `which <cli>` 判安装

### 反例 5 — 用户问“怎么用”，skill 只会执行

```text
用户：数据导出有什么能力？怎么用？
Agent：请确认导出意图...
```

→ 用户还在探索能力边界，Agent 却误判成具体写操作，容易过早进入确认卡片或执行流程。

修复：能力型 skill 增加“使用引导”小节：

- 先用 1 段话说明能力边界，例如支持按项目、字段、枚举、关键词、ID 文件筛选并导出
- 给 3~6 条用户可复制的自然语言提示词，覆盖高频业务场景
- 说明用户可以复制后替换条件；涉及本地文件时提供文件路径
- 明确“这类咨询只输出说明和示例，不执行命令；用户选定具体需求后再进入确认/执行流程”

## 引导技能（advanced，可选）

如果一个团队/产品下有多个 skill，可以做一个**引导技能**，专门告诉 Agent "如何使用本团队的技能系统"：

- 引导技能的 SKILL.md 在每个新会话**完整加载**（普通 skill 只加载 frontmatter 的 name + description）
- 引导技能本身**不执行业务**，只做路由：「你是不是想做 X？请去读 moo-xxx skill」
- 适用场景：团队已有 5+ 个 skill，且彼此有清晰边界但用户口语化输入有歧义

> ⚠️ 引导技能**不能**自动 invoke 其它 skill，只能在文档里指引"下一步去读哪个 SKILL.md"。

## 范本

参考 example-cli/SKILL.md（example-cli 仓库）的：

- frontmatter 写法（触发例句 + 负样本明确）
- `<EXTREMELY-IMPORTANT>` 6 条铁律的组织方式
- 末尾「场景→文件索引」表（共 14 行索引）
- 把高危流程（动态看板创建）单独放在 SKILL.md 里强约束、其它放 references/

完整正面教材拆解见 [reference/cli-best-practices.md](../reference/cli-best-practices.md)。
