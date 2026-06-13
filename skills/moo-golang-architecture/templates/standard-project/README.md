# Go 标准项目模板

基于 tRPC-Go 框架的标准 Go Web 项目模板，使用 Handler → Service → Repository 三层架构。

## 技术栈

- **框架**：tRPC-Go（RPC + HTTP 双协议支持）
- **配置**：本地 YAML / 环境变量
- **日志**：tRPC Log（上下文传递 + 链路追踪）
- **ORM**：GORM
- **数据库**：MySQL
- **缓存**：Redis（可选）

## 目录结构

```
standard-project/
├── cmd/
│   └── server/
│       └── main.go           # 应用入口，依赖装配
├── internal/
│   ├── handlers/             # HTTP/RPC 处理器
│   │   └── user_handler.go
│   ├── services/             # 业务逻辑层
│   │   └── user_service.go
│   ├── repositories/         # 数据访问层
│   │   └── user_repository.go
│   ├── models/               # 数据模型
│   │   └── user.go
│   └── logic/                # 业务逻辑实现（tRPC 风格）
│       └── user_logic.go
├── pkg/
│   ├── conf/                 # 配置管理（本地 YAML）
│   │   └── conf.go
│   ├── database/             # 数据库连接
│   │   └── database.go
│   └── response/             # 统一响应格式
│       └── response.go
├── trpc_go.yaml              # tRPC 框架配置
├── service.yaml              # 业务配置
├── go.mod
├── go.sum
├── Makefile                  # 构建脚本
└── README.md                 # 本文件
```

## 快速开始

### 1. 安装依赖

```bash
go mod download
```

### 2. 配置文件

#### trpc_go.yaml（框架配置）

```yaml
global:
  namespace: Development
  env_name: test

server:
  app: your-app
  server: your-server
  service:
    - name: trpc.app.server.Service
      network: tcp
      protocol: trpc
      ip: 0.0.0.0
      port: 8000
```

#### service.yaml（业务配置）

```yaml
server:
  app: your-app
  server: your-server

database:
  host: localhost
  port: 3306
  user: root
  password: your_password
  dbname: your_database
  charset: utf8mb4

redis:
  addr: localhost:6379
  password: ""
  db: 0
```

### 3. 运行应用

```bash
# 开发模式
go run cmd/server/main.go

# 或使用 Makefile
make run
```

### 4. 测试 API

```bash
# HTTP 接口（tRPC 自动映射）
curl -X POST http://localhost:8000/trpc.app.server.Service/CreateUser \
  -H "Content-Type: application/json" \
  -d '{"name":"张三","email":"zhangsan@example.com"}'

# 获取用户
curl http://localhost:8000/trpc.app.server.Service/GetUser?id=1
```

## Makefile 命令

```bash
make run          # 运行应用
make build        # 编译应用
make test         # 运行测试
make clean        # 清理编译文件
make lint         # 代码检查
```

## 核心代码示例

### 1. 配置管理（pkg/conf/conf.go）

```go
package conf

import (
    "os"

    "gopkg.in/yaml.v2"
    "trpc.group/trpc-go/trpc-go/log"
)

type Config struct {
    Server   ServerConfig   `yaml:"server"`
    Database DatabaseConfig `yaml:"database"`
    Redis    RedisConfig    `yaml:"redis"`
}

type DatabaseConfig struct {
    Host     string `yaml:"host"`
    Port     int    `yaml:"port"`
    User     string `yaml:"user"`
    Password string `yaml:"password"`
    DBName   string `yaml:"dbname"`
    Charset  string `yaml:"charset"`
}

func New() (*Config, error) {
    // 从本地 YAML 加载，部署时可用环境变量选择不同配置文件。
    data, err := os.ReadFile("service.yaml")
    if err != nil {
        return nil, err
    }

    c := &Config{}
    if err = yaml.Unmarshal(data, c); err != nil {
        return nil, err
    }

    log.Info("load conf succ")
    return c, nil
}
```

### 2. 主函数（cmd/server/main.go）

```go
package main

import (
    "trpc.group/trpc-go/trpc-go"
    "trpc.group/trpc-go/trpc-go/log"

    "your-project/internal/logic"
    "your-project/pkg/conf"
    "your-project/pkg/database"
    pb "github.com/mooyang-code/your-project/proto/gen"
)

func main() {
    // 1. 加载配置
    cfg, err := conf.New()
    if err != nil {
        log.Fatalf("load config failed: %v", err)
    }

    // 2. 初始化数据库
    db, err := database.InitDB(cfg.Database)
    if err != nil {
        log.Fatalf("init database failed: %v", err)
    }

    // 3. 依赖注入
    userRepo := repositories.NewUserRepository(db)
    userService := services.NewUserService(userRepo)
    userLogic := logic.NewUserLogic(userService, cfg)

    // 4. 注册服务
    s := trpc.NewServer()
    pb.RegisterServiceService(s, userLogic)

    // 5. 启动服务
    if err := s.Serve(); err != nil {
        log.Fatalf("server serve failed: %v", err)
    }
}
```

### 3. 业务逻辑层（internal/logic/user_logic.go）

```go
package logic

import (
    "context"

    "trpc.group/trpc-go/trpc-go/log"

    "your-project/internal/services"
    pb "github.com/mooyang-code/your-project/proto/gen"
)

type UserLogic struct {
    userService services.UserService
}

func NewUserLogic(userService services.UserService) *UserLogic {
    return &UserLogic{
        userService: userService,
    }
}

func (l *UserLogic) CreateUser(ctx context.Context, req *pb.CreateUserRequest) (*pb.CreateUserResponse, error) {
    log.InfoContextf(ctx, "CreateUser called, name:%s, email:%s", req.Name, req.Email)

    user, err := l.userService.CreateUser(ctx, req.Name, req.Email)
    if err != nil {
        log.ErrorContextf(ctx, "create user failed: %v", err)
        return nil, err
    }

    return &pb.CreateUserResponse{
        User: &pb.User{
            Id:    user.ID,
            Name:  user.Name,
            Email: user.Email,
        },
    }, nil
}
```

## 项目特性

- ✅ tRPC-Go 框架（RPC + HTTP 双协议）
- ✅ 标准三层架构
- ✅ 依赖注入（手动装配）
- ✅ tRPC Config 配置管理（支持配置中心、热更新）
- ✅ tRPC Log 日志（上下文传递、链路追踪）
- ✅ 统一错误处理
- ✅ 统一响应格式
- ✅ MySQL + GORM 数据访问
- ✅ 优雅关闭

## 扩展建议

### 添加新功能

1. 定义 protobuf 接口（.proto 文件）
2. 使用 trpc 工具生成桩代码
3. 在 `internal/models/` 创建数据模型
4. 在 `internal/repositories/` 创建仓储
5. 在 `internal/services/` 创建服务
6. 在 `internal/logic/` 实现 tRPC 接口
7. 在 `main.go` 注册服务

### 添加单元测试

```go
// internal/services/user_service_test.go
package services

import (
    "context"
    "testing"

    "github.com/tencent/goom"
    "github.com/stretchr/testify/assert"

    "your-project/internal/models"
    "your-project/internal/repositories"
)

func TestUserService_CreateUser_ValidInput_ShouldReturnUser(t *testing.T) {
    // 测试场景：创建用户时传入有效参数应成功返回用户信息

    // 1. 准备数据
    expectedUser := &models.User{
        ID:    1,
        Name:  "张三",
        Email: "zhangsan@example.com",
    }

    // 2. 创建 Mock
    mock := mocker.Create()
    defer mock.Reset()

    repo := (repositories.UserRepository)(nil)
    mock.Interface(&repo).Method("Create").Apply(
        func(_ *mocker.IContext, ctx context.Context, user *models.User) error {
            user.ID = expectedUser.ID
            return nil
        },
    )

    // 3. 创建被测对象
    service := NewUserService(repo)

    // 4. 执行测试
    ctx := context.Background()
    user, err := service.CreateUser(ctx, "张三", "zhangsan@example.com")

    // 5. 验证结果
    assert.NoError(t, err)
    assert.NotNil(t, user)
    assert.Equal(t, expectedUser.ID, user.ID)
    assert.Equal(t, expectedUser.Name, user.Name)
}
```

### 运行单元测试

```bash
# Go < 1.23
go test -gcflags=all=-l -v ./...

# Go >= 1.23
go test -gcflags="all=-N -l" -ldflags=-checklinkname=0 -v ./...

# 查看覆盖率
go test -gcflags="all=-N -l" -ldflags=-checklinkname=0 -v -cover ./...
```

### 迁移到 Clean Architecture

如果项目复杂度增加，可以按以下步骤迁移：

1. 创建 `domain/` 目录，定义领域模型和接口
2. 将 Service 改为实现领域接口
3. 创建 `usecases/` 目录
4. 将 Repository 接口移到 `domain/`
5. 重构代码，建立依赖倒置

## 并发处理

tRPC-Go 提供了优雅的并发工具：

```go
import "trpc.group/trpc-go/trpc-go"

// 并发执行多个任务
handlers := []func() error{
    func() error { return task1() },
    func() error { return task2() },
    func() error { return task3() },
}

// 等待所有任务完成，任一失败则返回错误
if err := trpc.GoAndWait(handlers...); err != nil {
    log.ErrorContextf(ctx, "tasks failed: %v", err)
    return err
}
```

## 日志最佳实践

```go
import "trpc.group/trpc-go/trpc-go/log"

// ✅ 推荐：带上下文的日志（支持链路追踪）
log.InfoContextf(ctx, "user created, userID:%d", userID)
log.ErrorContextf(ctx, "db query failed, err:%+v", err)

// ✅ 结构化日志
log.InfoContext(ctx, "request processed",
    log.Field("userID", userID),
    log.Field("latency", latency),
    log.Field("status", status))

// ❌ 避免：不带上下文的日志
log.Info("user created")  // 缺少链路追踪信息
```

## 许可

供团队内部使用。
