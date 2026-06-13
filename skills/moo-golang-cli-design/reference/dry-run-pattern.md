# --dry-run 实现模式

> "Agent 是会犯错的，给它一个零成本的试错机制。"

所有写命令必须支持 `--dry-run`。

## 契约

| 输入 | 行为 | 退出码 | stdout | stderr |
|------|------|--------|--------|--------|
| `--dry-run` + 完整合法参数 | 校验参数，**不发任何写 RPC**，输出 plan | **10** | plan JSON | (空) |
| `--dry-run` + 缺参/非法 | 直接返回参数错 | 2 | (空) | NDJSON 错误 |
| 不带 `--dry-run` | 真实执行 | 0/3/4/5/... | 业务结果 | 进度 |

## 注册 flag（每个写命令）

```go
var dryRun bool

cleanCreateCmd.Flags().BoolVar(&dryRun, "dry-run", false,
    "仅校验参数并输出计划，不真实创建（exit 10 表示 dry-run 通过）")
```

> 不建议把 `--dry-run` 注册成 PersistentFlag。dry-run 是写操作专属语义，
> 注册到 root 会让 `<cli> list --dry-run` 这种无意义组合也能解析通过。

## 实现骨架

```go
RunE: func(cmd *cobra.Command, args []string) error {
    // 1) 必填 / 协议 / 路径校验：dry-run 也必须跑
    if err := ValidateInputURL("input-file", inputFile); err != nil { return err }

    // 2) 业务上的"再深一层"校验：例如检查 UDF 名是否符合命名规则、字段数是否一致等
    if err := semanticCheck(req); err != nil { return err }

    // 3) dry-run 短路：构造 plan，输出，return DryRunOK（exit 10）
    if dryRun {
        plan := map[string]any{
            "would_create": req,
            "estimated_rows": guessedRows,
            "warnings": collectWarnings(req),
        }
        return EmitDryRun(plan)
    }

    // 4) 真实执行
    rsp, err := client.Create(ctx, req)
    ...
}
```

## EmitDryRun 实现

```go
// templates/output.go.tmpl 已包含
func EmitDryRun(plan any) error {
    if err := printJSON(plan); err != nil {
        return err
    }
    return NewDryRunOK("dry-run validation passed; remove --dry-run to apply")
}
```

main.go 的 `ClassifyError` 会把 `ErrTypeDryRunOK` 映射为 `ExitDryRunOK(10)`。

## 不能做的事

| ❌ 反模式 | 为什么 |
|----------|--------|
| dry-run 调真实写 RPC | 名字叫"试跑"反而下单了，比不支持 dry-run 还危险 |
| dry-run 跳过参数校验 | 校验本身是 dry-run 最大价值，不校验等于没做 |
| dry-run 退出码 = 0 | Agent 分不清"试跑通过"vs"真实下单成功" |
| dry-run 输出 = 空 / 仅 stderr | Agent 没法用 jq 解析 plan，无法在试跑后做条件判断 |
| dry-run 不警告幂等键 | 用户传了 `--idempotency-key` 和 `--dry-run`，应在 stderr hint：dry-run 不写缓存 |

## dry-run 内可以调用什么

| 调用类型 | 是否允许 | 备注 |
|---------|---------|------|
| 输入校验（validate.go） | ✅ | 必须 |
| 只读 Get / List（决定是否冲突） | ⚠️ 谨慎 | 可以但要在 plan 里标注 `"prechecked": true` |
| 后端的 `--dry-run` 接口 | ✅ | 如果后端有 dry-run RPC，优先复用 |
| Create / Update / Delete | ❌ | 任何写 RPC 都禁止 |
| 上传到 COS / 下游 webhook | ❌ | 任何外部副作用都禁止 |

## 推荐 plan 结构

```json
{
  "would_execute": "clean create",
  "would_send_to": "api.github.com/repos/mooyang-code/dev-boost/actions/workflows/clean.yml/dispatches",
  "request": { ... 真实即将发送的 req ... },
  "estimated_rows": 12345,
  "estimated_cost_seconds": 30,
  "warnings": [
    "UDF normalize_title 已存在 v3 版本，本次将创建 v4",
    "未设置 --rate-limit，将使用默认 1000 QPS"
  ],
  "checks_passed": ["url_scheme", "file_size", "permission"]
}
```

让 Agent 在试跑后能：
- `jq '.estimated_rows'` 决定是否真实执行
- `jq '.warnings | length'` 决定是否需要二次确认
- `jq '.request'` 重放 / 缓存
