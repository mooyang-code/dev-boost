# Go 架构模式对比

## 概述

本文档对比不同架构模式的优劣和适用场景,帮助选择合适的架构。

---

## 1. 简单分层架构（Layered Architecture）

### 结构

```
┌─────────────────────────────────┐
│  Handler 层（HTTP 处理）         │
├─────────────────────────────────┤
│  Service 层（业务逻辑）          │
├─────────────────────────────────┤
│  Repository 层（数据访问）       │
├─────────────────────────────────┤
│  Model 层（数据模型）            │
└─────────────────────────────────┘
```

### 目录结构

```
myapp/
├── handlers/
│   └── user_handler.go
├── services/
│   └── user_service.go
├── repositories/
│   └── user_repository.go
└── models/
    └── user.go
```

### 代码示例

```go
// models/user.go
package models

type User struct {
	ID    uint   `gorm:"primaryKey"`
	Name  string
	Email string `gorm:"uniqueIndex"`
}

// repositories/user_repository.go
package repositories

import (
	"gorm.io/gorm"  // 生产环境通过 trpc-database/gorm 插件获取 *gorm.DB
	"myapp/models"
)

type UserRepository struct {
	db *gorm.DB
}

func NewUserRepository(db *gorm.DB) *UserRepository {
	return &UserRepository{db: db}
}

func (r *UserRepository) Create(user *models.User) error {
	return r.db.Create(user).Error
}

func (r *UserRepository) FindByID(id uint) (*models.User, error) {
	var user models.User
	if err := r.db.First(&user, id).Error; err != nil {
		return nil, err
	}
	return &user, nil
}

// services/user_service.go
package services

import (
	"errors"
	"myapp/models"
	"myapp/repositories"
)

type UserService struct {
	repo *repositories.UserRepository
}

func NewUserService(repo *repositories.UserRepository) *UserService {
	return &UserService{repo: repo}
}

func (s *UserService) CreateUser(name, email string) (*models.User, error) {
	// 业务验证
	if email == "" {
		return nil, errors.New("邮箱不能为空")
	}

	user := &models.User{
		Name:  name,
		Email: email,
	}

	if err := s.repo.Create(user); err != nil {
		return nil, err
	}

	return user, nil
}

// handlers/user_handler.go
package handlers

import (
	"github.com/gin-gonic/gin"
	"myapp/services"
	"net/http"
)

type UserHandler struct {
	service *services.UserService
}

func NewUserHandler(service *services.UserService) *UserHandler {
	return &UserHandler{service: service}
}

func (h *UserHandler) CreateUser(c *gin.Context) {
	var req struct {
		Name  string `json:"name" binding:"required"`
		Email string `json:"email" binding:"required,email"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user, err := h.service.CreateUser(req.Name, req.Email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, user)
}
```

### 优劣分析

**优势**：
- ✅ 简单易懂，新手友好
- ✅ 快速开发
- ✅ 适合小型项目

**劣势**：
- ❌ 层间耦合紧密
- ❌ Model 贫血（只有数据，无行为）
- ❌ 业务逻辑分散在 Service 和 Handler
- ❌ 难以测试（依赖具体实现）

**适用场景**：
- CRUD 应用
- 原型开发
- 业务逻辑简单的项目

---

## 2. Clean Architecture（整洁架构）

### 结构

```
┌──────────────────────────────────────┐
│  框架 & 驱动（Web、DB、UI）          │
│  ┌────────────────────────────────┐  │
│  │  接口适配器（Controller、Repo） │  │
│  │  ┌──────────────────────────┐  │  │
│  │  │  用例（Use Cases）        │  │  │
│  │  │  ┌──────────────────┐    │  │  │
│  │  │  │  实体（Entities） │    │  │  │
│  │  │  └──────────────────┘    │  │  │
│  │  └──────────────────────────┘  │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘

依赖方向：从外向内
```

### 目录结构

```
myapp/
├── domain/              # 核心领域
│   ├── entities/
│   │   └── user.go
│   └── interfaces/      # 端口
│       └── user_repository.go
├── usecases/            # 用例
│   └── create_user.go
├── adapters/            # 适配器
│   ├── handlers/
│   │   └── user_handler.go
│   └── repositories/
│       └── postgres_user_repository.go
└── infrastructure/      # 基础设施
    ├── database/
    └── server/
```

### 代码示例

参见 `clean-architecture.md`

### 优劣分析

**优势**：
- ✅ 业务逻辑独立于框架
- ✅ 高可测试性
- ✅ 依赖倒置，易于替换实现
- ✅ 清晰的职责分离

**劣势**：
- ❌ 复杂度高，学习曲线陡
- ❌ 代码量大
- ❌ 过度工程（小项目）

**适用场景**：
- 大型企业应用
- 复杂业务逻辑
- 需要高测试覆盖率
- 长期维护的项目

---

## 3. Hexagonal Architecture（六边形架构）

### 结构

```
         输入适配器              核心              输出适配器

    ┌──────────────┐      ┌──────────┐      ┌──────────────┐
    │ HTTP Handler │─────▶│  用例     │─────▶│ PostgreSQL   │
    └──────────────┘      │  (端口)   │      │ Repository   │
                          └──────────┘      └──────────────┘
    ┌──────────────┐             │
    │ gRPC Server  │─────────────┘
    └──────────────┘
```

### 目录结构

```
myapp/
├── core/                # 应用核心
│   ├── domain/
│   ├── ports/
│   │   ├── input/       # 输入端口
│   │   └── output/      # 输出端口
│   └── services/        # 业务逻辑
└── adapters/            # 适配器
    ├── input/
    │   ├── http/
    │   └── grpc/
    └── output/
        ├── postgres/
        └── redis/
```

### 代码示例

参见 `hexagonal-architecture.md`

### 优劣分析

**优势**：
- ✅ 端口和适配器分离清晰
- ✅ 易于替换适配器
- ✅ 支持多种输入/输出方式
- ✅ 相比 Clean Architecture 更简洁

**劣势**：
- ❌ 仍需要较多代码
- ❌ 需要理解端口/适配器概念

**适用场景**：
- 需要支持多种协议（HTTP、gRPC、CLI）
- 需要支持多种数据源
- 微服务架构

---

## 4. DDD（领域驱动设计）

### 结构

```
┌─────────────────────────────────────┐
│  接口层（HTTP、gRPC）                │
├─────────────────────────────────────┤
│  应用层（用例、应用服务）            │
├─────────────────────────────────────┤
│  领域层（实体、值对象、聚合、服务）  │
├─────────────────────────────────────┤
│  基础设施层（仓储实现、外部服务）    │
└─────────────────────────────────────┘
```

### 目录结构

```
myapp/
├── domain/              # 领域层
│   ├── entities/
│   ├── value_objects/
│   ├── aggregates/
│   ├── services/
│   ├── repositories/    # 接口
│   └── events/
├── application/         # 应用层
│   └── services/
├── infrastructure/      # 基础设施层
│   ├── persistence/
│   └── messaging/
└── interfaces/          # 接口层
    └── http/
```

### 代码示例

参见 `ddd-patterns.md`

### 优劣分析

**优势**：
- ✅ 业务逻辑集中在领域层
- ✅ 富领域模型（实体包含行为）
- ✅ 统一语言
- ✅ 适合复杂业务

**劣势**：
- ❌ 学习曲线最陡
- ❌ 需要深入理解业务
- ❌ 代码量大
- ❌ 过度设计（简单场景）

**适用场景**：
- 复杂业务领域
- 需要与业务专家协作
- 长期演进的项目
- 微服务架构

---

## 5. 标准库风格（Go Kit / Standard Library）

### 结构

```
myapp/
├── cmd/
│   └── server/
│       └── main.go
├── internal/
│   ├── user/
│   │   ├── endpoint.go   # 端点
│   │   ├── service.go    # 服务接口
│   │   ├── transport.go  # 传输层
│   │   └── middleware.go # 中间件
│   └── order/
│       └── ...
└── pkg/
    └── ...
```

### 代码示例

```go
// internal/user/service.go
package user

import "context"

type Service interface {
	CreateUser(ctx context.Context, name, email string) (string, error)
	GetUser(ctx context.Context, id string) (*User, error)
}

type service struct {
	repo Repository
}

func NewService(repo Repository) Service {
	return &service{repo: repo}
}

func (s *service) CreateUser(ctx context.Context, name, email string) (string, error) {
	// 实现
	return "", nil
}

// internal/user/endpoint.go
package user

import (
	"context"
	"github.com/go-kit/kit/endpoint"
)

type CreateUserRequest struct {
	Name  string
	Email string
}

type CreateUserResponse struct {
	ID    string
	Error string
}

func MakeCreateUserEndpoint(s Service) endpoint.Endpoint {
	return func(ctx context.Context, request interface{}) (interface{}, error) {
		req := request.(CreateUserRequest)
		id, err := s.CreateUser(ctx, req.Name, req.Email)
		if err != nil {
			return CreateUserResponse{Error: err.Error()}, nil
		}
		return CreateUserResponse{ID: id}, nil
	}
}

// internal/user/transport.go
package user

import (
	"context"
	"encoding/json"
	"github.com/go-kit/kit/endpoint"
	"net/http"
)

func MakeHTTPHandler(endpoints Endpoints) http.Handler {
	mux := http.NewServeMux()

	mux.Handle("/users", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req CreateUserRequest
		json.NewDecoder(r.Body).Decode(&req)

		resp, _ := endpoints.CreateUser(r.Context(), req)

		json.NewEncoder(w).Encode(resp)
	}))

	return mux
}
```

### 优劣分析

**优势**：
- ✅ 符合 Go 惯用法
- ✅ 中间件机制强大
- ✅ 易于测试
- ✅ 微服务友好

**劣势**：
- ❌ 代码较多（Endpoint 层抽象）
- ❌ 对简单场景过于复杂

**适用场景**：
- 微服务架构
- 需要丰富的中间件（日志、监控、限流）
- gRPC + HTTP 双协议支持

---

## 架构对比总结

| 架构 | 复杂度 | 代码量 | 测试性 | 适用场景 | 学习曲线 |
|------|--------|--------|--------|----------|----------|
| **简单分层** | 低 | 少 | 中 | CRUD、小项目 | 低 |
| **Clean Architecture** | 高 | 多 | 高 | 大型应用、复杂业务 | 高 |
| **Hexagonal** | 中 | 中 | 高 | 多协议、微服务 | 中 |
| **DDD** | 最高 | 最多 | 高 | 复杂领域、长期项目 | 最高 |
| **Go Kit** | 中 | 多 | 高 | 微服务 | 中 |

---

## 架构选择建议

### 项目类型

```
简单 CRUD → 简单分层架构
中型 API 服务 → Hexagonal Architecture
大型企业应用 → Clean Architecture
复杂业务领域 → DDD
微服务 → Go Kit / Hexagonal
```

### 团队经验

```
新手团队 → 简单分层
有经验团队 → Hexagonal / Clean
深入理解业务 → DDD
```

### 业务复杂度

```
简单业务 → 简单分层
中等复杂 → Hexagonal
高度复杂 → DDD / Clean Architecture
```

---

## 演进路径

### 从简单到复杂

```
1. 简单分层（快速启动）
   ↓
2. 引入接口（提高测试性）
   ↓
3. Hexagonal（支持多协议）
   ↓
4. Clean Architecture（复杂业务）
   ↓
5. DDD（领域驱动）
```

### 推荐实践

1. **小项目**：从简单分层开始，按需演进
2. **中型项目**：直接使用 Hexagonal Architecture
3. **大型项目**：Clean Architecture 或 DDD
4. **微服务**：Hexagonal 或 Go Kit

---

## 混合架构

实际项目中，可以混合使用不同架构：

```go
myapp/
├── domain/              # DDD 领域层
│   ├── entities/
│   ├── value_objects/
│   └── aggregates/
├── usecases/            # Clean Architecture 用例层
│   └── create_order.go
├── adapters/            # Hexagonal 适配器
│   ├── http/
│   ├── grpc/
│   └── postgres/
└── pkg/                 # 通用工具
```

---

## 总结

- **没有银弹**：选择适合项目的架构
- **由简到繁**：从简单开始，逐步演进
- **业务驱动**：让业务复杂度决定架构复杂度
- **团队优先**：团队理解和维护比架构本身更重要
