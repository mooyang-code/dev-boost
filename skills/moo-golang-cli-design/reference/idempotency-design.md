# 幂等键 + --if-not-exists 设计

> Agent 在重试链路里反复跑 `<cli> create`，如果不解决，几分钟内能创建几十个相同任务。

两条独立但互补的机制：

- **`--idempotency-key`**：通用，无需后端配合。CLI 本地落盘缓存 → 同 key + 同业务参数 在 TTL 内 replay。
- **`--if-not-exists`**：仅 `create` 类（用户提供 ID）。先 Get 再 Create，已存在直接返回 0。

| 场景 | 推荐 |
|------|------|
| Agent 在脚本里跑 `clean create`，全程没显式 ID（后端自动分配 task_id） | `--idempotency-key clean-2026-04-19-001` |
| Agent 想确保某个 `project_id=saas_xxx` 存在 | `--if-not-exists` |
| 创建带固定 dashboard_id 的看板 | `--if-not-exists` |
| 启动后台 cronjob，每天跑一次 | `--idempotency-key cron-$(date +%F)` |

## --idempotency-key 完整方案

### 缓存键

```
sha256(idempotency-key + "|" + commandPath + "|" + sha256(sortedBizFlags))
```

排除会话/输出/认证类 flag（必须排除，否则改 `--output` 命中失效）：

```go
var idempotencyKeyExcludeFlags = map[string]bool{
    "output": true, "verbose": true,
    "env": true, "gateway": true, "token": true,
    "no-interactive": true, "yes": true,
    "dry-run": true,
    "idempotency-key": true, "idempotency-ttl": true, "idempotency-cache-dir": true,
    "if-not-exists": true,
}
```

### 缓存目录

```
$XDG_CACHE_HOME/<your-cli>/idempotency/<sha256>.json
   或 fallback: ~/.cache/<your-cli>/idempotency/<sha256>.json
```

可用 `--idempotency-cache-dir` 显式覆盖（CI 里清理用）。

### 缓存条目结构

```json
{
  "schema_version": 1,
  "key": "clean-2026-04-19-001",
  "command": "<your-cli> clean create",
  "args_hash": "deadbeef...",
  "payload": { ... 上次成功的响应 ... },
  "created_at": "2026-04-19T10:00:00Z",
  "ttl_seconds": 86400
}
```

`schema_version` 用于未来兼容；版本不匹配时丢弃（视为未命中）。

### TTL 默认 24h

`--idempotency-ttl 30m` / `2h` / `7d`。命中过期 → 删除文件 + 重新执行。

### RunE 内调用

```go
RunE: func(cmd *cobra.Command, args []string) error {
    if dryRun {
        return EmitDryRun(plan)
    }
    if replayed, err := MaybeReplayIdempotent(cmd); err != nil {
        return err
    } else if replayed {
        return nil   // 已 printOutput 缓存内容
    }
    rsp, err := client.Create(ctx, req)
    if err != nil { return err }
    if e := CheckBizCode("CreateXxx", rsp.Code, rsp.Message); e != nil {
        return e
    }
    return EmitIdempotent(cmd, rsp)   // 内部 = SaveIdempotent + printOutput
}
```

### 关键不变量

| 不变量 | 违反后果 |
|--------|---------|
| 业务码 != 0 必须 return CLIError，**不能**直接 EmitIdempotent | 失败响应被缓存，重试 replay 一个错误结果，Agent 永远走不出来 |
| 改业务参数（input-file / project / mode 等）必须命中失效 | 否则相同 key 可以"复用"完全不同的请求 |
| 改 `--output` / `--gateway` 不能影响命中 | 否则用户被迫每次保持一致才能 replay |
| dry-run **不写**缓存 | 试跑结果不应被当成真实结果 |

### 局限

- **跨机不一致**：缓存在本地磁盘，A 机和 B 机的同 key 各走各的。Agent 单机/单 runner 场景已足够；多 runner 部署需要共享 cache dir 或后端真幂等。
- **不防并发**：同一台机器上同时跑两条同 key 命令，第二条到 MaybeReplay 时第一条还没 SaveIdempotent，会双发。需要的话加文件锁。

## --if-not-exists 完整方案

仅适用于"用户提供唯一 ID 的 create"。

### 注册 flag

```go
projectCreateCmd.Flags().BoolVar(&ifNotExists, "if-not-exists", false,
    "存在则跳过创建并返回现有资源（exit 0）")
```

### RunE 内实现

```go
if ifNotExists {
    existing, gerr := client.GetProject(ctx, &GetReq{Id: projectID})
    switch {
    case gerr == nil && existing != nil:
        hintln("[if-not-exists] %q already exists, skipping create", projectID)
        return EmitIdempotent(cmd, map[string]any{
            "status": "exists",
            "data":   existing,
        })
    case gerr != nil && !isCLIErrorType(gerr, ErrTypeNotFound):
        // 网络错 / 权限错 → 透传，不要硬塞 create
        return gerr
    }
    // 走到这里：NotFound，继续 Create
}
```

### 输出契约

成功创建：
```json
{"status":"created","data":{...}}
```

已存在：
```json
{"status":"exists","data":{...}}
```

让 Agent 用 `jq '.status'` 区分两种情况。

## 全局 flag 注册（root.go）

```go
func init() {
    registerIdempotencyFlags(rootCmd)
    // ...
}
```

`registerIdempotencyFlags` 完整实现见 示例平台的 `cmd/cli/idempotency.go`，约 260 行。
关键代码片段已在 SKILL.md §3.5 / §3.6 给出。

## 推荐 Agent 调用模式

```bash
# 模式 A：通用幂等键（任何写命令）
KEY="my-pipeline-$(date +%Y%m%d)-$(uuidgen | head -c 8)"
<cli> clean create --idempotency-key "$KEY" --project xxx --mode udf ...
# 失败可重试同样的命令，成功结果会被缓存 24h

# 模式 B：用户控制 ID 的创建
<cli> project create --if-not-exists --project-id saas_team_video_1 --owner alice
# 已存在不会报错，stdout 输出 {"status":"exists",...}

# 模式 C：dry-run + 真实跑（推荐 Agent 写复杂流水线时使用）
<cli> clean create --dry-run --project xxx --mode udf ... # exit 10 = 校验通过
<cli> clean create --idempotency-key "$KEY" --project xxx --mode udf ...
```
