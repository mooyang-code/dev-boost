---
name: vmedia-golang-code-style
description: 媒资组 Go 编码规范，基于腾讯 Go 规范和团队实战经验。涵盖 Context/CloneContext、tRPC Log + WithContextFields、tRPC Metrics、卫语句、retry-go、GoAndWait、tRPC GORM 插件、DB 命名（d_/c_前缀）。当编写媒资 Go 代码、Code Review、重构时触发。
---

# Go 编码规范与实战规则

基于[腾讯 Go 编码规范](reference/tencent-go-standard.md)和团队实战经验，统一代码风格和最佳实践。

## 触发场景

- 编写新的 Go 代码
- Code Review
- 代码生成（AI 生成代码时自动遵循）
- 重构已有代码

---

## 核心规则

### 规则 1: Context 使用规范

**Context 必须作为函数的第一个参数，不要存储在结构体中。**

```go
// ✅ 正确：ctx 作为第一个参数
func (s *UserService) GetUser(ctx context.Context, userID string) (*User, error) {
    return s.repo.FindByID(ctx, userID)
}

// ❌ 错误：ctx 存储在结构体中
type UserService struct {
    ctx  context.Context  // 不要这样做！
    repo UserRepository
}

// ❌ 错误：使用 context.Background()
func (s *UserService) GetUser(userID string) (*User, error) {
    return s.repo.FindByID(context.Background(), userID)  // 丢失链路信息！
}
```

**为什么？**
- `context.Background()` 会丢失 TraceID 和全链路超时信息
- 结构体中的 ctx 可能被错误共享，导致超时和取消行为异常
- tRPC 的日志、监控、链路追踪都依赖 ctx 传递

#### 异步场景：trpc.CloneContext

**启动 goroutine 做异步任务时，必须用 `trpc.CloneContext(ctx)` 而不是 `context.Background()`。**

`CloneContext` 保留原 ctx 中的日志字段（TraceID、task_id 等 WithContextFields），但**断开**原 ctx 的超时/取消链路，避免：
1. handler 返回后原 ctx 被取消，导致异步任务的 DB/RPC 调用全部失败
2. 上游 RPC 的剩余超时传染到异步任务，导致长耗时任务提前超时

```go
import trpc "trpc.group/trpc-go/trpc-go"

// ✅ 正确：CloneContext 保留 log/trace 字段，断开超时继承
asyncCtx := trpc.CloneContext(ctx)
go func() {
    _ = s.engine.Run(asyncCtx, task, wfDef)
}()

// ❌ 错误：context.Background() 丢失所有链路字段
go func() {
    _ = s.engine.Run(context.Background(), task, wfDef)
}()

// ❌ 错误：直接传 ctx，handler 返回后 ctx 被取消，异步任务全部报错
go func() {
    _ = s.engine.Run(ctx, task, wfDef)
}()
```

**分页/循环中的多次网络请求，每次也要 clone：**

上游超时是一次性的，如果把同一个 ctx 传给所有翻页请求，第一页消耗的耗时会累积到后续页，大量翻页时必然超时。

```go
// ✅ 正确：每页独立 clone，超时互不影响（仅在 ctx 本身携带 deadline 时需要）
for {
    pageCtx := trpc.CloneContext(ctx)
    result, err := accessor.Query(pageCtx, req)
    // ...
}

// ❌ 错误：所有页共用同一个有超时的 ctx
for {
    result, err := accessor.Query(ctx, req)  // 第 N 页时剩余超时已被前 N-1 页消耗
    // ...
}
```

⚠️ **CloneContext 会断开取消信号！** 如果 ctx 可能被外部 cancel（如任务取消），翻页循环不能用 CloneContext，否则取消信令无法传播：

```go
// ❌ 危险：任务被取消后 cancelFunc() 被调用，但 pageCtx 完全感知不到
taskCtx, cancel := context.WithCancel(asyncCtx)
// ...
for {
    pageCtx := trpc.CloneContext(taskCtx) // 断开了取消链路！
    accessor.Query(pageCtx, ...)          // 任务取消了，ES 请求仍继续
}

// ✅ 正确：直接传 taskCtx，取消信号可以传播到 ES 请求
for {
    accessor.Query(taskCtx, ...)
    // 翻页超时由 ES client 的 Transport.ResponseHeaderTimeout 独立控制
}
```

**判断标准**：看 ctx 是否携带 **deadline/timeout**：
- 有 deadline → 可以考虑 CloneContext 防止翻页时超时累积
- 只有 cancel（无 deadline）→ **不要** CloneContext，否则取消信令失效

### 规则 2: 日志规范 — tRPC Log + 上下文字段

**统一使用 tRPC Log（`trpc.group/trpc-go/trpc-go/log`），所有日志必须携带 ctx。**

```go
import "trpc.group/trpc-go/trpc-go/log"

// ✅ 正确：携带 ctx 的日志（自动带上 TraceID + 链路字段）
log.InfoContextf(ctx, "export task created, task_id:%s", taskID)
log.ErrorContextf(ctx, "query storage failed, err:%+v", err)

// ❌ 错误：不带 ctx 的日志（丢失链路信息）
log.Infof("export task created")  // 无法关联到具体请求
```

**请求入口必须注入上下文字段（WithContextFields）：**

在 Handler/CLI 接口入口处，将本次请求的关键业务标识注入 ctx，后续所有下游日志自动携带：

```go
// ✅ 在 Handler 入口注入关键字段
func (h *ExportHandler) CreateExport(ctx context.Context, req *pb.CreateExportRequest) (*pb.CreateExportResponse, error) {
    // 注入本次请求的关键信息到 ctx，后续所有 log 自动携带
    ctx = log.WithContextFields(ctx,
        "project_id", req.ProjectId,
        "user", req.User,
        "task_type", "export",
    )

    log.InfoContextf(ctx, "create export request received")
    // 后续所有下游函数使用这个 ctx，日志自动带上 project_id/user/task_type
    return h.svc.CreateExport(ctx, req)
}
```

**WithContextFields 使用要点：**

| 要点 | 说明 |
|------|------|
| **注入位置** | Handler/CLI 入口，越早越好 |
| **关键字段** | 数据唯一 key、操作人、项目 ID、请求类型 |
| **传递方式** | 通过 ctx 自动传递到所有下游（service → dao → storage） |
| **日志效果** | 同一请求链路的所有日志都能被关联检索 |

### 规则 3: 监控统计 — tRPC Metrics

**使用 tRPC Metrics（`trpc.group/trpc-go/trpc-go/metrics`）进行监控统计上报。**

```go
import "trpc.group/trpc-go/trpc-go/metrics"

// ✅ 计数器：统计请求量
metrics.IncrCounter("export.create.total", 1)
metrics.IncrCounter("export.create."+projectID+".total", 1)

// ✅ 带维度的计数器
metrics.IncrCounter("task."+taskType+"."+status+".num", 1)

// ✅ 耗时统计
start := time.Now()
// ... 执行业务逻辑 ...
metrics.SetGauge("export.query.duration_ms", float64(time.Since(start).Milliseconds()))
```

**监控埋点规范：**

| 场景 | 指标名格式 | 示例 |
|------|-----------|------|
| 请求计数 | `{module}.{action}.total` | `export.create.total` |
| 按维度计数 | `{module}.{action}.{dim}.num` | `task.export.completed.num` |
| 错误计数 | `{module}.{action}.error` | `export.query.error` |
| 耗时 | `{module}.{action}.duration_ms` | `export.file_generate.duration_ms` |

### 规则 4: 卫语句 — 消除箭头代码

**使用卫语句（Guard Clause）提前返回，避免深层嵌套。**

```go
// ❌ 箭头代码：嵌套越来越深
func processOrder(ctx context.Context, order *Order) error {
    if order != nil {
        if order.IsValid() {
            if order.HasStock() {
                if err := order.Process(ctx); err != nil {
                    return err
                }
                return nil
            } else {
                return errors.New("库存不足")
            }
        } else {
            return errors.New("订单无效")
        }
    } else {
        return errors.New("订单为空")
    }
}

// ✅ 卫语句：扁平清晰
func processOrder(ctx context.Context, order *Order) error {
    if order == nil {
        return errors.New("订单为空")
    }
    if !order.IsValid() {
        return errors.New("订单无效")
    }
    if !order.HasStock() {
        return errors.New("库存不足")
    }
    return order.Process(ctx)
}
```

**原则：先处理异常路径，再执行正常逻辑。嵌套深度不超过 4 层。**

### 规则 5: 错误处理

遵循[腾讯 Go 规范](reference/tencent-go-standard.md)的错误处理要求：

```go
// ✅ 独立错误流，尽早返回
resp, err := client.Call(ctx, req)
if err != nil {
    return nil, fmt.Errorf("call service failed: %w", err)
}
// 正常逻辑继续

// ❌ 不要把错误判断和其他逻辑混合
x, y, err := f()
if err != nil || y == nil {  // 混合判断，有隐患
    return err
}

// ✅ 分开判断
x, y, err := f()
if err != nil {
    return fmt.Errorf("f failed: %w", err)
}
if y == nil {
    return errors.New("y is nil")
}
```

### 规则 6: 重试机制 — retry-go

**使用 [retry-go](https://github.com/avast/retry-go) 实现重试，不要手写重试循环。**

```go
import "github.com/avast/retry-go"

func (c *EventProcessor) processWithRetry(ctx context.Context, event *Event, retryCfg *RetryConfig) error {
    return retry.Do(
        func() error {
            return c.processEvent(ctx, event)
        },
        retry.Attempts(uint(retryCfg.RetryCount+1)),
        retry.Delay(time.Duration(retryCfg.RetryIntervalMs)*time.Millisecond),
        retry.LastErrorOnly(true),
        retry.OnRetry(func(n uint, err error) {
            log.InfoContextf(ctx, "处理事件重试(%d/%d)，事件ID: %s, 错误: %v",
                n, retryCfg.RetryCount, event.Id, err)
        }),
    )
}
```

**常用选项：**
| 选项 | 说明 |
|------|------|
| `retry.Attempts(n)` | 总尝试次数（含首次） |
| `retry.Delay(d)` | 重试间隔 |
| `retry.DelayType(retry.BackOffDelay)` | 指数退避 |
| `retry.LastErrorOnly(true)` | 只返回最后一次错误 |
| `retry.RetryIf(func(err error) bool)` | 条件重试 |
| `retry.Context(ctx)` | 支持 ctx 取消 |
| `retry.OnRetry(fn)` | 重试回调（记录日志） |

### 规则 7: 并发控制 — tRPC GoAndWait

**使用 tRPC 的 GoAndWait 进行并发任务管理，不要裸用 goroutine。**

```go
import "trpc.group/trpc-go/trpc-go"

// ✅ 使用 GoAndWait 并发执行多个独立任务
func (s *Service) GetDashboard(ctx context.Context, userID string) (*Dashboard, error) {
    var (
        user    *User
        orders  []*Order
        stats   *Stats
    )

    err := trpc.GoAndWait(
        func() error {
            var err error
            user, err = s.userRepo.FindByID(ctx, userID)
            return err
        },
        func() error {
            var err error
            orders, err = s.orderRepo.ListByUser(ctx, userID)
            return err
        },
        func() error {
            var err error
            stats, err = s.statsService.GetUserStats(ctx, userID)
            return err
        },
    )
    if err != nil {
        return nil, fmt.Errorf("获取仪表盘数据失败: %w", err)
    }

    return &Dashboard{User: user, Orders: orders, Stats: stats}, nil
}
```

**GoAndWait 特性：**
- 并发执行所有 handler，等待全部完成
- 任一 handler 返回错误，立即取消其他
- 自动 recover panic，避免 goroutine 泄漏

### 规则 8: 数据库使用 — tRPC GORM 插件

**优先使用 tRPC 的 GORM 插件，而非原生 gorm.Open。数据访问层目录用 `dao/`。**

```go
import (
    "trpc.group/trpc-go/trpc-database/gorm"
    "trpc.group/trpc-go/trpc-go/log"
)

// 初始化：通过 tRPC 插件方式
cli, err := gorm.NewClientProxy("trpc.mysql.server.service")  // 四级格式
if err != nil {
    panic(err)
}

// ✅ 必须使用 WithContext 携带 TraceID 和超时信息
// 文件位于 dao/user.go（不叫 dao/user_dao.go）
func (d *userDAO) FindByID(ctx context.Context, id int) (*User, error) {
    var user User
    if err := d.db.WithContext(ctx).Where("c_id = ?", id).First(&user).Error; err != nil {
        return nil, fmt.Errorf("query user failed: %w", err)
    }
    return &user, nil
}

// ✅ 复杂查询示例
func (r *OwnerRepository) ListByCondition(ctx context.Context, owner string, maxID int) ([]*Owner, error) {
    var owners []*Owner
    err := r.db.WithContext(ctx).
        Where("current_owners = ?", owner).
        Where("id < ?", maxID).
        Find(&owners).Error
    if err != nil {
        return nil, fmt.Errorf("list owners failed: %w", err)
    }
    return owners, nil
}
```

**GORM 单元测试 — 使用 sqlmock（与 [trpc-database/gorm 官方推荐](https://trpc.group/trpc-go/trpc-database/tree/master/gorm#单元测试) 一致）：**
```go
import (
    "github.com/DATA-DOG/go-sqlmock"
    "gorm.io/driver/mysql"
    "gorm.io/gorm"
)

func setupTestDB(t *testing.T) (*gorm.DB, sqlmock.Sqlmock) {
    db, mock, err := sqlmock.New()
    assert.NoError(t, err)

    gormDB, err := gorm.Open(mysql.New(mysql.Config{
        Conn:                      db,
        SkipInitializeWithVersion: true,
    }), &gorm.Config{})
    assert.NoError(t, err)

    return gormDB, mock
}
```

### 规则 9: 文件命名 — 不重复目录名

**文件名不应包含所在目录名作为后缀。包名已表达语义。**

```go
// ✅ 好：简洁，包名 + 文件名 = 完整语义
dao/project.go          → dao.NewProject(db)
dao/project_test.go
service/export.go       → service.NewExport(dao)
plugin/auth_check.go    → plugin.NewAuthCheck(dao)

// ❌ 坏：冗余
dao/project_dao.go
service/export_service.go
plugin/auth_check_plugin.go
store/project_store.go      // "store" 已被淘汰，用 "dao"
```

**数据访问层用 `dao/` 目录（不用 `store/`），与 `storage/`（存储抽象层）语义不冲突。**

### 规则 10: 方法命名 — 不重复类型名/服务名

**方法名不应包含其所属类型（struct/interface/service）已表达的语义。类型名是上下文，方法名只描述动作。**

此规则同时适用于 Go struct 方法、gRPC Service RPC 名、CLI 子命令。

```protobuf
// ✅ 好：Service 名已表达 "Export"，方法名只说动作
service ExportService {
  rpc Create(CreateExportReq) returns (CreateExportRsp);
  rpc GetStatus(GetExportStatusReq) returns (GetExportStatusRsp);
  rpc Preview(ExportPreviewReq) returns (ExportPreviewRsp);
}

// ❌ 坏：方法名重复了 Service 名中的 "Export"
service ExportService {
  rpc CreateExport(CreateExportReq) returns (CreateExportRsp);
  rpc GetExportStatus(GetExportStatusReq) returns (GetExportStatusRsp);
}
```

```go
// ✅ 好：类型名已表达语义
type TaskService struct { ... }
func (s *TaskService) List(ctx, ...)     // 调用：taskSvc.List()
func (s *TaskService) GetStatus(ctx, ...)
func (s *TaskService) Pause(ctx, ...)

// ❌ 坏：方法名重复了类型名
func (s *TaskService) ListTasks(ctx, ...)     // taskSvc.ListTasks() 啰嗦
func (s *TaskService) GetTaskStatus(ctx, ...)
func (s *TaskService) PauseTask(ctx, ...)
```

**注意**：Message 名（如 `CreateExportReq`、`ListTasksReq`）保持完整命名，因为 Message 是全局命名空间，没有 Service 上下文消歧。

**判断标准**：把 `类型名.方法名` 读出来，如果听起来有重复词（`ExportService.CreateExport`），就该去掉重复部分。

### 规则 11: DB 命名规范

**库名以 `d_` 开头，字段使用 `c_` 前缀，表名使用蛇形命名。表名以 `t_` 开头。**

```sql
-- 库名：d_ 前缀
CREATE DATABASE IF NOT EXISTS `d_flow_topology_def` DEFAULT CHARSET=utf8mb4;

-- 表定义
CREATE TABLE IF NOT EXISTS `flow_topology_def` (
  `c_id` int(11) NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `c_flow_topology_id` varchar(32) NOT NULL COMMENT '拓扑ID',
  `c_flow_type` varchar(32) NOT NULL COMMENT '流模板类型',
  `c_version` varchar(32) NOT NULL COMMENT '版本tag',
  `c_validation_rules` json DEFAULT NULL COMMENT '准入数据规则',
  `c_content_yaml` text NOT NULL COMMENT 'YAML 配置全文',
  `c_is_active` tinyint(1) DEFAULT '1' COMMENT '是否激活',
  `c_created_time` datetime DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `c_updated_time` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`c_id`),
  UNIQUE KEY `uk_xxx` (`c_field`),
  KEY `idx_xxx` (`c_field`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='表注释';
```

**命名规则：**
| 元素 | 规则 | 示例 |
|------|------|------|
| 库名 | `d_` 前缀 + 蛇形 | `d_flow_topology_def` |
| 表名 | 蛇形命名，业务前缀 | `flow_topology_def` |
| 字段 | `c_` 前缀 + 蛇形 | `c_flow_type` |
| 主键 | `c_id` | `c_id` |
| 时间 | `c_created_time` / `c_updated_time` | 带默认值 |
| 唯一索引 | `uk_` 前缀 | `uk_flow_topology_id` |
| 普通索引 | `idx_` 前缀 | `idx_event_bridge_id` |
| JSON 字段 | 允许 NULL | `c_validation_rules json DEFAULT NULL` |

### 规则 12: 缓存策略

**本地缓存 DB 数据有两种选择：**

| 方案 | 适用场景 | 特点 |
|------|---------|------|
| **tRPC localcache** | 单机缓存、低频变更数据 | 轻量、内存级、无网络开销 |
| **无极（Wuji）** | 分布式缓存、需要一致性 | 跨实例共享、自动失效 |

> 涉及本地缓存时，应主动询问用户选择 localcache 还是无极。

### 规则 13: 代码生成规范

#### 根据接口协议生成空实现

当服务有 protobuf 协议定义时，生成空的实现骨架：

```go
// 协议来源示例：github.com/mooyang-code/xData-mini/storage/proto/gen v1.1.10
// 生成的空实现应包含完整的方法签名和 TODO 注释

func (s *TrackerServiceImpl) TrackEvent(ctx context.Context, req *pb.TrackEventRequest) (*pb.TrackEventResponse, error) {
    // TODO: 实现业务逻辑
    return nil, errs.New(errs.RetServerSystemErr, "not implemented")
}
```

#### 生成运维工具和故障恢复接口

**每个服务都应该生成配套的 tools 和故障恢复接口：**
- 数据修复工具
- 状态检查接口
- 手动触发接口（用于故障恢复）
- 数据导出/导入工具

放置在项目的 `tools/` 目录下，或作为 CLI 子命令。

### 规则 14: 文档规范

**每个项目必须有完善的文档体系。**

#### docs/ 目录结构（必须）

```
docs/
├── design.md               # 系统设计文档
│   ├── 系统架构图
│   ├── 模块说明与数据流
│   ├── 核心术语表
│   └── 接口设计
├── user-guide.md            # 用户手册
│   ├── 快速开始
│   ├── CLI 命令参考（所有命令的用法、参数、示例）
│   ├── 完整工作流示例
│   └── FAQ
└── specs/                   # 模块详细规范（按需）
    └── <module>/
        ├── README.md        # 模块概述 + 架构
        └── step-XX-xxx.md   # 分步实现规范
```

#### README 必须包含

- 项目定位和架构概述
- 支持的业务类型
- 事件类型列表（如 one_click_film 的 13 种事件类型）
- **CLI 命令速查**（至少列出所有一级命令和典型用法）
- 完整工作流示例
- 部署要求和环境依赖

#### 代码变更同步规则

**代码变更时，必须同时更改：**
1. 相关的文档（README、设计文档、用户手册）
2. 单元测试代码
3. 如有接口变更，更新协议文件
4. 如有 CLI 变更，更新 CLI 命令参考

### 规则 15: CLI 设计规范

**每个项目必须提供 CLI 工具，遵循以下设计原则：**

```go
// CLI 入口：cmd/cli/main.go
// 命令组织：dm <resource> <action> [flags]

// ✅ 好的 CLI 设计
dm project list --user mooyang --output json
dm export create --project media_cover --filter '{"status":"active"}' --user mooyang
dm task get --task-id 12345

// ❌ 不好的设计
dm --do-export --project=media_cover  // 不要用扁平的 flag 替代子命令
```

**CLI 设计清单：**

| 要求 | 说明 |
|------|------|
| 结构化输出 | 默认 JSON，支持 `--output json/table/yaml` |
| 全局选项 | `--user`（必填）、`--output`、`--verbose`、`--help` |
| 子命令组织 | `dm <resource> <action>` 二级命令 |
| AI Agent 友好 | 无交互式输入，所有参数通过 flag 传递 |
| 错误输出 | 错误信息输出到 stderr，数据输出到 stdout |
| 帮助文档 | 每个命令必须有 `--help`、Usage 和 Examples |

---

## 内部组件优先

**必须使用 [trpc-database](reference/trpc-database.md) 生态组件，禁止在生产代码中直接使用裸的第三方库。**

| 需求 | ✅ 必须使用 | ❌ 禁止使用 |
|------|-----------|------------|
| MySQL/ORM | `trpc.group/trpc-go/trpc-database/gorm` | `gorm.io/driver/mysql` + `gorm.io/gorm` 直连 |
| MySQL/原生SQL | `trpc.group/trpc-go/trpc-database/mysql` | `database/sql` + `go-sql-driver/mysql` 直连 |
| Redis | `trpc.group/trpc-go/trpc-database/goredis` | `github.com/redis/go-redis` 直连 |
| Kafka | `trpc.group/trpc-go/trpc-database/kafka` | `github.com/IBM/sarama` 直连 |
| MongoDB | `trpc.group/trpc-go/trpc-database/mongodb` | `go.mongodb.org/mongo-driver` 直连 |
| 本地缓存 | `trpc.group/trpc-go/trpc-database/localcache` | 自建缓存 |
| ES | `trpc.group/trpc-go/trpc-database/es` | `github.com/elastic/go-elasticsearch` 直连 |
| ClickHouse | `trpc.group/trpc-go/trpc-database/gorm`（driver_name: clickhouse） | `clickhouse-go` 直连 |
| PostgreSQL | `trpc.group/trpc-go/trpc-database/gorm`（driver_name: postgres） | `gorm.io/driver/postgres` 直连 |
| etcd | `trpc.group/trpc-go/trpc-database/etcd` | `go.etcd.io/etcd/client` 直连 |

**例外：** 单元测试中按 trpc-database/gorm 官方推荐，使用 `sqlmock` + `gorm.Open(mysql.New(...))` 构造 mock DB。

**原因：** tRPC 组件自带监控上报、链路追踪、连接池管理、服务发现集成，裸用第三方库会丢失这些能力。

---

## 代码量化标准

| 指标 | 限制 | 来源 |
|------|------|------|
| 文件长度 | ≤ 800 行 | 腾讯 Go 规范 |
| 函数长度 | ≤ 80 行 | 腾讯 Go 规范 |
| 嵌套深度 | ≤ 4 层 | 腾讯 Go 规范 |
| 函数参数 | ≤ 5 个 | 腾讯 Go 规范 |
| 行宽 | ≤ 120 列 | 腾讯 Go 规范 |
| 测试文件 | ≤ 1600 行（2x） | 腾讯 Go 规范 |
| 测试函数 | ≤ 160 行（2x） | 腾讯 Go 规范 |

## Resources

- **[reference/tencent-go-standard.md](reference/tencent-go-standard.md)** — 腾讯 Go 编码规范完整版
- **[reference/trpc-database.md](reference/trpc-database.md)** — tRPC 数据库组件速查手册
- **[reference/trpc-patterns.md](reference/trpc-patterns.md)** — tRPC 常用模式详解
