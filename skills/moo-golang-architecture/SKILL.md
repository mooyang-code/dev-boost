---
name: moo-golang-architecture
description: 媒资组 Go 项目架构规范，基于 tRPC-Go 框架。涵盖三层架构（Handler→Service→DAO）、标准目录结构、tRPC-Go 服务初始化（blank import 清单、go.mod 版本、selector 配置错误排查）、README 章节规范。当设计新服务、搭建项目骨架、重构代码结构、解决启动 panic 时触发。
---

# Go 架构设计

基于 tRPC-Go 框架设计 Go Web 应用，**默认三层架构，按需演进，统一技术栈，避免过早优化**。

## 核心原则

### 1. 标准化布局

**遵循 cmd/internal/pkg 约定：**
- `cmd/` - 应用程序入口，只做依赖装配
- `internal/` - 私有代码，不可被外部导入
- `pkg/` - 公共代码，可被外部导入

### 2. 显式依赖注入

**在 main.go 中装配所有依赖：**
```go
// ✅ 好的实践：显式装配
func main() {
    db := initDB()
    userDAO := dao.NewUser(db)
    userService := service.NewUser(userDAO)
    userHandler := handler.NewUser(userService)
}

// ❌ 不好的实践：隐式依赖
func main() {
    handler.InitUser()  // 内部隐藏了依赖创建
}
```

### 3. 接口驱动

**在使用处定义接口，而非实现处：**
```go
// ✅ 在 Service 层定义需要的接口
type UserService struct {
    userDAO UserDAO  // Service 定义它需要什么
}

type UserDAO interface {
    FindByID(ctx context.Context, id string) (*User, error)
}

// ❌ 在 DAO 实现处定义接口
type IUserDAO interface { ... }  // 不推荐
type UserDAO struct { ... }
```

### 4. 分层清晰

```
Handler → Service → DAO → Database
  ↓         ↓        ↓
HTTP层   业务逻辑层  数据访问层
```

---

## 标准项目结构

```
myapp/
├── cmd/
│   ├── server/main.go          # tRPC 服务端入口
│   └── cli/main.go             # CLI 工具入口（每个项目必须有 CLI）
├── internal/
│   ├── handler/                # tRPC Handler 层（协议处理）
│   ├── service/                # 业务逻辑层
│   │   ├── project.go          # ← 文件名不重复目录名（不叫 project_service.go）
│   │   └── export.go
│   ├── dao/                    # 数据访问层（MySQL CRUD，使用 GORM）
│   │   ├── project.go          # ← 不叫 project_dao.go
│   │   ├── project_test.go
│   │   └── field.go
│   ├── engine/                 # 编排/引擎层（如工作流引擎）
│   ├── plugin/                 # 插件系统
│   │   ├── interfaces.go       # 插件接口定义
│   │   └── builtin/            # 内置插件实现
│   ├── storage/                # 存储抽象层（多数据源适配，如 ES/HBase）
│   │   ├── interfaces.go       # 统一接口
│   │   ├── registry.go         # 注册中心
│   │   └── es/                 # ES 适配器
│   ├── filter/                 # 通用筛选/DSL
│   └── model/                  # 数据模型
├── docs/                       # 文档（必须）
│   ├── design.md               # 系统设计文档
│   ├── user-guide.md           # 用户手册
│   └── specs/                  # 模块详细规范
├── schema/                     # 数据库 Schema（DDL）
│   └── schema.sql
├── config/                     # 配置文件
│   ├── trpc_go.yaml            # tRPC 配置
│   └── workflows/              # 工作流 YAML 定义
├── tools/                      # 运维工具 & 故障恢复脚本
├── go.mod
├── Makefile
└── README.md
```

### dao/ vs storage/ 职责区分

| 目录 | 职责 | 数据源 | 操作 |
|------|------|--------|------|
| `dao/` | 平台自身元数据的 CRUD | MySQL（GORM） | 项目、字段、任务、权限等管理表 |
| `storage/` | 业务数据源的统一查询抽象 | ES / MySQL / HBase 等 | Query、Count、GetByIDs |

**dao** = 对 MySQL 管理表做增删改查，**storage** = 对用户业务数据做跨存储类型的查询适配。两者职责不重叠。

### 文件命名规则

**文件名不重复所在目录名。** 包名已表达语义，文件名只需表达「哪个实体」：

```go
// ✅ 好：包名 + 文件名 = 完整语义
dao/project.go        → dao.NewProject(db)
service/export.go     → service.NewExport(dao)
plugin/auth_check.go  → plugin.NewAuthCheck(dao)

// ❌ 坏：文件名与目录名重复
dao/project_dao.go          → 冗余
service/export_service.go   → 冗余
plugin/auth_check_plugin.go → 冗余
```

### 目录规范要求

| 目录/文件 | 必须 | 说明 |
|----------|------|------|
| `cmd/cli/` | ✅ | **每个项目必须有 CLI 工具**，AI Agent 友好，输出结构化 JSON |
| `cmd/server/` | ✅ | tRPC 服务端入口 |
| `docs/` | ✅ | 至少包含设计文档和用户手册 |
| `docs/design.md` | ✅ | 系统设计文档：架构图、模块说明、数据流 |
| `docs/user-guide.md` | ✅ | 用户手册：使用方法、命令示例、完整工作流 |
| `schema/` | ✅ | 所有 DDL 集中管理 |
| `tools/` | 推荐 | 运维工具、数据修复、故障恢复 |
| `README.md` | ✅ | 见下方「README 规范」 |

### CLI 设计原则

```
dm                              # 项目名作为命令名
├── project       项目管理
├── export        数据导出
├── task          任务管理
└── ...

设计要点：
- 所有输出为结构化 JSON（--output json/table/yaml）
- 全局选项：--user, --output, --verbose
- 子命令式组织：dm <resource> <action> [flags]
- AI Agent 可直接调用，无需交互式输入
```

---

## tRPC-Go 服务初始化

### 推荐引入的公开组件

```go
import (
    "github.com/mooyang-code/go-commlib/trpc-database/timer"
    _ "github.com/mooyang-code/go-commlib/trpc-filter/cors"
    _ "go.uber.org/automaxprocs"
    _ "trpc.group/trpc-go/trpc-filter/validation"
    "trpc.group/trpc-go/trpc-go"
    "trpc.group/trpc-go/trpc-go/log"
)
```

**日志**：用 `trpc.group/trpc-go/trpc-go/log`，不用标准库 `"log"`。公开项目按需引入 CORS、validation、localcache、timer 等组件；不要引用私有依赖。

### go.mod 版本要求

| 依赖 | 最低版本 | 说明 |
|------|---------|------|
| `trpc.group/trpc-go/trpc-go` | v1.0.3 | tRPC-Go 主框架 |
| `trpc.group/trpc-go/trpc-filter/validation` | v1.0.1 | 参数校验 |
| `trpc.group/trpc-go/trpc-database/localcache` | v1.0.0 | 本地缓存 |
| `github.com/mooyang-code/go-commlib/trpc-filter/cors` | v0.0.1 | CORS filter |
| `github.com/mooyang-code/go-commlib/trpc-database/timer` | v0.0.2 | 本地/服务内定时任务 |
| `github.com/tencent/goom` | v1.0.6 | 单元测试 mock |

### trpc_go.yaml ↔ blank import 对应关系

| yaml 节点 | 对应 blank import |
|---|---|
| `server.filter: validation` | `trpc-filter/validation` |
| `server.filter: cors` | `github.com/mooyang-code/go-commlib/trpc-filter/cors` |
| `client.service.target: ip://...` / `dsn://...` | tRPC-Go 内置 selector |
| `timer` 服务 | `github.com/mooyang-code/go-commlib/trpc-database/timer` |

### DB client service name 命名

yaml 中 `client.service.name` 与代码中 `tgorm.NewClientProxy("...")` 必须完全一致：

```yaml
# trpc_go.yaml
client:
  service:
    - name: trpc.mysql.{服务名}
      target: dsn://user:pass@tcp(127.0.0.1:3306)/dbname?parseTime=True&loc=Local
```

```go
// main.go
db, err := gorm.Open(mysql.Open(dsn), &gorm.Config{})
```

> 公开项目优先使用标准 Go SDK、GORM 直连或 tRPC-Go 内置 selector；不要依赖内网服务发现 scheme。

### 常见启动 panic 排查

#### `selector ... not exist`

```
panic: failed to setup client: client: selector xxx not exist
```

**原因**：配置里引用了项目未安装的 selector/filter，或从私有环境模板迁移后仍保留了专用 scheme。

**修复**：
```bash
go get trpc.group/trpc-go/trpc-go@v1.0.3
go mod tidy
```

#### `selector dsn not exist`

检查是否引用了项目未安装的 selector/filter，或仍保留了私有环境专用的 私有服务发现 scheme。

**参考项目**：`github.com/mooyang-code/xData-mini/storage` 的 `main.go` 与 `trpc_go.yaml`。

---

## README 规范

**每个项目必须在根目录生成 `README.md`**，结构固定、内容精准、与代码保持一致。

### 必须包含的章节（按顺序）

```markdown
# 项目名称
> 一句话定位

项目背景段落（2-4 句）

## Features      # 已实现能力，emoji + 加粗标题 + 破折号
## Requirements  # 运行依赖版本，用表格
## Project Structure  # 目录树 + 注释，depth=2~3 层
## Quick Start   # 初始化DB → 修改配置 → 编译 → 启动 → 使用示例
## Architecture  # ASCII 架构图 + 数据流说明，不超过 30 行
## Configuration # 关键配置字段，YAML 示例
## Contributing  # 提交前检查事项
## License       # 内部项目填版权声明
```

### 各章节写作规范

**Features**：只写已实现功能，格式 `- 🔥 **标题** — 说明文字`

**Requirements**：用表格：
```markdown
| 依赖 | 版本要求 |
|------|---------|
| Go   | 1.21 +  |
| MySQL | 8.0 +  |
```

**Architecture**：优先用 ASCII 图，图后配数据流说明（3~5 步）：
```
┌─────────┐      tRPC      ┌─────────────┐
│  CLI    │ ─────────────▶ │   Server    │
└─────────┘                │ Handler     │
                           │ Service     │
                           │ DAO         │
                           └──────┬──────┘
                                  │
                            MySQL / ES / COS
```

**Contributing**（固定 4 条）：
1. `go vet ./...` 和 `go test ./...` 均通过
2. 新增功能附带单元测试
3. 接口变更需同步更新 proto 文件
4. Commit message 遵循团队规范（见 `moo-git-commit` skill）

### 禁止项

| 禁止 | 原因 |
|------|------|
| 写未实现的功能 | 误导使用者 |
| 用 badge（徽章） | 内部项目无 CI 公网链接 |
| 章节顺序随意 | 统一阅读习惯 |
| Quick Start 缺编译步骤 | 使用者无法运行 |
| Architecture 只有文字没有图 | 不直观 |

---

## 架构模式

**默认使用三层架构（Handler → Service → DAO），绝大多数项目够用。**

只有当项目复杂度明确超出三层架构承载能力时，再考虑演进：

| 信号 | 演进方向 | 参考 |
|------|---------|------|
| 需要支持多种协议/数据源 | 引入端口和适配器 | [hexagonal-architecture.md](./reference/hexagonal-architecture.md) |
| 业务逻辑复杂，需要强隔离 | 分离领域层 | [clean-architecture.md](./reference/clean-architecture.md) |
| 复杂业务领域建模 | DDD 战术模式 | [ddd-patterns.md](./reference/ddd-patterns.md) |

> **原则：从简单开始，按需演进。不要过早引入复杂架构。**

---

## 核心实现模式

### 三层架构示例

```go
// 1. Handler 层：处理 tRPC 请求
func (h *UserHandler) CreateUser(ctx context.Context, req *pb.CreateUserRequest) (*pb.CreateUserResponse, error) {
    user, err := h.userService.Create(ctx, req)
    if err != nil {
        return nil, err
    }
    return &pb.CreateUserResponse{User: user}, nil
}

// 2. Service 层：业务逻辑
func (s *userService) Create(ctx context.Context, req *pb.CreateUserRequest) (*model.User, error) {
    if existing, _ := s.userDAO.FindByEmail(ctx, req.Email); existing != nil {
        return nil, errs.New(errs.RetServerBadRequest, "邮箱已存在")
    }
    user := &model.User{ID: uuid.New().String(), Email: req.Email}
    return s.userDAO.Save(ctx, user)
}

// 3. DAO 层：数据访问
func (d *userDAO) Save(ctx context.Context, user *model.User) (*model.User, error) {
    if err := d.db.WithContext(ctx).Create(user).Error; err != nil {
        return nil, fmt.Errorf("save user failed: %w", err)
    }
    return user, nil
}
```

### 依赖注入（main.go 装配）

```go
func main() {
    s := trpc.NewServer()

    db, err := tgorm.NewClientProxy("trpc.mysql.gorm.myapp")
    if err != nil {
        panic(err)
    }

    userDAO := dao.NewUser(db)
    userService := service.NewUser(userDAO)
    pb.RegisterUserServiceHandlerServer(s, handler.NewUser(userService))

    if err := s.Serve(); err != nil {
        log.Fatal(err)
    }
}
```

### 配置管理（本地 YAML）

```go
func New() (*Config, error) {
    b, err := os.ReadFile("config/service.yaml")
    if err != nil {
        return nil, fmt.Errorf("load service.yaml failed: %w", err)
    }
    c := &Config{}
    if err = yaml.Unmarshal(b, c); err != nil {
        return nil, err
    }
    log.InfoContextf(trpc.BackgroundContext(), "load conf succ")
    return c, nil
}
```

---

## 技术栈速查

| 层次 | 组件 | 说明 |
|------|------|------|
| **框架** | tRPC-Go | RPC + HTTP 统一框架 |
| **配置** | 本地 YAML / 环境变量 | 与 `xData-mini/storage` 一致，启动时加载 |
| **日志** | tRPC Log | 上下文传递 + 链路追踪 |
| **数据库** | GORM / sqlite / duckdb / rocksdb | 按项目场景选择 |
| **缓存** | `trpc-database/localcache` / 项目缓存封装 | 本地缓存优先 |
| **服务寻址** | `ip://` / `dns://` / `dsn://` | 公开组件直连或 DNS |
| **公共组件** | `github.com/mooyang-code/go-commlib` | CORS、timer、open-wuji、tinyfunc 等 |

公开项目优先复用项目内封装和公开组件；直接使用第三方库时要统一管理 ctx、超时、日志、连接池和错误处理。

---

## 常见陷阱

### 过早优化架构

❌ 简单 CRUD 应用用 Clean Architecture → 增加不必要复杂性
✅ 从三层开始，复杂度增加时再按需演进

### 贫血模型

```go
// ❌ 业务规则散落在 Service，模型只有数据
user.IsActive = false

// ✅ 领域行为内聚在模型中
user.Deactivate()  // 内部校验当前状态
```

### 框架标签泄漏到业务层

```go
// ❌ GORM 标签出现在领域模型
type User struct {
    ID string `gorm:"primaryKey"`
}

// ✅ 数据模型与领域模型分离
// model/user.go       — 纯领域模型
// dao/user_model.go   — 含 gorm tag 的 DB 模型
```

---

## 最佳实践

1. **从三层开始**：不要过早引入复杂架构
2. **接口在使用侧定义**：让使用者定义接口，而不是实现者
3. **显式依赖注入**：在 main.go 中手动装配依赖
4. **保持层次清晰**：单向依赖，避免循环依赖
5. **文档先行**：架构决策要有 `docs/design.md`

## Resources

- **[reference/architecture.md](./reference/architecture.md)**: 架构模式对比（按需查阅）
- **[reference/patterns.md](./reference/patterns.md)**: Go 设计模式
- **[reference/tech-stack.md](./reference/tech-stack.md)**: 技术栈选型对比
