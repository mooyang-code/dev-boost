# C11 — moo-cli 插件作者专项检查

## 标准

本条专供"把 skill 作为 moo-cli 插件发布"的作者使用。普通 skill 走 c1–c10 即可；**一旦要发布为插件**，还要额外满足本条。

协议权威定义在 `moo-cli/docs/release-pkg-spec.md`，本检查清单为它的 **review 对应物**：开发者在交付前自查、reviewer 在 review 时核对。

## 何时适用

- 作者打算把 skill 打进 moo-cli 插件包发布（`moo-admin release-pkg`）
- skill 需要附带 CLI 二进制（不是纯文档 skill）
- 发布后会被 moo-cli 路由 / 自动安装到终端用户

不适用：纯文档/规范/review skill（如 `moo-skill-review` 本身）、团队内部手工分发的 skill。

---

## 检查项

### 11.1 SKILL.md frontmatter 完整性

- [ ] **`name`**：必填，且必须与二进制命名 `<name>-<os>-<arch>` 的 `<name>` 段完全一致（一个字符都不能差）
- [ ] **`description`**：必填，遵循 c1（触发词）+ reference/description-and-negative-cases
- [ ] **`keywords`**（推荐）：推荐手动维护，5-15 个业务高区分度词
  - 不写也能发，admin 流程会用 LLM 从正文抽一次（**但每次发布抽取结果可能略有差异**）
  - 写了就是"开发者背书"的稳定触发词，admin 不会覆盖

```yaml
---
name: example-cli                           # ← 必须 = 二进制文件名前缀
description: "媒资数据治理... 当用户问 export/清洗/巡检/对账/看板/cron/UDF 时触发..."
keywords:                                # 推荐手写
  - 数据治理
  - export
  - 清洗
  - 巡检
  - 对账
---
```

### 11.2 发布包结构（release pkg）

- [ ] **二进制在发布包根目录**，不放子目录
- [ ] **二进制命名严格** `<name>-<os>-<arch>`，分隔符用 `-`（不是 `_`）
  - ✅ `example-cli-darwin-arm64`
  - ❌ `example-cli_darwin_arm64` / `bin/example-cli-darwin-arm64` / `example-cli-v1.0.0-darwin-arm64`
- [ ] **4 平台齐全**（推荐）：`darwin-arm64` / `darwin-amd64` / `linux-amd64` / `linux-arm64`
- [ ] **二进制有执行位**（0o111），大小 ≤ 50MB
- [ ] **发布包内不含 `plugin.yaml`**——由 admin 流程自动生成；若包里带了会被 preflight 拒绝

### 11.3 禁止文件扫描（preflight 会拦）

发布包内不得出现：

- [ ] **敏感文件**：`*.key`、`*.env`、`*.secret`、`*.pem`、`*.token`
- [ ] **VCS 元数据**：`.git/`、`.svn/`
- [ ] **OS 元数据**：`.DS_Store`、`__MACOSX/`、`Thumbs.db`
- [ ] **plugin.yaml**（见 11.2 末条）

团队内已有 `scripts/pack-skill.sh` 可帮助过滤这些，但最终责任在打包者。

### 11.4 版本号策略

- [ ] **版本号不写在二进制文件名里**：版本号由 `--version` 参数在发布时传入，不固化到产物
- [ ] **版本号语义清晰**：优先使用 `vMAJOR.MINOR.PATCH` 或 `vMAJOR.MINOR.PATCH-tag.<num>`，末尾是**数字**便于 admin 自动 bump
  - ✅ `v1.0.0` → 自动建议 `v1.0.1`
  - ✅ `v1.0.0-moo-cli.2` → 自动建议 `v1.0.0-moo-cli.3`
  - ⚠️ `v1.0.0-rc` → admin 报 `version_bump_unsupported`，每次发布都要手工给版本号
- [ ] **不用 `latest` / `stable` / `HEAD` 等漂浮标记**作为版本号

### 11.5 和 moo-cli 运行时的契约

- [ ] **stdout = JSON，stderr = 进度 / 日志**（继承 c5），因为 Agent 会解析 stdout
- [ ] **敏感信息通过 `MOO_CLI_TOKEN` 等 inject env 读取，不要从命令行参数读**
- [ ] **二进制支持 `--schema` 或 `--help` 打印能力描述**（可选但推荐），方便 admin 在发布时自动生成 plugin.yaml 的 `commands` 字段

### 11.6 change_type 心智对齐

moo-cli 在升级时根据发布的 `change_type` 决定行为：

- `skill_only`：仅 skill/references/scripts 变更，不重下二进制——用户升级近乎瞬间
- `full`：二进制也变了，整包下载

**开发者应主动维护这个心智**：

- [ ] **纯改 SKILL.md / references / 文案** → 可以不改二进制，admin 会自动识别为 `skill_only` 小版本升级
- [ ] **二进制改动必然伴随 skill 文档同步更新**（至少 `keywords` 或某个示例），避免出现"二进制变了但 skill 还在讲老行为"

### 11.7 发布前 dry-run 自检

在让 admin 联动 rainbow 之前，先自己跑：

```bash
moo-admin release-pkg /path/to/your-plugin-pkg.zip --channel=beta --dry-run
```

- [ ] exit 10 (`dry_run_ok`)，**不是** exit 2
- [ ] stdout 里 `generated_plugin_yaml` 的 keywords 和你期望的触发词一致
- [ ] `change_type` 预判符合你的预期（纯改文档的 PR 不应该是 `full`）
- [ ] `binary_sha256` 4 平台齐全

任何一项不符 → 先修再发。

---

## 反模式

```text
❌ SKILL.md 写 name: example-cli，但二进制叫 <cli>-darwin-arm64
   → preflight 报 "binary_errors: name mismatch"；改二进制文件名或改 frontmatter。

❌ 发布包里塞一个 plugin.yaml 以为会被 admin 使用
   → preflight 报 "pkg_invalid: plugin.yaml must not be in pkg"；
     plugin.yaml 由 admin 自动生成，开发者不应手写。

❌ 二进制用版本号命名：example-cli-v1.0.0-darwin-arm64
   → 版本号通过 --version 传入。命名里带版本会让后续 CI 复用出现一堆分支。

❌ 把 4 个平台的 zip 分别发：
   moo-admin release-pkg example-cli-darwin-arm64.zip  (只含 1 个二进制)
   → 一次应该发一个完整包，4 平台齐全；否则客户端其它平台用户无法升级。

❌ 每次发布都让 admin LLM 抽 keywords，不在 frontmatter 固化
   → 抽取结果每次可能不同，触发稳定性差。首次发布 admin 抽过后就写回 SKILL.md。

❌ 版本号用末尾非数字：v1.0.0-beta
   → 每次发布都会被 admin 报 version_bump_unsupported，需要手工给版本号。
     改成 v1.0.0-beta.1 / .2 / .3 可以自动 bump。
```

---

## 和其它 checklist 的关系

| 场景 | 首选 checklist |
|---|---|
| SKILL.md description 写得好不好 | c1-trigger + reference/description |
| SKILL.md 文档结构、是否符合 Agent 心智 | c9-skill-architecture |
| 插件 CLI 命令是否"开箱即跑" | c2-cli-contract |
| stdout/stderr 契约 | c5-output-contract |
| **发布包合规（本条）** | **c11 —— 专供 moo-cli 插件发布** |

---

## 参考

- `moo-cli/docs/release-pkg-spec.md` —— 完整协议
- `moo-cli/skill/admin/SKILL.md` —— Agent 侧发布流程
- `moo-cli/skill/admin/references/pkg-spec.md` —— Agent 速查
