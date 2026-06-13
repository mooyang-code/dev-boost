# Go 技术栈选型

## 概述

本文档对比 Go 生态中常用的技术栈，帮助选择合适的工具和框架。

---

## HTTP 框架

### 1. Gin

**特点**：高性能、生态丰富、易上手

**优势**：
- ✅ 性能优秀（基于 httprouter）
- ✅ 中间件生态完善
- ✅ 路由分组、参数绑定、验证等功能齐全
- ✅ 文档完善，社区活跃

**劣势**：
- ❌ 过度依赖 Context，不符合标准库风格
- ❌ 错误处理不够优雅

**使用场景**：中小型 Web 应用、API 服务

```go
package main

import (
	"github.com/gin-gonic/gin"
	"net/http"
)

func main() {
	r := gin.Default()

	// 路由分组
	api := r.Group("/api/v1")
	{
		api.GET("/users/:id", func(c *gin.Context) {
			id := c.Param("id")
			c.JSON(http.StatusOK, gin.H{"id": id})
		})

		api.POST("/users", func(c *gin.Context) {
			var user struct {
				Name  string `json:"name" binding:"required"`
				Email string `json:"email" binding:"required,email"`
			}

			if err := c.ShouldBindJSON(&user); err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
				return
			}

			c.JSON(http.StatusCreated, user)
		})
	}

	r.Run(":8080")
}
```

---

### 2. Echo

**特点**：高性能、极简设计

**优势**：
- ✅ 性能与 Gin 相当
- ✅ 标准化的中间件接口
- ✅ 内置数据绑定和验证
- ✅ 自动 TLS、HTTP/2 支持

**劣势**：
- ❌ 社区规模不如 Gin
- ❌ 第三方中间件较少

**使用场景**：追求极致性能的 API 服务

```go
package main

import (
	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
	"net/http"
)

func main() {
	e := echo.New()

	// 中间件
	e.Use(middleware.Logger())
	e.Use(middleware.Recover())

	// 路由
	e.GET("/users/:id", func(c echo.Context) error {
		id := c.Param("id")
		return c.JSON(http.StatusOK, map[string]string{"id": id})
	})

	e.Start(":8080")
}
```

---

### 3. Chi

**特点**：轻量级、符合标准库风格

**优势**：
- ✅ 基于 `net/http`，无额外抽象
- ✅ 路由性能优秀
- ✅ 符合 Go 惯用法
- ✅ 中间件与标准库兼容

**劣势**：
- ❌ 功能相对简单，需要自己实现更多功能
- ❌ 缺少内置验证、绑定等功能

**使用场景**：追求简洁、标准化的项目

```go
package main

import (
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"net/http"
)

func main() {
	r := chi.NewRouter()

	// 中间件
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	// 路由
	r.Route("/api/v1", func(r chi.Router) {
		r.Get("/users/{id}", func(w http.ResponseWriter, r *http.Request) {
			id := chi.URLParam(r, "id")
			w.Write([]byte("User ID: " + id))
		})
	})

	http.ListenAndServe(":8080", r)
}
```

---

### 4. 标准库（net/http）

**特点**：零依赖、完全控制

**优势**：
- ✅ 无外部依赖
- ✅ 最大灵活性
- ✅ 性能稳定

**劣势**：
- ❌ 路由功能弱（Go 1.22+ 改进）
- ❌ 需要手动实现中间件、验证等功能

**使用场景**：微服务、追求零依赖的项目

```go
package main

import "net/http"

func main() {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /users/{id}", func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id") // Go 1.22+
		w.Write([]byte("User ID: " + id))
	})

	http.ListenAndServe(":8080", mux)
}
```

---

## ORM / 数据库库

### 1. GORM

**特点**：功能全面、易用性高

**优势**：
- ✅ 功能丰富（关联、事务、钩子、迁移）
- ✅ 自动迁移
- ✅ 插件生态完善
- ✅ 支持多种数据库

**劣势**：
- ❌ 性能相对较低
- ❌ 抽象层过厚，难以优化 SQL
- ❌ 魔法操作较多，调试困难

**使用场景**：快速开发、复杂关联查询

```go
package main

import (
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

type User struct {
	ID    uint   `gorm:"primaryKey"`
	Name  string
	Email string `gorm:"uniqueIndex"`
}

func main() {
	db, _ := gorm.Open(postgres.Open("dsn"), &gorm.Config{})

	// 自动迁移
	db.AutoMigrate(&User{})

	// 创建
	db.Create(&User{Name: "Alice", Email: "alice@example.com"})

	// 查询
	var user User
	db.First(&user, 1)
	db.Where("email = ?", "alice@example.com").First(&user)

	// 更新
	db.Model(&user).Update("Name", "Bob")

	// 删除
	db.Delete(&user)
}
```

---

### 2. sqlx

**特点**：轻量级、保留 SQL 控制权

**优势**：
- ✅ 扩展标准库 `database/sql`
- ✅ 结构体扫描
- ✅ 命名参数
- ✅ 性能优秀

**劣势**：
- ❌ 需要手写 SQL
- ❌ 无迁移、关联等高级功能

**使用场景**：性能敏感、需要精细控制 SQL

```go
package main

import (
	"github.com/jmoiron/sqlx"
	_ "github.com/lib/pq"
)

type User struct {
	ID    int    `db:"id"`
	Name  string `db:"name"`
	Email string `db:"email"`
}

func main() {
	db, _ := sqlx.Connect("postgres", "dsn")

	// 查询单条
	var user User
	db.Get(&user, "SELECT * FROM users WHERE id = $1", 1)

	// 查询多条
	var users []User
	db.Select(&users, "SELECT * FROM users WHERE name LIKE $1", "A%")

	// 命名参数
	db.NamedExec("INSERT INTO users (name, email) VALUES (:name, :email)",
		map[string]interface{}{"name": "Alice", "email": "alice@example.com"})
}
```

---

### 3. ent

**特点**：类型安全、代码生成

**优势**：
- ✅ 强类型、编译时检查
- ✅ 自动生成 CRUD 代码
- ✅ 图查询（GraphQL 友好）
- ✅ 迁移管理

**劣势**：
- ❌ 学习曲线陡峭
- ❌ 代码生成增加复杂性
- ❌ 生态相对较新

**使用场景**：大型项目、GraphQL 应用

```go
package main

import (
	"context"
	"myapp/ent"
	"myapp/ent/user"

	_ "github.com/lib/pq"
)

func main() {
	client, _ := ent.Open("postgres", "dsn")
	defer client.Close()

	ctx := context.Background()

	// 创建
	u, _ := client.User.
		Create().
		SetName("Alice").
		SetEmail("alice@example.com").
		Save(ctx)

	// 查询
	users, _ := client.User.
		Query().
		Where(user.NameHasPrefix("A")).
		All(ctx)

	// 更新
	client.User.
		UpdateOneID(u.ID).
		SetName("Bob").
		Save(ctx)

	// 删除
	client.User.DeleteOneID(u.ID).Exec(ctx)
}
```

---

## 配置管理

### 1. Viper

**特点**：功能全面、多格式支持

**优势**：
- ✅ 支持 JSON、YAML、TOML、ENV 等
- ✅ 配置文件热加载
- ✅ 远程配置（etcd、Consul）
- ✅ 环境变量绑定

**使用场景**：复杂配置需求

```go
package main

import (
	"github.com/spf13/viper"
	"log"
)

func main() {
	viper.SetConfigName("config")
	viper.SetConfigType("yaml")
	viper.AddConfigPath(".")

	if err := viper.ReadInConfig(); err != nil {
		log.Fatal(err)
	}

	// 读取配置
	host := viper.GetString("server.host")
	port := viper.GetInt("server.port")

	// 环境变量
	viper.AutomaticEnv()
	dbHost := viper.GetString("DB_HOST")
}
```

---

### 2. envconfig

**特点**：极简、只支持环境变量

**优势**：
- ✅ 零配置文件，符合 12-Factor App
- ✅ 结构体标签映射
- ✅ 类型安全

**使用场景**：云原生、容器化应用

```go
package main

import (
	"github.com/kelseyhightower/envconfig"
	"log"
)

type Config struct {
	ServerHost string `envconfig:"SERVER_HOST" default:"localhost"`
	ServerPort int    `envconfig:"SERVER_PORT" default:"8080"`
	DBHost     string `envconfig:"DB_HOST" required:"true"`
}

func main() {
	var cfg Config
	if err := envconfig.Process("", &cfg); err != nil {
		log.Fatal(err)
	}

	// 使用 cfg.ServerHost, cfg.ServerPort, cfg.DBHost
}
```

---

## 日志库

### 1. zap

**特点**：高性能、结构化

**优势**：
- ✅ 性能最优（零分配）
- ✅ 结构化日志
- ✅ 多种输出格式

**使用场景**：高性能要求

```go
package main

import (
	"go.uber.org/zap"
)

func main() {
	logger, _ := zap.NewProduction()
	defer logger.Sync()

	logger.Info("User login",
		zap.String("user_id", "123"),
		zap.Int("attempt", 1),
	)
}
```

---

### 2. logrus

**特点**：功能丰富、易用

**优势**：
- ✅ 结构化日志
- ✅ 钩子机制（Hooks）
- ✅ 多种格式化器

**使用场景**：通用日志需求

```go
package main

import (
	"github.com/sirupsen/logrus"
)

func main() {
	log := logrus.New()
	log.SetFormatter(&logrus.JSONFormatter{})

	log.WithFields(logrus.Fields{
		"user_id": "123",
		"action":  "login",
	}).Info("User action")
}
```

---

### 3. slog（标准库，Go 1.21+）

**特点**：官方标准、零依赖

**优势**：
- ✅ 标准库，无外部依赖
- ✅ 结构化日志
- ✅ 性能优秀

**使用场景**：Go 1.21+ 新项目

```go
package main

import (
	"log/slog"
	"os"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	logger.Info("User login",
		"user_id", "123",
		"attempt", 1,
	)
}
```

---

## 依赖注入

### 1. Wire（Google）

**特点**：编译时代码生成

**优势**：
- ✅ 编译时检查
- ✅ 无运行时反射
- ✅ 生成可读代码

**使用场景**：大型项目

```go
//go:build wireinject

package main

import (
	"github.com/google/wire"
)

func InitializeApp() (*App, error) {
	wire.Build(
		NewDatabase,
		NewUserRepository,
		NewUserService,
		NewUserHandler,
		NewApp,
	)
	return &App{}, nil
}
```

---

### 2. fx（Uber）

**特点**：运行时依赖注入

**优势**：
- ✅ 自动生命周期管理
- ✅ 灵活的依赖图
- ✅ 支持并发启动

**使用场景**：微服务、需要生命周期管理

```go
package main

import (
	"go.uber.org/fx"
)

func main() {
	fx.New(
		fx.Provide(
			NewDatabase,
			NewUserRepository,
			NewUserService,
		),
		fx.Invoke(RunServer),
	).Run()
}
```

---

## 测试库

### 1. testify

**特点**：断言 + Mock

**优势**：
- ✅ 丰富的断言
- ✅ Mock 生成工具
- ✅ Suite 支持

```go
package main

import (
	"github.com/stretchr/testify/assert"
	"testing"
)

func TestAdd(t *testing.T) {
	result := Add(1, 2)
	assert.Equal(t, 3, result)
	assert.NotNil(t, result)
}
```

---

### 2. mocker（腾讯自研）

**特点**：接口和函数 Mock

**优势**：
- ✅ 支持接口和函数 Mock
- ✅ 类型安全
- ✅ 无需代码生成

```go
package main

import (
	"github.com/tencent/goom"
	"testing"
)

func TestUserService(t *testing.T) {
	mock := mocker.Create()
	defer mock.Reset()

	var userRepo UserRepository
	mock.Interface(&userRepo).Method("FindByID").Apply(
		func(_ *mocker.IContext, id string) (*User, error) {
			return &User{ID: id}, nil
		},
	)

	service := NewUserService(userRepo)
	user, _ := service.GetUser("123")

	assert.Equal(t, "123", user.ID)
}
```

---

## 技术栈推荐

### 1. 微服务（高性能）

```
HTTP 框架：Chi / Echo
数据库：sqlx
配置：envconfig
日志：zap
依赖注入：Wire
测试：testify + mocker
```

### 2. 单体应用（快速开发）

```
HTTP 框架：Gin
ORM：GORM
配置：Viper
日志：logrus
依赖注入：手动装配
测试：testify
```

### 3. 企业级应用（稳定性）

```
HTTP 框架：Gin / Echo
数据库：ent / sqlx
配置：Viper
日志：slog (Go 1.21+)
依赖注入：Wire
测试：mocker + testify
```

### 4. 云原生（容器化）

```
HTTP 框架：Chi
数据库：sqlx
配置：envconfig
日志：slog (JSON 格式)
依赖注入：fx
测试：testify
```

---

## 总结

| 场景 | HTTP | 数据库 | 配置 | 日志 | DI | 测试 |
|------|------|--------|------|------|----|------|
| **快速开发** | Gin | GORM | Viper | logrus | 手动 | testify |
| **高性能** | Chi/Echo | sqlx | envconfig | zap/slog | Wire | mocker |
| **大型项目** | Echo | ent | Viper | zap | Wire | mocker |
| **云原生** | Chi | sqlx | envconfig | slog | fx | testify |

选择技术栈时，优先考虑：
1. **团队熟悉度**
2. **项目规模和复杂度**
3. **性能要求**
4. **维护成本**
