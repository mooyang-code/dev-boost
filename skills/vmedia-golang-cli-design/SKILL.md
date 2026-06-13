---
name: vmedia-golang-cli-design
description: 媒资组 Go CLI 设计规范，面向 AI Agent / CI / 人工三类调用方设计的命令行工具。涵盖 stdout/stderr 输出契约、退出码语义化、结构化错误对象 CLIError、--dry-run、schema 自省、--idempotency-key 幂等键、--if-not-exists、TTY 自适应、输入安全校验、cobra 错误归类。当用户开发新 CLI、改造旧 CLI、Code Review CLI 命令、解决 Agent 调用 CLI 不稳定问题时触发。
---

# 媒资 Go CLI 设计规范

面向 **AI Agent 优先** 的 CLI 设计指南。基于 `vmedia-dm`（datamind）改造经验沉淀，已在生产 Agent 流程跑通。

> **核心理念**：CLI 是契约。Agent 不会读你的 README，它只会观察 stdout / stderr / exit code。三者中任何一个不稳定，整条 Agent 流水线就会反复猜测、重复下单、错误退避。

---

## 一、设计原则速查（10 条）

| # | 原则 | 一句话规则 | 关联模板/文档 |
|---|------|-----------|--------------|
| 1 | **输出契约** | stdout 永远是结构化数据；进度/日志/错误/提示一律 stderr | `templates/lint-stdout.sh` + `templates/output.go.tmpl` |
| 2 | **退出码语义化** | 不要只用 0/1；按场景细分（usage=2 / not_found=3 / permission=4 / rate_limited=6 / network=7 / dry_run_ok=10 …） | `templates/exitcode.go.tmpl` + `reference/exit-codes.md` |
| 3 | **结构化错误对象** | 失败时 stderr 输出单行 NDJSON：`{error,message,suggestion,retryable,detail}` | `templates/cli_error.go.tmpl` |
| 4 | **--help 必须有 Long 示例** | Short 一行；Long 给 ≥3 个真实可粘贴的命令样例 | 见本文 §3.4 |
| 5 | **写操作必有 --dry-run** | 通过返回 exit=10（不是 0），让 Agent 区分"试跑通过"vs"真实下单成功" | `reference/dry-run-pattern.md` |
| 6 | **schema 自省** | 提供 `<cli> schema [cmd]`，结构化暴露命令树/参数/枚举值/退出码 | `reference/schema-introspection.md` |
| 7 | **输入安全校验** | URL 协议白名单、本地路径黑名单、文件大小上限，全部 fail-fast 不发请求 | `templates/validate.go.tmpl` |
| 8 | **幂等键** | 全局 `--idempotency-key`：同 key + 同业务参数在 TTL 内 replay；写命令统一接 `EmitIdempotent` | `reference/idempotency-design.md` |
| 9 | **存在性短路** | `create` 类命令支持 `--if-not-exists`：先 Get 再 Create，已存在直接返回（exit 0） | `reference/idempotency-design.md` |
| 10 | **TTY 自适应** | 未显式 `--output` 时 TTY 走 table、管道走 json；非 TTY 自动收敛 emoji；全局 `--no-interactive` / `--yes` | `templates/term.go.tmpl` |

---

## 二、最小落地步骤（新项目 30 分钟跑通）

按顺序做这 6 步，新 CLI 项目就具备 Agent 友好基线：

```bash
# 0. 假设你已经有 cmd/<your-cli>/ 目录和 cobra rootCmd
cd cmd/<your-cli>/

# 1. 拷贝六个基础文件
cp $SKILL/templates/cli_error.go.tmpl  ./cli_error.go
cp $SKILL/templates/exitcode.go.tmpl   ./exitcode.go
cp $SKILL/templates/term.go.tmpl       ./term.go
cp $SKILL/templates/validate.go.tmpl   ./validate.go
cp $SKILL/templates/output.go.tmpl     ./output.go
cp $SKILL/templates/lint-stdout.sh     ../../scripts/lint-stdout.sh

# 2. 把 *.go 文件里的 <YOUR-CLI> 替换为你的 CLI 名（如 vmedia-foo）
sed -i '' 's/<YOUR-CLI>/vmedia-foo/g' ./{cli_error,exitcode,term,validate,output}.go

# 3. 在 main.go 里把 rootCmd.Execute() 包成下面的 §3.1 模式
# 4. 在 root.go init() 注册 --no-interactive / --yes（见 §3.5）
# 5. 在 Makefile 加 lint-cli 目标
echo -e "\nlint-cli:\n\t@bash scripts/lint-stdout.sh" >> Makefile

# 6. 跑一遍验证：必须输出 "OK: cmd/cli stdout 纪律检查通过"
make lint-cli
```

完成后立刻可用：结构化错误、语义化退出码、TTY 自适应、stdout 纪律检查。

---

## 三、核心代码模式

### 3.1 main.go 必须这样写

```go
func main() {
    if err := rootCmd.Execute(); err != nil {
        PrintCLIErrorJSON(err)              // stderr 输出单行 NDJSON
        os.Exit(ClassifyError(err))         // 按错误类型映射退出码
    }
}
```

**配套 cobra 配置（去掉 cobra 默认的 stderr 噪声）：**

```go
var rootCmd = &cobra.Command{
    Use:           "<your-cli>",
    SilenceErrors: true,   // 不让 cobra 自己 fprintln stderr
    SilenceUsage:  true,   // 不让 cobra 把整段 usage 喷出来
    // ...
}
```

> ⚠️ 不加 `SilenceErrors/SilenceUsage`，cobra 会在 stderr 喷 `Error: ...` + 完整 help 文本，污染 NDJSON 错误流。Agent 拿到 mixed 内容直接懵。

### 3.2 stdout 纪律：stdout 只能写结构化数据

| 用途 | 禁用 | 推荐 |
|------|------|------|
| 业务结果 | `fmt.Print*` 散落各处 | 统一从 `output.go::printOutput(payload)` 出口 |
| 进度日志 | `fmt.Println("正在上传...")` | `progressln("正在上传...")` 内部 = `fmt.Fprintln(os.Stderr, ...)` |
| 提示/hint | `fmt.Printf("[hint] ...")` | `hintln("[hint] ...")` 内部走 stderr |
| 第三方 SDK 污染 | verbose SDK/zap 直接 fd1 写 | `redirectStdoutToStderr()` dup fd1→fd2 屏蔽 |

执行 `make lint-cli` 自动校验全部 `*.go` 文件，违规直接 fail。模板见 `templates/lint-stdout.sh`。

### 3.3 退出码契约（一旦发布即 API，不可改语义）

```go
// templates/exitcode.go
const (
    ExitOK               = 0
    ExitGeneric          = 1
    ExitUsage            = 2   // 参数错（必填缺失/枚举非法/dry-run 校验失败）
    ExitNotFound         = 3   // 资源不存在
    ExitPermissionDenied = 4
    ExitConflict         = 5
    ExitRateLimited      = 6
    ExitNetwork          = 7
    ExitDryRunOK         = 10  // dry-run 通过（≠ 真实执行成功）
)
```

完整契约（含 Agent 处理建议）见 [reference/exit-codes.md](reference/exit-codes.md)。

**特别注意**：`ClassifyError` 必须识别 cobra/pflag 解析阶段的字符串错误（`required flag` / `unknown flag` / `unknown command` / ...），否则它们会被兜底成 `ExitGeneric(1)`，Agent 拿到 1 会按"未分类异常"放弃重试。模板已实现。

### 3.4 Long help：写 ≥ 3 个真实示例

不要写"创建一个清洗任务"这种废话。直接给 Agent 可粘贴的命令：

```go
cleanCreateCmd.Long = `创建一个 UDF/builtin 数据清洗任务。

示例：
  # 1) UDF 模式 + 试跑（不会真实下单）
  vmedia-foo clean create --dry-run \
    --project saas_xxx_video_1 --mode udf \
    --udf-name normalize_title --input-file cos://bkt/raw/2026-04-19.csv

  # 2) 真实创建 + 幂等键（重试不重复下单）
  vmedia-foo clean create --idempotency-key clean-2026-04-19-001 \
    --project saas_xxx_video_1 --mode udf ...

  # 3) 看输出
  vmedia-foo clean create ... | jq '.task_id'`
```

### 3.5 root.go 全局参数注册（标准三段）

```go
func init() {
    // 业务全局
    rootCmd.PersistentFlags().StringVar(&flagOutput,  "output",   "json", "json/table；TTY 下未显式指定时自动 table")
    rootCmd.PersistentFlags().StringVar(&flagGateway, "gateway",  defaultGateway, "网关地址")
    rootCmd.PersistentFlags().StringVar(&flagToken,   "token",    "",     "API token，优先于 API_TOKEN")
    rootCmd.PersistentFlags().BoolVar(&flagVerbose,   "verbose",  false,  "详细日志")

    // 交互模式（template/term.go 已经声明 flagNoInteractive / flagYes）
    rootCmd.PersistentFlags().BoolVar(&flagNoInteractive, "no-interactive", false, "禁止任何 stdin 提示（CI/Agent 必加）")
    rootCmd.PersistentFlags().BoolVarP(&flagYes,          "yes", "y",       false, "对所有交互式确认默认回答 yes")

    // 幂等机制
    registerIdempotencyFlags(rootCmd)

    // 自适应 --output 默认值
    rootCmd.PersistentPreRunE = func(cmd *cobra.Command, args []string) error {
        if !cmd.Flags().Changed("output") && IsStdoutTTY() {
            flagOutput = "table"
        }
        return nil
    }
}
```

### 3.6 写命令统一骨架（dry-run + 幂等 + 错误分类）

每个写命令的 RunE 严格按这个顺序写：

```go
RunE: func(cmd *cobra.Command, args []string) error {
    // a) 输入校验（fail-fast，不发请求）
    if err := ValidateInputURL("input-file", inputFile); err != nil { return err }

    // b) dry-run 短路：通过返回 ExitDryRunOK，不发任何 RPC
    if dryRun {
        return EmitDryRun(cmd, plan)   // 内部 return NewDryRunOK("...")
    }

    // c) --if-not-exists 短路（仅 create 类命令）
    if ifNotExists {
        existing, gerr := client.Get(ctx, &GetReq{Id: id})
        switch {
        case gerr == nil && existing != nil:
            hintln("[if-not-exists] %q already exists, skipping create", id)
            return EmitIdempotent(cmd, map[string]any{"status": "exists", "data": existing})
        case gerr != nil && !isCLIErrorType(gerr, ErrTypeNotFound):
            return gerr
        }
    }

    // d) 幂等 replay：命中直接 return nil（已 printOutput）
    if replayed, err := MaybeReplayIdempotent(cmd); err != nil {
        return err
    } else if replayed {
        return nil
    }

    // e) 真实 RPC
    rsp, err := client.Create(ctx, req)
    if err != nil {
        return err   // 已经是 *CLIError 或被 PrintCLIErrorJSON 兜底
    }

    // f) 业务码校验：rsp.Code != 0 必须转 CLIError，否则失败响应会被缓存
    if e := CheckBizCode("CreateXxx", rsp.Code, rsp.Message); e != nil {
        return e
    }

    // g) 写缓存 + 输出
    return EmitIdempotent(cmd, rsp)
}
```

> 关键不变量：**业务码 != 0 必须 return CLIError，不能直接 EmitIdempotent**。否则失败响应会被当成成功结果缓存，下次同 key 直接 replay 一个错误结果。

### 3.7 错误分类决策树

```
err 是什么？
├─ nil                                        → return EmitIdempotent(rsp)
├─ *CLIError                                  → return err（已分类好）
├─ 网关 HTTP 错误（trpc errs.New）            → 用 mapGatewayError 转 CLIError（templates 含示例）
├─ 业务码 rsp.Code != 0                       → CheckBizCode 转 CLIError
├─ cobra 解析错误（required flag/unknown ...）→ 不需要你处理，ClassifyError 自动归类 ExitUsage
└─ 其他原始 error                             → 原样 return，PrintCLIErrorJSON 包成 generic_error
```

CLIError 类型选择参考 [reference/error-types.md](reference/error-types.md)。

---

## 四、--dry-run 实现要点

设计要点见 [reference/dry-run-pattern.md](reference/dry-run-pattern.md)，速记：

- dry-run 通过 → `return NewDryRunOK("ok, would create xxx")`，main 自动 exit=10
- dry-run 校验失败 → `return NewUsageError(...)`，exit=2
- dry-run **绝对不发 RPC**（除非是只读探测，且必须在 stderr hint 标注）
- dry-run 在所有写命令上必须可用，包括 `auth grant` / `dashboard create` 等次要命令

---

## 五、schema 自省命令

让 Agent 不靠记忆/猜测就能知道有哪些命令、参数、枚举值。

```bash
<cli> schema --all                    # 整棵命令树
<cli> schema clean create             # 单命令（放在 .commands[0]）
<cli> schema --exit-codes-only        # 仅退出码契约
```

实现要点：
- 不调任何 RPC，全部从 cobra 内存元数据生成
- 通过自定义 annotation `vmedia.dm/enum` 标注枚举值（`RegisterEnum(cmd, "mode", "udf", "builtin")`），Agent 直接拿到合法值
- 输出含 `exit_codes` / `error_types` / `stderr_format` / `stdout_format` 元信息

完整实现细节 + 可拷代码见 [reference/schema-introspection.md](reference/schema-introspection.md)。

---

## 六、输入安全校验（必做）

`templates/validate.go.tmpl` 给出三类校验函数模板：

| 函数 | 用途 | 失败行为 |
|------|------|---------|
| `ValidateInputURL("input-file", v)` | 限定 URL 协议白名单（http/https/cos） | `NewUsageError`，exit=2 |
| `ValidateLocalPath("file", v)` | 拒绝 `/etc /sys /proc ~/.ssh ~/.aws ~/.kube` 等敏感目录 | `NewUsageError`，exit=2 |
| `ValidateFileSize("file", v, 5GiB)` | 上传文件大小上限 | `NewUsageError`，exit=2 |

**血泪教训**：不做协议校验，Agent 把 `file:///etc/passwd` 当 `--input-url` 喂给后端 → SSRF；不做路径黑名单，让 Agent 误传 `~/.ssh/id_rsa` 上传 COS → 凭据泄露。

---

## 七、幂等键 + --if-not-exists

完整设计与代码见 [reference/idempotency-design.md](reference/idempotency-design.md)。要点：

- **CLI 端方案，不改 pb**：缓存落本地磁盘 `$XDG_CACHE_HOME/<cli>/idempotency/<sha256>.json`
- **缓存键** = `--idempotency-key` + 命令路径 + 业务 flag 哈希（排除 `--output` `--gateway` 等会话相关 flag）
- **TTL** 默认 24h（可配 `--idempotency-ttl`）
- 仅成功执行写缓存；失败不阻塞重试
- `--if-not-exists` 仅适用于"用户提供唯一 ID 的 create"（如 `project create --project-id xxx`），其他场景用 `--idempotency-key`

---

## 八、TTY 自适应

集中在 `templates/term.go` 一份代码：

| API | 用途 |
|-----|------|
| `IsStdoutTTY()` | 决定 `--output` 默认值 / 是否输出 table |
| `IsStderrTTY()` | 决定是否带 emoji / 颜色 |
| `IsInteractive()` | 决定是否允许 stdin prompt（任一条件触发就 false：`--no-interactive`、`--yes`、stdin/stdout 不是 TTY） |
| `AssumedYes()` | 用户已通过 `--yes` 同意所有 prompt |
| `SymbolOK/Fail/Warn()` | TTY 下出 `✓ ✗ ⚠`，CI 下出 `[OK] [FAIL] [WARN]`（grep 友好） |

---

## 九、上线前自检 Checklist

| 项目 | 检查命令 | 期望 |
|------|----------|------|
| 1. stdout 纪律 | `make lint-cli` | `OK: cmd/cli stdout 纪律检查通过` |
| 2. 缺参 | `<cli> <write-cmd>`（不传必填） | exit=2 + stderr 单行 NDJSON `error:"invalid_argument"` |
| 3. 不存在子命令 | `<cli> not-a-cmd` | exit=2 + suggestion 指向 schema |
| 4. dry-run 通过 | `<cli> <write-cmd> --dry-run --required-args ...` | exit=10 |
| 5. schema 完整 | `<cli> schema --all \| jq 'keys'` | 含 `commands` `global_flags` `exit_codes` `error_types` |
| 6. schema 单命令 | `<cli> schema <cmd> \| jq '.commands[0].flags \| length'` | > 0 |
| 7. 幂等 replay | 同 key 跑两次写命令 | 第二次 stderr 含 `[idempotent] replay cache hit` + stdout 一致 |
| 8. TTY 自适应 | `<cli> list \| head` 与 `<cli> list`（直接终端） | 前者 json、后者 table |
| 9. 单测 | `go test ./cmd/<cli>/...` | 全绿，含 `exitcode_test` `term_test` `idempotency_test` |
| 10. README + skill | 更新到反映新参数 | `--user / --server` 等过时 flag 已清理 |

---

## 十、常见陷阱

| 陷阱 | 症状 | 修复 |
|------|------|------|
| 业务码 != 0 仍 EmitIdempotent | 失败响应被缓存，下次 replay 还是错的 | 在 `EmitIdempotent` 前必须 `CheckBizCode` |
| cobra 默认 SilenceErrors=false | stderr 既有 NDJSON 又有 cobra 的 `Error: ...` | rootCmd 设 `SilenceErrors: SilenceUsage: true` |
| verbose SDK / zap 直接 fd1 写 | stdout 混入 INFO 日志 | main 入口 `redirectStdoutToStderr()` dup fd1→fd2 |
| `--output` 默认硬编码 table | Agent / 管道场景每次手动 `--output json` | 默认 `json`，仅在 `IsStdoutTTY() && !Changed("output")` 时切 table |
| dry-run 调了真实 RPC | "试跑"反而下单 | dry-run 只做参数校验 + plan 输出，**不发任何写 RPC** |
| 幂等键参与了 `--output` 的哈希 | 改 `--output` 命中失效 | 必须排除会话/输出/认证相关 flag（见模板 `idempotencyKeyExcludeFlags`） |
| `--if-not-exists` 用在没有 Get 接口的资源上 | 一律走 Create，失败/重复 | 仅在用户传入 ID 且后端有幂等 Get 时启用 |
| Long help 只写中文描述无示例 | Agent 不知道如何组合参数 | Long 必须含 ≥3 段可粘贴命令 |

---

## 十一、参考与延伸

- [reference/exit-codes.md](reference/exit-codes.md) — 退出码完整契约 + Agent 处理建议
- [reference/error-types.md](reference/error-types.md) — CLIError 类型选择树 + 工厂函数
- [reference/dry-run-pattern.md](reference/dry-run-pattern.md) — dry-run 实现模板
- [reference/schema-introspection.md](reference/schema-introspection.md) — schema 命令完整代码
- [reference/idempotency-design.md](reference/idempotency-design.md) — 幂等键 + --if-not-exists 设计
- `templates/cli_error.go.tmpl` `exitcode.go.tmpl` `term.go.tmpl` `validate.go.tmpl` `output.go.tmpl` `lint-stdout.sh` — 可直接拷贝的代码
- 真实参考实现：`github.com/mooyang-code/xData-mini/storage/cmd/cli/`、`docs/cli/refactor-plan.md`
