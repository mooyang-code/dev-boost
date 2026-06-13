# Clean Architecture（整洁架构）

## 概述

Clean Architecture 是 Robert C. Martin（Uncle Bob）提出的软件架构模式，核心思想是**将业务逻辑与框架、UI、数据库等外部细节分离**。

## 核心原则

### 1. 依赖规则

**依赖方向始终向内指向**：

```
外层依赖内层，内层不知道外层的存在

┌──────────────────────────────────────┐
│  框架 & 驱动（Web、DB、UI）          │  ← 最外层
│  ┌────────────────────────────────┐  │
│  │  接口适配器（Controller、Gateway）│  │
│  │  ┌──────────────────────────┐  │  │
│  │  │  用例（Use Cases）        │  │  │
│  │  │  ┌──────────────────┐    │  │  │
│  │  │  │  实体（Entities） │    │  │  │  ← 最内层
│  │  │  └──────────────────┘    │  │  │
│  │  └──────────────────────────┘  │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
```

### 2. 四层架构

| 层次 | 职责 | 示例 |
|------|------|------|
| **实体层（Entities）** | 核心业务规则和模型 | User、Order、Product |
| **用例层（Use Cases）** | 应用业务规则 | CreateUser、PlaceOrder |
| **接口适配器层** | 转换数据格式 | HTTP Handler、Repository |
| **框架层** | 外部工具和框架 | Gin、GORM、Redis |

---

## Go 语言实现

### 目录结构

```
app/
├── domain/              # 实体层（最核心）
│   ├── entities/
│   │   ├── user.go
│   │   └── order.go
│   ├── value_objects/
│   │   ├── email.go
│   │   └── money.go
│   └── interfaces/      # 领域接口（端口）
│       ├── user_repository.go
│       └── payment_gateway.go
├── usecases/            # 用例层
│   ├── create_user.go
│   └── place_order.go
├── adapters/            # 适配器层
│   ├── handlers/        # HTTP 适配器
│   │   └── user_handler.go
│   ├── repositories/    # 数据库适配器
│   │   └── postgres_user_repository.go
│   └── gateways/        # 外部服务适配器
│       └── stripe_payment_gateway.go
└── infrastructure/      # 框架层
    ├── database/
    ├── server/
    └── config/
```

---

## 实现示例

### 1. 实体层（Entities）

实体层包含核心业务逻辑，**不依赖任何框架和外部库**。

```go
// domain/entities/user.go
package entities

import (
    "errors"
    "time"
)

// User 用户实体（核心业务模型）
type User struct {
    id        string
    email     string
    name      string
    isActive  bool
    createdAt time.Time
}

// NewUser 创建新用户（工厂方法）
func NewUser(id, email, name string) (*User, error) {
    if email == "" {
        return nil, errors.New("邮箱不能为空")
    }
    if name == "" {
        return nil, errors.New("姓名不能为空")
    }

    return &User{
        id:        id,
        email:     email,
        name:      name,
        isActive:  true,
        createdAt: time.Now(),
    }, nil
}

// ID 获取用户 ID
func (u *User) ID() string {
    return u.id
}

// Email 获取邮箱
func (u *User) Email() string {
    return u.email
}

// Name 获取姓名
func (u *User) Name() string {
    return u.name
}

// IsActive 是否激活
func (u *User) IsActive() bool {
    return u.isActive
}

// Deactivate 停用用户（业务规则）
func (u *User) Deactivate() {
    u.isActive = false
}

// Activate 激活用户（业务规则）
func (u *User) Activate() {
    u.isActive = true
}

// CanPlaceOrder 是否可以下单（业务规则）
func (u *User) CanPlaceOrder() bool {
    return u.isActive
}
```

### 2. 领域接口（Ports）

在领域层定义接口，由外层实现（依赖倒置）。

```go
// domain/interfaces/user_repository.go
package interfaces

import (
    "context"
    "myapp/domain/entities"
)

// UserRepository 用户仓储接口（端口）
type UserRepository interface {
    FindByID(ctx context.Context, id string) (*entities.User, error)
    FindByEmail(ctx context.Context, email string) (*entities.User, error)
    Save(ctx context.Context, user *entities.User) error
    Update(ctx context.Context, user *entities.User) error
    Delete(ctx context.Context, id string) error
}
```

### 3. 用例层（Use Cases）

用例层编排业务流程，依赖领域接口。

```go
// usecases/create_user.go
package usecases

import (
    "context"
    "errors"

    "myapp/domain/entities"
    "myapp/domain/interfaces"
    "github.com/google/uuid"
)

// CreateUserRequest 创建用户请求
type CreateUserRequest struct {
    Email string
    Name  string
}

// CreateUserResponse 创建用户响应
type CreateUserResponse struct {
    UserID  string
    Success bool
    Error   string
}

// CreateUserUseCase 创建用户用例
type CreateUserUseCase struct {
    userRepo interfaces.UserRepository
}

// NewCreateUserUseCase 创建用例实例
func NewCreateUserUseCase(repo interfaces.UserRepository) *CreateUserUseCase {
    return &CreateUserUseCase{
        userRepo: repo,
    }
}

// Execute 执行用例
func (uc *CreateUserUseCase) Execute(ctx context.Context, req CreateUserRequest) CreateUserResponse {
    // 1. 业务验证：检查邮箱是否已存在
    existing, err := uc.userRepo.FindByEmail(ctx, req.Email)
    if err != nil {
        return CreateUserResponse{Success: false, Error: "查询失败"}
    }
    if existing != nil {
        return CreateUserResponse{Success: false, Error: "邮箱已存在"}
    }

    // 2. 创建实体（领域逻辑）
    user, err := entities.NewUser(
        uuid.New().String(),
        req.Email,
        req.Name,
    )
    if err != nil {
        return CreateUserResponse{Success: false, Error: err.Error()}
    }

    // 3. 持久化
    if err := uc.userRepo.Save(ctx, user); err != nil {
        return CreateUserResponse{Success: false, Error: "保存失败"}
    }

    return CreateUserResponse{
        UserID:  user.ID(),
        Success: true,
    }
}
```

### 4. 适配器层（Adapters）

#### HTTP 适配器（Controller）

```go
// adapters/handlers/user_handler.go
package handlers

import (
    "net/http"

    "github.com/gin-gonic/gin"
    "myapp/usecases"
)

// UserHandler 用户 HTTP 处理器
type UserHandler struct {
    createUserUseCase *usecases.CreateUserUseCase
}

// NewUserHandler 创建处理器
func NewUserHandler(createUserUseCase *usecases.CreateUserUseCase) *UserHandler {
    return &UserHandler{
        createUserUseCase: createUserUseCase,
    }
}

// CreateUser 创建用户端点
func (h *UserHandler) CreateUser(c *gin.Context) {
    // 1. 解析请求
    var input struct {
        Email string `json:"email" binding:"required,email"`
        Name  string `json:"name" binding:"required"`
    }

    if err := c.ShouldBindJSON(&input); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
        return
    }

    // 2. 调用用例
    req := usecases.CreateUserRequest{
        Email: input.Email,
        Name:  input.Name,
    }

    resp := h.createUserUseCase.Execute(c.Request.Context(), req)

    // 3. 返回响应
    if !resp.Success {
        c.JSON(http.StatusBadRequest, gin.H{"error": resp.Error})
        return
    }

    c.JSON(http.StatusCreated, gin.H{
        "user_id": resp.UserID,
    })
}
```

#### 数据库适配器（Repository Implementation）

```go
// adapters/repositories/postgres_user_repository.go
package repositories

import (
    "context"
    "errors"

    "gorm.io/gorm"  // 生产环境通过 trpc-database/gorm 插件获取 *gorm.DB
    "myapp/domain/interfaces"
)

// postgresUserRepository PostgreSQL 用户仓储实现
type postgresUserRepository struct {
    db *gorm.DB
}

// NewPostgresUserRepository 创建 PostgreSQL 仓储
func NewPostgresUserRepository(db *gorm.DB) interfaces.UserRepository {
    return &postgresUserRepository{db: db}
}

// userModel 数据库模型（与实体分离）
type userModel struct {
    ID        string `gorm:"primaryKey"`
    Email     string `gorm:"uniqueIndex"`
    Name      string
    IsActive  bool
    CreatedAt time.Time
}

// FindByID 根据 ID 查找
func (r *postgresUserRepository) FindByID(ctx context.Context, id string) (*entities.User, error) {
    var model userModel
    if err := r.db.WithContext(ctx).First(&model, "id = ?", id).Error; err != nil {
        if errors.Is(err, gorm.ErrRecordNotFound) {
            return nil, nil
        }
        return nil, err
    }

    return r.toEntity(&model), nil
}

// FindByEmail 根据邮箱查找
func (r *postgresUserRepository) FindByEmail(ctx context.Context, email string) (*entities.User, error) {
    var model userModel
    if err := r.db.WithContext(ctx).Where("email = ?", email).First(&model).Error; err != nil {
        if errors.Is(err, gorm.ErrRecordNotFound) {
            return nil, nil
        }
        return nil, err
    }

    return r.toEntity(&model), nil
}

// Save 保存用户
func (r *postgresUserRepository) Save(ctx context.Context, user *entities.User) error {
    model := r.toModel(user)
    return r.db.WithContext(ctx).Create(model).Error
}

// toEntity 转换为实体
func (r *postgresUserRepository) toEntity(m *userModel) *entities.User {
    user, _ := entities.NewUser(m.ID, m.Email, m.Name)
    if !m.IsActive {
        user.Deactivate()
    }
    return user
}

// toModel 转换为模型
func (r *postgresUserRepository) toModel(u *entities.User) *userModel {
    return &userModel{
        ID:       u.ID(),
        Email:    u.Email(),
        Name:     u.Name(),
        IsActive: u.IsActive(),
    }
}
```

### 5. 依赖装配（main.go）

```go
// cmd/app/main.go
package main

import (
    "myapp/adapters/handlers"
    "myapp/adapters/repositories"
    "myapp/infrastructure/database"
    "myapp/infrastructure/server"
    "myapp/usecases"
)

func main() {
    // 1. 初始化基础设施
    db := database.NewPostgres(config.Database)

    // 2. 初始化适配器（实现端口）
    userRepo := repositories.NewPostgresUserRepository(db)

    // 3. 初始化用例（注入依赖）
    createUserUseCase := usecases.NewCreateUserUseCase(userRepo)

    // 4. 初始化 HTTP 处理器
    userHandler := handlers.NewUserHandler(createUserUseCase)

    // 5. 启动服务器
    srv := server.New(userHandler)
    srv.Run()
}
```

---

## 优势

### 1. 独立于框架
业务逻辑不依赖 Gin、GORM 等框架，可以随时更换。

### 2. 可测试性
每一层都可以独立测试，不需要数据库或 HTTP 服务器。

```go
// usecases/create_user_test.go
func TestCreateUserUseCase_Execute(t *testing.T) {
    // 使用 Mock Repository（不需要真实数据库）
    mockRepo := &MockUserRepository{}
    useCase := NewCreateUserUseCase(mockRepo)

    req := CreateUserRequest{
        Email: "test@example.com",
        Name:  "Test User",
    }

    resp := useCase.Execute(context.Background(), req)

    assert.True(t, resp.Success)
    assert.NotEmpty(t, resp.UserID)
}
```

### 3. 业务逻辑集中
所有核心业务规则都在 `domain` 层，易于理解和维护。

### 4. 易于替换实现
可以轻松切换数据库、HTTP 框架等外部依赖。

---

## 何时使用

### 适合场景
- ✅ 复杂业务逻辑
- ✅ 长期维护的项目
- ✅ 需要高测试覆盖率
- ✅ 多种数据源或外部服务
- ✅ 微服务架构

### 不适合场景
- ❌ 简单 CRUD 应用
- ❌ 快速原型开发
- ❌ 小型工具脚本
- ❌ 业务规则极少的项目

---

## 常见陷阱

### 1. 贫血模型（Anemic Model）

```go
// ❌ 错误：只有数据，没有行为
type User struct {
    ID       string
    Email    string
    IsActive bool
}

// ✅ 正确：富领域模型，包含业务行为
type User struct {
    id       string
    email    string
    isActive bool
}

func (u *User) Deactivate() {
    u.isActive = false
}

func (u *User) CanPlaceOrder() bool {
    return u.isActive
}
```

### 2. 框架泄漏

```go
// ❌ 错误：实体依赖 GORM
type User struct {
    ID    string `gorm:"primaryKey"`
    Email string `gorm:"uniqueIndex"`
}

// ✅ 正确：实体纯净，数据库标签在适配器层
// domain/entities/user.go
type User struct {
    id    string
    email string
}

// adapters/repositories/user_model.go
type userModel struct {
    ID    string `gorm:"primaryKey"`
    Email string `gorm:"uniqueIndex"`
}
```

### 3. 过度工程

对于简单的 CRUD 应用，不需要 Clean Architecture，使用简单的分层即可。

---

## 总结

Clean Architecture 通过依赖倒置原则，将业务逻辑与外部细节分离，提高了代码的可测试性、可维护性和灵活性。适合复杂业务场景，但不要过度使用。
