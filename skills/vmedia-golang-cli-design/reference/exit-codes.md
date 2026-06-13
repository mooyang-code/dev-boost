# 退出码契约

退出码一旦发布即 API，**不允许重新定义已有码的语义**，只能新增。

| 码 | 名称 | 含义 | Agent 处理建议 | 典型触发 |
|----|------|------|--------------|---------|
| 0 | ExitOK | 成功 | 解析 stdout JSON | 正常路径 |
| 1 | ExitGeneric | 未分类错误（兜底） | 看 stderr `error` 字段；不要盲目重试 | 极少触发（被 ClassifyError 兜住） |
| 2 | ExitUsage | 参数错误 | 读 `suggestion` 字段改参，**不要重试** | 必填缺失、枚举非法、dry-run 校验失败、cobra unknown command |
| 3 | ExitNotFound | 资源不存在 | 先 `list / get` 确认，再决定是否 create | 项目/任务/规则 ID 找不到 |
| 4 | ExitPermissionDenied | 权限不足 | 用 `auth check` 验证，必要时 `auth grant` | PAT Token 无对应项目权限 |
| 5 | ExitConflict | 资源已存在/状态冲突 | 改用 update / get；create 加 `--if-not-exists` | 重复创建 |
| 6 | ExitRateLimited | 被限流 | **退避后重试**（同 key 加 `--idempotency-key`） | 网关 429 / QPS 超限 |
| 7 | ExitNetwork | 网络错误或超时 | **退避后重试** | DNS 失败、connection reset、ctx timeout |
| 10 | ExitDryRunOK | dry-run 通过 | 视为成功，去掉 `--dry-run` 真实执行 | `<cli> create --dry-run` 校验通过 |

## 关键设计决策

### 为什么 ExitDryRunOK = 10 而不是 0？

如果 dry-run 也返回 0，Agent 看到 exit=0 + 一段 JSON，会以为操作真的执行了。
返回 10 让 Agent 必须显式分流："`exit==10` 是试跑通过，`exit==0` 才是真实下单成功"。

### 为什么 ExitUsage = 2 而不是 1？

GNU 约定 `2` 是 "misuse of shell builtins / invalid arguments"，与 cobra 默认的 1 区分开。
更重要的：让 Agent 区分"参数错（不要重试）"vs"未分类错（可能可以重试）"。

### 为什么 cobra usage 错误也要归到 ExitUsage？

`required flag(s) "x" not set` 这类错误本质就是参数错。如果不归类，会被兜底成 ExitGeneric(1)，
Agent 拿到 1 会按"未分类异常"放弃重试 / 或执行错误的兜底流程。

实现见 `templates/exitcode.go.tmpl::isCobraUsageError`。

### 不要新增退出码，除非…

新增代价高（所有 Agent 都得更新），现有 8 + 1 个码已经覆盖 95% 场景。

确实需要的场景：
- 后端达到一致性容忍上限（如审批流卡住） → 考虑 `ExitTimeout=8`
- 业务侧明确的"配额耗尽" → 考虑 `ExitQuotaExceeded=9`

新增前先在团队 PR 讨论。

## 调用约定

```go
// main.go
func main() {
    if err := rootCmd.Execute(); err != nil {
        PrintCLIErrorJSON(err)              // stderr 单行 NDJSON
        os.Exit(ClassifyError(err))         // 自动按 *CLIError.Type 或 cobra 文本归类
    }
}
```

## 在 schema 中暴露

`<cli> schema --exit-codes-only` 必须输出完整退出码列表，让 Agent 程序化获取契约：

```bash
$ <cli> schema --exit-codes-only | jq '.exit_codes | map({code,name,meaning})'
```

实现见 `reference/schema-introspection.md`。
