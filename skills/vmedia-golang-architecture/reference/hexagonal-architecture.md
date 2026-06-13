# Hexagonal Architecture（六边形架构）

## 概述

六边形架构（Hexagonal Architecture），也称为**端口和适配器架构**（Ports and Adapters），由 Alistair Cockburn 提出。核心思想是**将应用程序核心与外部世界隔离**。

## 核心概念

### 架构图

```
         外部世界（适配器）           应用程序核心（端口）

    ┌─────────────────┐            ┌──────────────────┐
    │  HTTP Handler   │───────────▶│  Input Port      │
    └─────────────────┘            │  (Use Case)      │
                                   └──────────────────┘
    ┌─────────────────┐                    │
    │   gRPC Server   │────────────────────┘
    └─────────────────┘
                                           │
                                           ▼
                                   ┌──────────────────┐
                                   │  Business Logic  │
                                   │  (Domain)        │
                                   └──────────────────┘
                                           │
                                           ▼
    ┌─────────────────┐            ┌──────────────────┐
    │  PostgreSQL     │◀───────────│  Output Port     │
    │  Repository     │            │  (Interface)     │
    └─────────────────┘            └──────────────────┘

    ┌─────────────────┐                    │
    │  Redis Cache    │────────────────────┘
    └─────────────────┘
```

### 关键术语

| 术语 | 说明 | 示例 |
|------|------|------|
| **端口（Port）** | 应用程序对外暴露的接口 | UserService 接口 |
| **适配器（Adapter）** | 实现端口的具体组件 | HTTP Handler、PostgreSQL Repository |
| **输入端口（Input Port）** | 应用程序接收外部请求的接口 | CreateUserUseCase |
| **输出端口（Output Port）** | 应用程序调用外部服务的接口 | UserRepository、EmailSender |
| **输入适配器** | 调用输入端口的组件 | HTTP Handler、gRPC Server、CLI |
| **输出适配器** | 实现输出端口的组件 | PostgreSQL Repo、Redis Cache、SMTP |

---

## Go 语言实现

### 目录结构

```
myapp/
├── cmd/
│   └── server/
│       └── main.go           # 依赖装配
├── internal/
│   ├── core/                 # 应用核心（端口）
│   │   ├── domain/           # 领域模型
│   │   │   ├── user.go
│   │   │   └── order.go
│   │   ├── ports/            # 端口定义
│   │   │   ├── input/        # 输入端口
│   │   │   │   └── user_service.go
│   │   │   └── output/       # 输出端口
│   │   │       ├── user_repository.go
│   │   │       └── email_sender.go
│   │   └── services/         # 业务逻辑（实现输入端口）
│   │       └── user_service.go
│   └── adapters/             # 适配器
│       ├── input/            # 输入适配器
│       │   ├── http/
│       │   │   └── user_handler.go
│       │   └── grpc/
│       │       └── user_server.go
│       └── output/           # 输出适配器
│           ├── postgres/
│           │   └── user_repository.go
│           └── smtp/
│               └── email_sender.go
└── pkg/
    ├── config/
    └── logger/
```

---

## 完整实现示例

### 1. 领域模型（Domain）

```go
// internal/core/domain/user.go
package domain

import (
	"errors"
	"time"
)

// User 用户领域模型
type User struct {
	id        string
	email     string
	name      string
	createdAt time.Time
}

// NewUser 创建用户
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
		createdAt: time.Now(),
	}, nil
}

// Getters
func (u *User) ID() string        { return u.id }
func (u *User) Email() string     { return u.email }
func (u *User) Name() string      { return u.name }
func (u *User) CreatedAt() time.Time { return u.createdAt }
```

### 2. 输入端口（Input Port）

```go
// internal/core/ports/input/user_service.go
package input

import (
	"context"
	"myapp/internal/core/domain"
)

// CreateUserRequest 创建用户请求
type CreateUserRequest struct {
	Email string
	Name  string
}

// CreateUserResponse 创建用户响应
type CreateUserResponse struct {
	UserID string
}

// UserService 用户服务（输入端口）
type UserService interface {
	CreateUser(ctx context.Context, req CreateUserRequest) (*CreateUserResponse, error)
	GetUser(ctx context.Context, id string) (*domain.User, error)
}
```

### 3. 输出端口（Output Port）

```go
// internal/core/ports/output/user_repository.go
package output

import (
	"context"
	"myapp/internal/core/domain"
)

// UserRepository 用户仓储（输出端口）
type UserRepository interface {
	Save(ctx context.Context, user *domain.User) error
	FindByID(ctx context.Context, id string) (*domain.User, error)
	FindByEmail(ctx context.Context, email string) (*domain.User, error)
}
```

```go
// internal/core/ports/output/email_sender.go
package output

import "context"

// EmailSender 邮件发送器（输出端口）
type EmailSender interface {
	SendWelcomeEmail(ctx context.Context, email, name string) error
}
```

### 4. 业务逻辑（Service）

```go
// internal/core/services/user_service.go
package services

import (
	"context"
	"errors"

	"github.com/google/uuid"
	"myapp/internal/core/domain"
	"myapp/internal/core/ports/input"
	"myapp/internal/core/ports/output"
)

// userService 用户服务实现（实现输入端口）
type userService struct {
	userRepo    output.UserRepository
	emailSender output.EmailSender
}

// NewUserService 创建用户服务
func NewUserService(
	userRepo output.UserRepository,
	emailSender output.EmailSender,
) input.UserService {
	return &userService{
		userRepo:    userRepo,
		emailSender: emailSender,
	}
}

// CreateUser 创建用户
func (s *userService) CreateUser(ctx context.Context, req input.CreateUserRequest) (*input.CreateUserResponse, error) {
	// 1. 检查邮箱是否存在
	existing, err := s.userRepo.FindByEmail(ctx, req.Email)
	if err != nil {
		return nil, err
	}
	if existing != nil {
		return nil, errors.New("邮箱已存在")
	}

	// 2. 创建领域模型
	user, err := domain.NewUser(
		uuid.New().String(),
		req.Email,
		req.Name,
	)
	if err != nil {
		return nil, err
	}

	// 3. 保存用户
	if err := s.userRepo.Save(ctx, user); err != nil {
		return nil, err
	}

	// 4. 发送欢迎邮件（异步处理，错误不影响主流程）
	go func() {
		_ = s.emailSender.SendWelcomeEmail(context.Background(), user.Email(), user.Name())
	}()

	return &input.CreateUserResponse{
		UserID: user.ID(),
	}, nil
}

// GetUser 获取用户
func (s *userService) GetUser(ctx context.Context, id string) (*domain.User, error) {
	return s.userRepo.FindByID(ctx, id)
}
```

### 5. 输入适配器 - HTTP Handler

```go
// internal/adapters/input/http/user_handler.go
package http

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"myapp/internal/core/ports/input"
)

// UserHandler HTTP 处理器（输入适配器）
type UserHandler struct {
	userService input.UserService
}

// NewUserHandler 创建 HTTP 处理器
func NewUserHandler(userService input.UserService) *UserHandler {
	return &UserHandler{
		userService: userService,
	}
}

// CreateUser 创建用户端点
func (h *UserHandler) CreateUser(c *gin.Context) {
	var req struct {
		Email string `json:"email" binding:"required,email"`
		Name  string `json:"name" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	resp, err := h.userService.CreateUser(c.Request.Context(), input.CreateUserRequest{
		Email: req.Email,
		Name:  req.Name,
	})

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"user_id": resp.UserID,
	})
}

// GetUser 获取用户端点
func (h *UserHandler) GetUser(c *gin.Context) {
	id := c.Param("id")

	user, err := h.userService.GetUser(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"id":    user.ID(),
		"email": user.Email(),
		"name":  user.Name(),
	})
}
```

### 6. 输出适配器 - PostgreSQL Repository

```go
// internal/adapters/output/postgres/user_repository.go
package postgres

import (
	"context"
	"errors"

	"gorm.io/gorm"  // 生产环境通过 trpc-database/gorm 插件获取 *gorm.DB
	"myapp/internal/core/ports/output"
)

// userRepository PostgreSQL 仓储实现（输出适配器）
type userRepository struct {
	db *gorm.DB
}

// NewUserRepository 创建 PostgreSQL 仓储
func NewUserRepository(db *gorm.DB) output.UserRepository {
	return &userRepository{db: db}
}

// userModel 数据库模型
type userModel struct {
	ID        string `gorm:"primaryKey"`
	Email     string `gorm:"uniqueIndex"`
	Name      string
	CreatedAt int64
}

func (userModel) TableName() string {
	return "users"
}

// Save 保存用户
func (r *userRepository) Save(ctx context.Context, user *domain.User) error {
	model := &userModel{
		ID:        user.ID(),
		Email:     user.Email(),
		Name:      user.Name(),
		CreatedAt: user.CreatedAt().Unix(),
	}
	return r.db.WithContext(ctx).Create(model).Error
}

// FindByID 根据 ID 查找
func (r *userRepository) FindByID(ctx context.Context, id string) (*domain.User, error) {
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
func (r *userRepository) FindByEmail(ctx context.Context, email string) (*domain.User, error) {
	var model userModel
	if err := r.db.WithContext(ctx).Where("email = ?", email).First(&model).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return r.toEntity(&model), nil
}

// toEntity 转换为领域实体
func (r *userRepository) toEntity(m *userModel) *domain.User {
	user, _ := domain.NewUser(m.ID, m.Email, m.Name)
	return user
}
```

### 7. 输出适配器 - SMTP Email Sender

```go
// internal/adapters/output/smtp/email_sender.go
package smtp

import (
	"context"
	"fmt"
	"net/smtp"

	"myapp/internal/core/ports/output"
)

// emailSender SMTP 邮件发送器（输出适配器）
type emailSender struct {
	host     string
	port     int
	username string
	password string
	from     string
}

// NewEmailSender 创建邮件发送器
func NewEmailSender(host string, port int, username, password, from string) output.EmailSender {
	return &emailSender{
		host:     host,
		port:     port,
		username: username,
		password: password,
		from:     from,
	}
}

// SendWelcomeEmail 发送欢迎邮件
func (s *emailSender) SendWelcomeEmail(ctx context.Context, email, name string) error {
	auth := smtp.PlainAuth("", s.username, s.password, s.host)

	subject := "欢迎加入"
	body := fmt.Sprintf("你好 %s，欢迎加入我们的平台！", name)
	message := fmt.Sprintf("Subject: %s\r\n\r\n%s", subject, body)

	addr := fmt.Sprintf("%s:%d", s.host, s.port)
	return smtp.SendMail(addr, auth, s.from, []string{email}, []byte(message))
}
```

### 8. 依赖装配（main.go）

```go
// cmd/server/main.go
package main

import (
	"log"

	"github.com/gin-gonic/gin"
	"gorm.io/driver/postgres"  // 示例用 postgres；生产环境应通过 trpc-database/gorm 插件初始化
	"gorm.io/gorm"  // 生产环境通过 trpc-database/gorm 插件获取 *gorm.DB
	postgresAdapter "myapp/internal/adapters/output/postgres"
	smtpAdapter "myapp/internal/adapters/output/smtp"
	"myapp/internal/core/services"
)

func main() {
	// 1. 初始化数据库
	db, err := gorm.Open(postgres.Open("postgres://user:pass@localhost/db"), &gorm.Config{})
	if err != nil {
		log.Fatal(err)
	}

	// 2. 初始化输出适配器（实现输出端口）
	userRepo := postgresAdapter.NewUserRepository(db)
	emailSender := smtpAdapter.NewEmailSender("smtp.gmail.com", 587, "user", "pass", "noreply@example.com")

	// 3. 初始化服务（实现输入端口）
	userService := services.NewUserService(userRepo, emailSender)

	// 4. 初始化输入适配器
	userHandler := httpAdapter.NewUserHandler(userService)

	// 5. 配置路由
	router := gin.Default()
	router.POST("/users", userHandler.CreateUser)
	router.GET("/users/:id", userHandler.GetUser)

	// 6. 启动服务器
	if err := router.Run(":8080"); err != nil {
		log.Fatal(err)
	}
}
```

---

## 优势

### 1. 可测试性

每个组件都可以独立测试，使用 Mock 替代适配器。

```go
// internal/core/services/user_service_test.go
func TestUserService_CreateUser(t *testing.T) {
	// Mock 输出端口
	mockRepo := &MockUserRepository{}
	mockEmailSender := &MockEmailSender{}

	// 创建服务
	service := services.NewUserService(mockRepo, mockEmailSender)

	// 测试
	req := input.CreateUserRequest{
		Email: "test@example.com",
		Name:  "Test User",
	}

	resp, err := service.CreateUser(context.Background(), req)

	assert.NoError(t, err)
	assert.NotEmpty(t, resp.UserID)
}
```

### 2. 易于替换

可以轻松替换适配器，不影响核心业务逻辑。

```go
// 从 PostgreSQL 切换到 MongoDB
mongoRepo := mongoAdapter.NewUserRepository(mongoClient)
userService := services.NewUserService(mongoRepo, emailSender)

// 从 HTTP 切换到 gRPC
grpcServer := grpcAdapter.NewUserServer(userService)
```

### 3. 依赖倒置

核心业务逻辑不依赖外部框架，外部框架依赖核心。

```
❌ 错误：业务逻辑依赖 GORM
Service → GORM

✅ 正确：GORM 实现仓储接口
Service → Repository Interface ← PostgreSQL Adapter (使用 GORM)
```

---

## 与 Clean Architecture 的对比

| 特性 | Hexagonal Architecture | Clean Architecture |
|------|------------------------|---------------------|
| **核心思想** | 端口和适配器分离 | 依赖规则（向内依赖） |
| **层次结构** | 核心 + 适配器（2 层） | 实体 + 用例 + 适配器 + 框架（4 层） |
| **复杂度** | 相对简单 | 更细粒度的分层 |
| **适用场景** | 中小型项目 | 大型复杂项目 |
| **Go 实践** | 更常见 | 适合 DDD 场景 |

---

## 何时使用

### 适合场景
- ✅ 需要支持多种输入方式（HTTP、gRPC、CLI）
- ✅ 需要支持多种输出方式（PostgreSQL、MongoDB、Redis）
- ✅ 需要高测试覆盖率
- ✅ 业务逻辑需要独立于框架
- ✅ 微服务架构

### 不适合场景
- ❌ 简单 CRUD 应用
- ❌ 原型开发
- ❌ 业务逻辑极少的项目

---

## 总结

六边形架构通过**端口和适配器**将业务逻辑与外部世界隔离，提高了代码的可测试性、可维护性和灵活性。相比 Clean Architecture 更简洁，更适合 Go 语言的工程实践。
