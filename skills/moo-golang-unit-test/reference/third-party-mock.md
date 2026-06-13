# 第三方库 Mock 策略

本文档介绍如何正确 Mock 常见的第三方库。

## 核心原则

**❌ 不要直接 Mock 第三方库**
- 第三方库的内部实现可能变化
- Mock 实现细节容易出错
- 维护成本高

**✅ 使用官方推荐的测试方案**
- 使用专门的测试库
- 使用内存版本
- 使用测试服务器

## 数据库 Mock

### 1. go-sqlmock（推荐）

用于 Mock `database/sql` 和 GORM。

#### 安装

```bash
go get github.com/DATA-DOG/go-sqlmock
```

#### 基础用法

```go
import (
    "database/sql"
    "testing"

    "github.com/DATA-DOG/go-sqlmock"
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"
)

func TestUserRepo_GetByID(t *testing.T) {
    // 1. 创建 Mock DB
    db, mock, err := sqlmock.New()
    require.NoError(t, err)
    defer db.Close()

    // 2. 设置期望
    rows := sqlmock.NewRows([]string{"id", "name", "email"}).
        AddRow(1, "test", "test@example.com")

    mock.ExpectQuery("SELECT (.+) FROM users WHERE id = ?").
        WithArgs(1).
        WillReturnRows(rows)

    // 3. 创建 Repo
    repo := &UserRepo{db: db}

    // 4. 执行测试
    user, err := repo.GetByID(context.Background(), 1)

    // 5. 验证
    require.NoError(t, err)
    assert.Equal(t, int64(1), user.ID)
    assert.Equal(t, "test", user.Name)

    // 6. 验证所有期望都被调用
    err = mock.ExpectationsWereMet()
    assert.NoError(t, err)
}
```

#### GORM 集成

```go
import (
    "github.com/DATA-DOG/go-sqlmock"
    "gorm.io/driver/mysql"
    "gorm.io/gorm"
)

func TestUserRepo_CreateWithGORM(t *testing.T) {
    // 1. 创建 Mock DB
    db, mock, err := sqlmock.New()
    require.NoError(t, err)
    defer db.Close()

    // 2. 创建 GORM DB
    gormDB, err := gorm.Open(mysql.New(mysql.Config{
        Conn:                      db,
        SkipInitializeWithVersion: true,  // 重要：跳过版本检查
    }), &gorm.Config{})
    require.NoError(t, err)

    // 3. 设置期望
    mock.ExpectBegin()
    mock.ExpectExec("INSERT INTO `users`").
        WithArgs("test", "test@example.com", sqlmock.AnyArg()).
        WillReturnResult(sqlmock.NewResult(1, 1))
    mock.ExpectCommit()

    // 4. 创建 Repo
    repo := &UserRepo{db: gormDB}

    // 5. 执行测试
    user := &User{Name: "test", Email: "test@example.com"}
    err = repo.Create(context.Background(), user)

    // 6. 验证
    require.NoError(t, err)
    assert.Equal(t, int64(1), user.ID)

    err = mock.ExpectationsWereMet()
    assert.NoError(t, err)
}
```

#### 常见 SQL 操作

```go
// SELECT 查询
rows := sqlmock.NewRows([]string{"id", "name"}).
    AddRow(1, "user1").
    AddRow(2, "user2")
mock.ExpectQuery("SELECT (.+) FROM users").WillReturnRows(rows)

// INSERT 操作
mock.ExpectExec("INSERT INTO users").
    WithArgs("test", "test@example.com").
    WillReturnResult(sqlmock.NewResult(1, 1))  // lastInsertId, rowsAffected

// UPDATE 操作
mock.ExpectExec("UPDATE users SET name = ?").
    WithArgs("new name", 1).
    WillReturnResult(sqlmock.NewResult(0, 1))

// DELETE 操作
mock.ExpectExec("DELETE FROM users WHERE id = ?").
    WithArgs(1).
    WillReturnResult(sqlmock.NewResult(0, 1))

// 事务
mock.ExpectBegin()
mock.ExpectExec("INSERT INTO users").WillReturnResult(sqlmock.NewResult(1, 1))
mock.ExpectCommit()

// 事务回滚
mock.ExpectBegin()
mock.ExpectExec("INSERT INTO users").WillReturnError(errors.New("db error"))
mock.ExpectRollback()

// 返回错误
mock.ExpectQuery("SELECT (.+) FROM users").
    WillReturnError(errors.New("connection timeout"))
```

#### 正则匹配 SQL

```go
// 精确匹配（推荐用于测试）
mock.ExpectQuery("SELECT id, name FROM users WHERE id = ?").
    WithArgs(1).
    WillReturnRows(rows)

// 正则匹配
mock.ExpectQuery(`SELECT (.+) FROM users WHERE id = \?`).
    WithArgs(1).
    WillReturnRows(rows)

// 忽略 SQL（不推荐）
mock.ExpectQuery(".*").WillReturnRows(rows)
```

### 2. 为什么不 Mock GORM？

```go
// ❌ 错误：直接 Mock GORM
gormDB := &gorm.DB{}
mock.Interface(&gormDB).Method("Create").Return(...)

// 问题：
// 1. GORM 内部实现复杂，Mock 容易出错
// 2. GORM 版本更新可能导致 Mock 失效
// 3. 无法验证生成的 SQL 是否正确
```

```go
// ✅ 正确：使用 go-sqlmock
db, mock, _ := sqlmock.New()
gormDB, _ := gorm.Open(mysql.New(mysql.Config{Conn: db}), &gorm.Config{})

// 好处：
// 1. 可以验证 SQL 语句
// 2. 可以验证参数
// 3. 与 GORM 版本无关
```

## Redis Mock

### miniredis（推荐）

内存中的 Redis 服务器，支持大部分 Redis 命令。

#### 安装

```bash
go get github.com/alicebob/miniredis/v2
```

#### 基础用法

```go
import (
    "testing"

    "github.com/alicebob/miniredis/v2"
    "github.com/go-redis/redis/v8"
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"
)

func TestCacheService_Get(t *testing.T) {
    // 1. 启动 miniredis
    mr, err := miniredis.Run()
    require.NoError(t, err)
    defer mr.Close()

    // 2. 创建 Redis 客户端
    client := redis.NewClient(&redis.Options{
        Addr: mr.Addr(),
    })

    // 3. 预设数据
    mr.Set("user:1", `{"id":1,"name":"test"}`)

    // 4. 创建 Service
    service := &CacheService{redis: client}

    // 5. 执行测试
    user, err := service.GetUser(context.Background(), "user:1")

    // 6. 验证
    require.NoError(t, err)
    assert.Equal(t, int64(1), user.ID)
    assert.Equal(t, "test", user.Name)
}
```

#### 常见操作

```go
// String 操作
mr.Set("key", "value")
mr.Get("key")  // 返回 "value"
mr.SetEx("key", time.Hour, "value")  // 带过期时间

// Hash 操作
mr.HSet("user:1", "name", "test")
mr.HGet("user:1", "name")  // 返回 "test"
mr.HGetAll("user:1")

// List 操作
mr.LPush("list", "value1", "value2")
mr.LRange("list", 0, -1)

// Set 操作
mr.SAdd("set", "member1", "member2")
mr.SMembers("set")

// 过期时间
mr.Set("key", "value")
mr.Expire("key", time.Hour)
mr.TTL("key")  // 返回剩余时间

// 检查是否存在
mr.Exists("key")  // 返回 bool

// 删除
mr.Del("key")

// 快进时间（测试过期）
mr.Set("key", "value")
mr.Expire("key", time.Second)
mr.FastForward(2 * time.Second)  // 快进2秒
mr.Exists("key")  // 返回 false
```

#### 测试 Redis 失败场景

```go
func TestCacheService_HandleRedisError(t *testing.T) {
    mr, err := miniredis.Run()
    require.NoError(t, err)
    defer mr.Close()

    client := redis.NewClient(&redis.Options{Addr: mr.Addr()})
    service := &CacheService{redis: client}

    // 模拟 Redis 错误
    mr.SetError("connection refused")

    // 执行测试
    _, err = service.GetUser(context.Background(), "user:1")

    // 验证错误处理
    assert.Error(t, err)
    assert.Contains(t, err.Error(), "connection refused")

    // 清除错误状态
    mr.SetError("")
}
```

### 为什么不 Mock Redis Client？

```go
// ❌ 错误：Mock Redis Client
redisClient := &redis.Client{}
mock.Interface(&redisClient).Method("Get").Return(...)

// 问题：
// 1. redis.Client 有很多内部状态
// 2. 无法测试 Redis 特定行为（过期、并发等）
// 3. 维护成本高
```

```go
// ✅ 正确：使用 miniredis
mr, _ := miniredis.Run()
client := redis.NewClient(&redis.Options{Addr: mr.Addr()})

// 好处：
// 1. 真实的 Redis 行为
// 2. 可以测试过期、事务等高级功能
// 3. 无需维护 Mock 代码
```

## HTTP Mock

### httptest（标准库）

Go 标准库提供的 HTTP 测试工具。

#### Mock HTTP 服务器

```go
import (
    "io"
    "net/http"
    "net/http/httptest"
    "testing"

    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"
)

func TestAPIClient_GetUser(t *testing.T) {
    // 1. 创建测试服务器
    server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        // 验证请求
        assert.Equal(t, "/api/users/1", r.URL.Path)
        assert.Equal(t, "GET", r.Method)
        assert.Equal(t, "Bearer token123", r.Header.Get("Authorization"))

        // 返回响应
        w.Header().Set("Content-Type", "application/json")
        w.WriteHeader(http.StatusOK)
        w.Write([]byte(`{"id":1,"name":"test"}`))
    }))
    defer server.Close()

    // 2. 创建客户端
    client := &APIClient{
        baseURL: server.URL,
        token:   "token123",
    }

    // 3. 执行测试
    user, err := client.GetUser(context.Background(), 1)

    // 4. 验证
    require.NoError(t, err)
    assert.Equal(t, int64(1), user.ID)
    assert.Equal(t, "test", user.Name)
}
```

#### Mock HTTP 错误

```go
func TestAPIClient_HandleError(t *testing.T) {
    tests := []struct {
        name           string
        statusCode     int
        responseBody   string
        expectedError  string
    }{
        {
            name:          "404 Not Found",
            statusCode:    http.StatusNotFound,
            responseBody:  `{"error":"user not found"}`,
            expectedError: "user not found",
        },
        {
            name:          "500 Internal Error",
            statusCode:    http.StatusInternalServerError,
            responseBody:  `{"error":"internal error"}`,
            expectedError: "internal error",
        },
        {
            name:          "401 Unauthorized",
            statusCode:    http.StatusUnauthorized,
            responseBody:  `{"error":"invalid token"}`,
            expectedError: "invalid token",
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                w.WriteHeader(tt.statusCode)
                w.Write([]byte(tt.responseBody))
            }))
            defer server.Close()

            client := &APIClient{baseURL: server.URL}
            _, err := client.GetUser(context.Background(), 1)

            require.Error(t, err)
            assert.Contains(t, err.Error(), tt.expectedError)
        })
    }
}
```

#### Mock HTTP 超时

```go
func TestAPIClient_Timeout(t *testing.T) {
    server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        // 模拟慢响应
        time.Sleep(2 * time.Second)
        w.WriteHeader(http.StatusOK)
    }))
    defer server.Close()

    // 设置短超时
    client := &APIClient{
        baseURL: server.URL,
        timeout: 100 * time.Millisecond,
    }

    _, err := client.GetUser(context.Background(), 1)

    require.Error(t, err)
    assert.Contains(t, err.Error(), "timeout")
}
```

#### 验证请求内容

```go
func TestAPIClient_CreateUser(t *testing.T) {
    var capturedRequest *http.Request
    var capturedBody []byte

    server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        capturedRequest = r

        // 读取请求体
        body, _ := io.ReadAll(r.Body)
        capturedBody = body

        w.WriteHeader(http.StatusCreated)
        w.Write([]byte(`{"id":1}`))
    }))
    defer server.Close()

    client := &APIClient{baseURL: server.URL}
    user := &User{Name: "test", Email: "test@example.com"}

    err := client.CreateUser(context.Background(), user)
    require.NoError(t, err)

    // 验证请求
    assert.Equal(t, "POST", capturedRequest.Method)
    assert.Equal(t, "application/json", capturedRequest.Header.Get("Content-Type"))
    assert.Contains(t, string(capturedBody), `"name":"test"`)
}
```

## 时间相关

### 依赖注入（推荐）

```go
// ❌ 不好：直接使用 time.Now()
type Service struct{}

func (s *Service) CreateRecord() *Record {
    return &Record{
        CreatedAt: time.Now(),  // 难以测试
    }
}
```

```go
// ✅ 好：注入时间提供者
type TimeProvider interface {
    Now() time.Time
}

type RealTimeProvider struct{}

func (r *RealTimeProvider) Now() time.Time {
    return time.Now()
}

type Service struct {
    timeProvider TimeProvider
}

func (s *Service) CreateRecord() *Record {
    return &Record{
        CreatedAt: s.timeProvider.Now(),
    }
}

// 测试中 Mock
type MockTimeProvider struct {
    now time.Time
}

func (m *MockTimeProvider) Now() time.Time {
    return m.now
}

func TestService_CreateRecord(t *testing.T) {
    fixedTime := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
    service := &Service{
        timeProvider: &MockTimeProvider{now: fixedTime},
    }

    record := service.CreateRecord()

    assert.Equal(t, fixedTime, record.CreatedAt)
}
```

## 文件系统 Mock

### afero（推荐）

内存文件系统。

```bash
go get github.com/spf13/afero
```

```go
import (
    "github.com/spf13/afero"
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"
)

func TestFileService_ReadConfig(t *testing.T) {
    // 1. 创建内存文件系统
    fs := afero.NewMemMapFs()

    // 2. 写入测试文件
    afero.WriteFile(fs, "/config.json", []byte(`{"debug":true}`), 0644)

    // 3. 创建 Service
    service := &FileService{fs: fs}

    // 4. 执行测试
    config, err := service.ReadConfig("/config.json")

    // 5. 验证
    require.NoError(t, err)
    assert.True(t, config.Debug)
}
```

## 总结

| 第三方库 | 推荐方案 | 原因 |
|---------|---------|------|
| database/sql | go-sqlmock | 验证 SQL，与实现解耦 |
| GORM | go-sqlmock | 同上 |
| Redis | miniredis | 真实 Redis 行为 |
| HTTP Client | httptest | 标准库，功能完整 |
| 时间 | 依赖注入 | 简单有效 |
| 文件系统 | afero | 内存操作，快速 |

**原则：**
1. 优先使用官方推荐的测试方案
2. 不要 Mock 第三方库的内部实现
3. 使用内存版本或测试服务器
4. 通过依赖注入提高可测试性

---

**返回 [主文档](../SKILL.md)**
