# Mocker 使用详细指南

本文档提供 GOOM Mocker 库的完整使用指南。

## 什么是 Mocker？

[GOOM Mocker](https://github.com/tencent/goom) 是腾讯开源的 Go Mock 框架，支持：
- 接口 Mock
- 结构体方法 Mock
- 函数 Mock
- 全局变量 Mock

**为什么选择 Mocker？**
- 无需生成 Mock 代码
- 支持 Mock 具体类型（不仅是接口）
- 语法简洁直观
- 运行时动态 Mock

## 基本用法

### 创建和清理 Mock

```go
import "github.com/tencent/goom"

func TestSomething(t *testing.T) {
    // 1. 创建 Mock
    mock := mocker.Create()

    // 2. 使用 defer 确保清理
    defer mock.Reset()

    // 3. 设置 Mock 行为
    // ...

    // 4. 执行测试
    // ...
}
```

**重要：** 必须使用 `defer mock.Reset()` 确保清理，否则会影响其他测试。

## 接口 Mock

### 基础接口 Mock

```go
// 定义接口
type UserRepo interface {
    GetByID(ctx context.Context, id int64) (*User, error)
    Create(ctx context.Context, user *User) error
}

// 测试中 Mock
func TestUserService_GetUser(t *testing.T) {
    mock := mocker.Create()
    defer mock.Reset()

    // ⚠️ 关键：必须使用类型转换保留类型信息
    userRepo := (UserRepo)(nil)

    // Mock GetByID 方法
    mock.Interface(&userRepo).Method("GetByID").Apply(
        func(_ *mocker.IContext, ctx context.Context, id int64) (*User, error) {
            // 自定义 Mock 逻辑
            if id == 1 {
                return &User{ID: 1, Name: "test"}, nil
            }
            return nil, errors.New("not found")
        },
    )

    // 注入到被测对象
    service := &UserService{repo: userRepo}

    // 执行测试
    user, err := service.GetUser(context.Background(), 1)
    assert.NoError(t, err)
    assert.Equal(t, "test", user.Name)
}
```

### 常见错误

```go
// ❌ 错误：类型信息丢失
var userRepo UserRepo  // 值为 nil，但类型信息已丢失
mock.Interface(&userRepo).Method("GetByID")...  // 无法工作！

// ✅ 正确：显式类型转换
userRepo := (UserRepo)(nil)  // nil，但保留类型信息
mock.Interface(&userRepo).Method("GetByID")...  // 可以工作
```

### 简化语法：固定返回值

```go
// 如果不需要复杂逻辑，可以使用 Return
mock.Interface(&userRepo).Method("GetByID").Return(
    &User{ID: 1, Name: "test"},
    nil,  // error
)
```

### Apply 的第一个参数

```go
// ✅ 正确：第一个参数必须是 *mocker.IContext
mock.Interface(&userRepo).Method("GetByID").Apply(
    func(_ *mocker.IContext, ctx context.Context, id int64) (*User, error) {
        return &User{ID: id}, nil
    },
)

// ❌ 错误：缺少 *mocker.IContext 参数
mock.Interface(&userRepo).Method("GetByID").Apply(
    func(ctx context.Context, id int64) (*User, error) {  // 编译错误！
        return &User{ID: id}, nil
    },
)
```

## 结构体方法 Mock

Mocker 的强大之处：可以 Mock 具体类型的方法，无需定义接口。

```go
// 具体类型
type DataProcessor struct {
    config *Config
}

func (d *DataProcessor) Process(data string) (string, error) {
    // 复杂的处理逻辑
    return processData(data)
}

func (d *DataProcessor) Validate(data string) (bool, error) {
    // 验证逻辑
    return validateData(data)
}

// 测试中 Mock
func TestService_ProcessData(t *testing.T) {
    mock := mocker.Create()
    defer mock.Reset()

    // Mock 结构体方法
    mock.Struct(&DataProcessor{}).Method("Process").Apply(
        func(_ *DataProcessor, data string) (string, error) {
            return "processed: " + data, nil
        },
    )

    // 或使用 Return
    mock.Struct(&DataProcessor{}).Method("Validate").Return(true, nil)

    // 创建被测对象
    processor := &DataProcessor{}
    service := &Service{processor: processor}

    // 执行测试
    result, err := service.ProcessData("test")
    assert.NoError(t, err)
    assert.Equal(t, "processed: test", result)
}
```

**好处：**
- 不需要为每个结构体定义接口
- 适合快速测试
- 减少接口定义的维护成本

**注意：**
- Mock 会影响所有该类型的实例
- 使用完必须 `Reset()`

## 函数 Mock

### Mock 全局函数

```go
package utils

import "github.com/google/uuid"

func GenerateID() string {
    return uuid.New().String()
}

func GetCurrentTime() time.Time {
    return time.Now()
}
```

```go
// 测试中 Mock
func TestService_CreateRecord(t *testing.T) {
    mock := mocker.Create()
    defer mock.Reset()

    // Mock 全局函数
    mock.Func(utils.GenerateID).Return("mock-id-123")

    mock.Func(utils.GetCurrentTime).Return(
        time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC),
    )

    // 执行测试
    service := &Service{}
    record := service.CreateRecord("test")

    assert.Equal(t, "mock-id-123", record.ID)
    assert.Equal(t, "2024-01-01", record.CreatedAt.Format("2006-01-02"))
}
```

### Mock 带逻辑的函数

```go
// 使用 Apply 实现自定义逻辑
mock.Func(utils.ValidateEmail).Apply(
    func(email string) bool {
        // 自定义验证逻辑
        return strings.Contains(email, "@")
    },
)
```

## 全局变量 Mock

### Mock 全局变量

```go
package config

var (
    AppName    = "production-app"
    DebugMode  = false
    MaxRetries = 3
)
```

```go
// 测试中 Mock
func TestService_WithDebugMode(t *testing.T) {
    mock := mocker.Create()
    defer mock.Reset()

    // Mock 全局变量
    mock.Var(&config.AppName).Set("test-app")
    mock.Var(&config.DebugMode).Set(true)
    mock.Var(&config.MaxRetries).Set(1)

    // 执行测试
    service := &Service{}
    result := service.DoSomething()

    // 验证
    assert.True(t, result.DebugEnabled)
}
```

## 高级特性

### 条件 Mock (When)

根据参数条件返回不同结果：

```go
mock.Interface(&userRepo).Method("GetByID").When(
    func(ctx context.Context, id int64) bool {
        return id == 1  // 条件
    },
).Return(&User{ID: 1, Name: "test"}, nil)

// 不满足条件时的默认行为
mock.Interface(&userRepo).Method("GetByID").Return(
    nil,
    errors.New("not found"),
)
```

### 多次返回 (Returns)

模拟多次调用返回不同结果：

```go
mock.Interface(&userRepo).Method("GetByID").Returns(
    // 第一次调用
    []interface{}{&User{ID: 1, Name: "first"}, nil},
    // 第二次调用
    []interface{}{&User{ID: 2, Name: "second"}, nil},
    // 第三次及以后调用
    []interface{}{nil, errors.New("limit exceeded")},
)

// 测试
user1, _ := repo.GetByID(ctx, 1)  // 返回 first
user2, _ := repo.GetByID(ctx, 2)  // 返回 second
user3, _ := repo.GetByID(ctx, 3)  // 返回 error
```

### 调用原始方法 (Origin)

在 Mock 中调用原始方法：

```go
mock.Interface(&userRepo).Method("GetByID").Apply(
    func(ic *mocker.IContext, ctx context.Context, id int64) (*User, error) {
        // 调用原始方法
        user, err := ic.Origin().(func(context.Context, int64) (*User, error))(ctx, id)

        // 修改结果
        if user != nil {
            user.Name = "modified-" + user.Name
        }

        return user, err
    },
)
```

## 调试和问题排查

### 查看 Mock 是否生效

```go
// 添加日志
mock.Interface(&userRepo).Method("GetByID").Apply(
    func(_ *mocker.IContext, ctx context.Context, id int64) (*User, error) {
        fmt.Printf("Mock called with id=%d\n", id)
        return &User{ID: id}, nil
    },
)
```

### 常见问题

#### 1. Mock 没有生效

**原因：** 类型信息丢失或方法签名不匹配

```go
// 检查：
// 1. 接口是否使用类型转换: userRepo := (UserRepo)(nil)
// 2. 方法名是否正确
// 3. Apply 第一个参数是否为 *mocker.IContext
```

#### 2. Mock 影响了其他测试

**原因：** 忘记调用 `Reset()`

```go
// 解决：始终使用 defer
defer mock.Reset()
```

#### 3. 并发测试失败

**原因：** Mocker 修改全局状态

```go
// 解决：不要在并发测试中使用 Mocker Mock 全局函数/变量
// 或者不使用 t.Parallel()
```

## 最佳实践

### 1. Mock 粒度

```go
// ✅ 好：只 Mock 必要的方法
mock.Interface(&userRepo).Method("GetByID").Return(...)

// ❌ 不好：Mock 所有方法
mock.Interface(&userRepo).Method("GetByID").Return(...)
mock.Interface(&userRepo).Method("Create").Return(...)
mock.Interface(&userRepo).Method("Update").Return(...)
// ... (如果测试只需要 GetByID)
```

### 2. Mock 顺序

```go
// ✅ 好：按测试执行顺序设置 Mock
func TestService_ComplexFlow(t *testing.T) {
    mock := mocker.Create()
    defer mock.Reset()

    // 1. 设置所有 Mock
    mock.Interface(&userRepo).Method("GetByID").Return(...)
    mock.Interface(&orderRepo).Method("Create").Return(...)

    // 2. 创建被测对象
    service := NewService(userRepo, orderRepo)

    // 3. 执行测试
    result, err := service.ProcessOrder(...)

    // 4. 验证结果
    assert.NoError(t, err)
}
```

### 3. 复用 Mock 配置

```go
// 提取辅助函数
func mockUserRepo(mock *mocker.Mocker) UserRepo {
    repo := (UserRepo)(nil)
    mock.Interface(&repo).Method("GetByID").Apply(
        func(_ *mocker.IContext, ctx context.Context, id int64) (*User, error) {
            return &User{ID: id, Name: "test"}, nil
        },
    )
    return repo
}

// 在测试中使用
func TestService_GetUser(t *testing.T) {
    mock := mocker.Create()
    defer mock.Reset()

    userRepo := mockUserRepo(mock)
    service := &Service{repo: userRepo}

    // ...
}
```

### 4. 避免过度 Mock

```go
// ❌ 不好：Mock 简单的纯函数
func add(a, b int) int { return a + b }
mock.Func(add).Return(5)  // 没必要

// ✅ 好：直接调用
result := add(2, 3)  // 简单纯函数无需 Mock
```

## 运行测试

### Go < 1.23

```bash
go test -gcflags=all=-l -v ./...
```

### Go >= 1.23

```bash
go test -gcflags="all=-N -l" -ldflags=-checklinkname=0 -v ./...
```

**参数说明：**
- `-gcflags=all=-l`: 禁用内联优化（Mocker 需要）
- `-gcflags="all=-N -l"`: Go 1.23+ 需要同时禁用优化和内联
- `-ldflags=-checklinkname=0`: Go 1.23+ 禁用 linkname 检查

## 参考资源

- [GOOM Mocker 公开仓库](https://github.com/tencent/goom)
- [示例代码](../examples/mock-examples.md)

---

**返回 [主文档](../SKILL.md)**
