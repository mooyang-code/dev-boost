# CLIError 类型选择树

## 类型常量与工厂函数对照

| Type 常量 | 工厂函数 | Retryable | 退出码 |
|----------|---------|-----------|--------|
| `ErrTypeGeneric` = `"generic_error"` | （兜底） | false | 1 |
| `ErrTypeUsage` = `"invalid_argument"` | `NewUsageError` | false | 2 |
| `ErrTypeNotFound` = `"not_found"` | `NewNotFoundError` | false | 3 |
| `ErrTypePermissionDenied` = `"permission_denied"` | `NewPermissionError` | false | 4 |
| `ErrTypeConflict` = `"conflict"` | `NewConflictError` | false | 5 |
| `ErrTypeRateLimited` = `"rate_limited"` | `NewRateLimitedError` | true | 6 |
| `ErrTypeNetwork` = `"network_error"` | `NewNetworkError` | true | 7 |
| `ErrTypeDryRunOK` = `"dry_run_ok"` | `NewDryRunOK` | false | 10 |

> **Retryable** 是给 Agent 的提示。`true` = 同样请求等一会再发即可成功（如限流/网络）；`false` = 不改参数重试也是错（权限/参数）。

## 选择树

```
错误是怎么发生的？
├─ 参数错（必填缺失、值非法、互斥冲突）        → NewUsageError
├─ 资源 ID 找不到                            → NewNotFoundError
├─ 有 ID，但当前 Token 没权限                → NewPermissionError
├─ 资源已存在 / 状态冲突（重复创建、状态机非法跳转） → NewConflictError
├─ 后端 429 / "rate limited" / "too many requests" → NewRateLimitedError
├─ 网络层失败：DNS / connect / read timeout / EOF  → NewNetworkError
├─ dry-run 校验通过                          → NewDryRunOK
└─ 都不是                                    → 直接 return 普通 error，PrintCLIErrorJSON 兜底为 generic_error
```

## 一定要写 Suggestion

`suggestion` 是给 Agent 看的"修复方法"。没有它，Agent 拿到 `permission_denied` 只能猜怎么办。

| 错误 | 不写 suggestion ❌ | 好的 suggestion ✓ |
|------|-------------------|------------------|
| 参数错 | "missing required flag" | "用 `<cli> schema <cmd>` 查参数定义" |
| 不存在 | "project not found" | "用 `<cli> project list` 查询正确 ID" |
| 权限 | "permission denied" | "用 `<cli> auth grant --project xxx --module export`" |
| 冲突 | "already exists" | "改用 `<cli> xxx update`；如确认幂等可加 `--if-not-exists`" |
| 限流 | "rate limited" | "指数退避后重试；同 key 加 `--idempotency-key` 避免重复下单" |

## Detail 字段：附加结构化上下文

```go
return NewUsageError(
    fmt.Sprintf("--%s 文件不存在: %s", flagName, path),
    "确认路径正确",
).WithDetail("flag", flagName).WithDetail("path", path)
```

输出：
```json
{
  "error": "invalid_argument",
  "message": "--input-file 文件不存在: /tmp/x.csv",
  "suggestion": "确认路径正确",
  "retryable": false,
  "detail": {"flag":"input-file","path":"/tmp/x.csv"}
}
```

Agent 拿到 detail 可以做精确恢复，不用解析 message 字符串。

## 网关 / 业务码 → CLIError 映射

后端两层都可能返错，CLI 必须把它们都映射成 CLIError，避免向上抛出"原始 protobuf 错误字符串"：

| 来源 | 处理点 | 函数 |
|------|--------|------|
| trpc 错误（HTTP/JSON-RPC 状态码） | client 调用返 `err != nil` | `mapGatewayError(err)` 见示例 CLI 源码 |
| 业务码（`rsp.Code != 0`） | `if e := CheckBizCode(...); e != nil { return e }` | `cli_error.go::CheckBizCode` |
| cobra 解析错误（`required flag` 等） | 不需要业务代码处理 | `ClassifyError` 自动归类 |

## 何时不要用 CLIError

- **CLIError 是终点**，不要 wrap：`return fmt.Errorf("foo: %w", NewNotFoundError(...))` 会让 message 双层包裹，stderr 输出难看
- **dry-run 路径**用 `NewDryRunOK` 而不是 `nil`，否则 main 不会 exit=10
- **正常成功路径**直接 `return nil` + `printOutput`，不要硬塞 `NewCLIError("ok")`
