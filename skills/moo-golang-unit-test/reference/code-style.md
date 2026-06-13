# 代码风格完整规范

本文档定义 Go 单元测试代码的完整风格规范，基于腾讯 Go 编码规范。

## 格式化和换行

### 使用 gofmt

所有代码必须使用 `gofmt` 格式化。

```bash
# 格式化单个文件
gofmt -w file.go

# 格式化整个项目
gofmt -w .
```

### 行长度

- 建议每行不超过 **120 个字符**
- 超过时应换行

```go
// ✅ 好：适当换行
mock.Interface(&userRepo).Method("GetByID").Apply(
    func(_ *mocker.IContext, ctx context.Context, id int64) (*User, error) {
        return &User{ID: id}, nil
    },
)

// ❌ 不好：一行太长
mock.Interface(&userRepo).Method("GetByID").Apply(func(_ *mocker.IContext, ctx context.Context, id int64) (*User, error) { return &User{ID: id}, nil })
```

## Import 规范

### Import 分组

Import 必须分为 3 组，用空行分隔：

1. 标准库
2. 第三方库
3. 项目内部包

```go
import (
    // 1. 标准库
    "context"
    "errors"
    "fmt"
    "testing"
    "time"

    // 2. 第三方库
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"
    "github.com/tencent/goom"
    "github.com/DATA-DOG/go-sqlmock"

    // 3. 项目内部包
    "github.com/mooyang-code/project/dao"
    "github.com/mooyang-code/project/model"
    "github.com/mooyang-code/project/service"
)
```

### 每组内按字母排序

```go
// ✅ 正确：按字母排序
import (
    "context"
    "errors"
    "fmt"
    "testing"
)

// ❌ 错误：未排序
import (
    "testing"
    "context"
    "fmt"
    "errors"
)
```

### 不要使用相对路径

```go
// ❌ 错误：相对路径
import "../dao"

// ✅ 正确：完整路径
import "github.com/mooyang-code/project/dao"
```

### 不要使用 . import

```go
// ❌ 错误：点 import
import . "github.com/stretchr/testify/assert"

func TestSomething(t *testing.T) {
    Equal(t, 1, 1)  // 不清楚来自哪里
}

// ✅ 正确：显式 import
import "github.com/stretchr/testify/assert"

func TestSomething(t *testing.T) {
    assert.Equal(t, 1, 1)  // 清楚来自 assert 包
}
```

### 必要时使用别名

```go
// ✅ 好：使用别名避免冲突
import (
    "github.com/mooyang-code/project/model"
    protomodel "github.com/mooyang-code/project/proto/model"
)

// ✅ 好：使用别名简化长包名
import (
    mock "github.com/DATA-DOG/go-sqlmock"
)
```

## 错误处理规范

### error 作为最后返回值

```go
// ✅ 正确：error 在最后
func doSomething() (int, error) {
    return 0, nil
}

func doSomething2() (int, string, error) {
    return 0, "", nil
}

// ❌ 错误：error 不在最后
func doSomething() (error, int) {
    return nil, 0
}
```

### 独立的错误处理流程

```go
// ✅ 正确：错误处理独立
result, err := doSomething()
if err != nil {
    // 错误处理
    return nil, err
}
// 正常流程
process(result)

// ❌ 错误：混在一起
if result, err := doSomething(); err == nil {
    process(result)
} else {
    return nil, err
}
```

### 使用 require 处理致命错误

```go
// ✅ 正确：致命错误用 require
func TestUserService_GetUser(t *testing.T) {
    user, err := service.GetUser(1)
    require.NoError(t, err)  // 如果失败，停止测试

    // 后续代码依赖 user 不为 nil
    assert.Equal(t, "test", user.Name)
}

// ❌ 错误：可能导致 panic
func TestUserService_GetUser(t *testing.T) {
    user, err := service.GetUser(1)
    assert.NoError(t, err)  // 即使失败，继续执行

    // 如果 user 为 nil，这里会 panic
    assert.Equal(t, "test", user.Name)
}
```

### 错误信息小写开头

```go
// ✅ 正确：错误信息小写开头
errors.New("user not found")
fmt.Errorf("invalid email: %s", email)

// ❌ 错误：错误信息大写开头
errors.New("User not found")
fmt.Errorf("Invalid email: %s", email)
```

## 命名规范

### 变量命名

```go
// ✅ 正确：驼峰式，首字母小写
var userName string
var userCount int
var isActive bool

// ❌ 错误：下划线分隔
var user_name string
var user_count int
```

### 常量命名

```go
// ✅ 正确：驼峰式或全大写
const MaxRetries = 3
const DefaultTimeout = 10 * time.Second
const API_KEY = "xxx"  // 全大写也可以

// ❌ 错误：下划线分隔普通常量
const max_retries = 3
```

### 特殊名词保持原有写法

```go
// ✅ 正确：特殊名词保持原有大小写
var userID int64        // ID 不是 Id
var apiClient *Client   // API 不是 Api
var urlPath string      // URL 不是 Url
var httpServer *Server  // HTTP 不是 Http
var jsonData []byte     // JSON 不是 Json

// 导出的变量
var UserID int64
var APIClient *Client
var URLPath string
var HTTPServer *Server

// ❌ 错误：特殊名词写法错误
var userId int64        // 应该是 userID
var apiClient *Client   // 如果导出应该是 APIClient
var urlPath string      // 如果导出应该是 URLPath
```

### 测试函数命名

```go
// ✅ 正确：完整描述场景和结果
func TestUserService_Create_ValidUser_ShouldSuccess(t *testing.T)
func TestUserService_Create_DuplicateEmail_ShouldReturnError(t *testing.T)
func TestValidator_ValidateEmail_EmptyEmail_ShouldReturnError(t *testing.T)

// ❌ 错误：命名不清晰
func TestCreate(t *testing.T)
func TestCreate1(t *testing.T)
func TestError(t *testing.T)
```

### 表驱动测试用例命名

```go
tests := []struct {
    name    string  // 使用 snake_case
    input   int
    wantErr bool
}{
    {
        name:    "valid_positive_number",  // ✅ 小写下划线
        input:   10,
        wantErr: false,
    },
    {
        name:    "invalid_negative_number",
        input:   -1,
        wantErr: true,
    },
}
```

## 控制结构规范

### if 语句

```go
// ✅ 正确：花括号不换行
if condition {
    // ...
}

// ❌ 错误：花括号换行
if condition
{
    // ...
}

// ✅ 正确：简短声明
if err := doSomething(); err != nil {
    return err
}

// ✅ 正确：提前返回
if err != nil {
    return err
}
// 正常流程

// ❌ 错误：嵌套太深
if condition1 {
    if condition2 {
        if condition3 {
            // ...
        }
    }
}
```

### for 循环

```go
// ✅ 正确：标准 for
for i := 0; i < 10; i++ {
    // ...
}

// ✅ 正确：range
for i, v := range slice {
    // ...
}

// ✅ 正确：忽略不用的变量
for _, v := range slice {
    // ...
}

// ❌ 错误：不忽略不用的变量
for i, v := range slice {  // i 未使用
    process(v)
}
```

### switch 语句

```go
// ✅ 正确：每个 case 独立
switch status {
case "pending":
    // ...
case "processing":
    // ...
case "completed":
    // ...
default:
    // ...
}

// ✅ 正确：多个条件合并
switch status {
case "pending", "processing":
    // ...
case "completed":
    // ...
}
```

## 函数和方法

### 函数长度

- 普通函数：≤ 80 行
- 测试函数：≤ 160 行（2x）

### 参数顺序

```go
// ✅ 正确：context 第一个，error 最后
func doSomething(ctx context.Context, id int64, name string) (*Result, error) {
    return nil, nil
}

// ❌ 错误：顺序不对
func doSomething(id int64, ctx context.Context) (error, *Result) {
    return nil, nil
}
```

### 多返回值换行

```go
// ✅ 正确：返回值过多时换行
func complexFunc(
    ctx context.Context,
    param1 string,
    param2 int,
) (
    result1 string,
    result2 int,
    err error,
) {
    return "", 0, nil
}
```

## 注释规范

### 测试函数注释

```go
// ✅ 好的注释：说明场景、前置条件、预期结果
func TestUserService_Create_DuplicateEmail_ShouldReturnError(t *testing.T) {
    // 测试场景: 创建用户时邮箱重复
    // 前置条件: 数据库中已存在相同邮箱的用户
    // 输入数据: 邮箱为 test@example.com 的用户
    // 预期结果: 返回邮箱重复错误

    // 准备测试数据
    existingUser := &User{Email: "test@example.com"}
    // ...
}

// ❌ 不需要的注释
func TestUserService_Create(t *testing.T) {
    // 创建 mock  <- 代码已经很清楚了
    mock := mocker.Create()
    // ...
}
```

### 复杂逻辑注释

```go
// ✅ 好的注释：解释为什么
mock.Interface(&userRepo).Method("GetByID").Apply(
    func(_ *mocker.IContext, ctx context.Context, id int64) (*User, error) {
        // 模拟数据库查询失败场景
        if id == 999 {
            return nil, errors.New("database connection timeout")
        }
        return &User{ID: id}, nil
    },
)

// ❌ 不好的注释：重复代码
// 调用 GetByID 方法  <- 代码已经很清楚了
user, err := repo.GetByID(ctx, 1)
```

## 结构体和方法

### 结构体字段排列

```go
// ✅ 好：相关字段放在一起，按大小排列（可选）
type User struct {
    // 基础信息
    ID    int64
    Name  string
    Email string

    // 时间字段
    CreatedAt time.Time
    UpdatedAt time.Time

    // 布尔标志
    IsActive  bool
    IsDeleted bool
}
```

### 构造函数

```go
// ✅ 好：使用 New 前缀
func NewUserService(repo UserRepo) *UserService {
    return &UserService{
        repo: repo,
    }
}

// ✅ 好：为测试提供构造函数
func NewTestUser(opts ...func(*User)) *User {
    user := &User{
        ID:    1,
        Name:  "test",
        Email: "test@example.com",
    }
    for _, opt := range opts {
        opt(user)
    }
    return user
}
```

## 魔法数字处理

### 使用常量代替魔法数字

```go
// ❌ 不好：魔法数字
func TestRetry(t *testing.T) {
    for i := 0; i < 3; i++ {  // 3 是什么？
        // ...
    }
    time.Sleep(100 * time.Millisecond)  // 100 是什么？
}

// ✅ 好：使用常量
const (
    MaxRetries     = 3
    RetryInterval  = 100 * time.Millisecond
)

func TestRetry(t *testing.T) {
    for i := 0; i < MaxRetries; i++ {
        // ...
    }
    time.Sleep(RetryInterval)
}
```

### 表驱动测试中的魔法数字

```go
// ❌ 不好：魔法数字
tests := []struct {
    name    string
    age     int
    wantErr bool
}{
    {
        name:    "valid_age",
        age:     25,  // 为什么是 25？
        wantErr: false,
    },
    {
        name:    "too_young",
        age:     10,  // 为什么是 10？
        wantErr: true,
    },
}

// ✅ 好：使用常量或注释说明
const (
    MinAge = 18
    MaxAge = 120
)

tests := []struct {
    name    string
    age     int
    wantErr bool
}{
    {
        name:    "valid_age",
        age:     MinAge + 7,  // 合法年龄
        wantErr: false,
    },
    {
        name:    "too_young",
        age:     MinAge - 8,  // 低于最小年龄
        wantErr: true,
    },
}
```

## 表驱动测试规范

### 标准结构

```go
func TestFunction(t *testing.T) {
    tests := []struct {
        name    string  // 必须：测试用例名称
        input   Input   // 输入参数
        mock    func()  // Mock 设置（可选）
        want    Output  // 期望输出
        wantErr bool    // 是否期望错误
    }{
        {
            name:  "normal_case",
            input: Input{...},
            want:  Output{...},
            wantErr: false,
        },
        {
            name:  "error_case",
            input: Input{...},
            wantErr: true,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            // 设置 Mock
            if tt.mock != nil {
                tt.mock()
            }

            // 执行测试
            got, err := Function(tt.input)

            // 验证错误
            if tt.wantErr {
                assert.Error(t, err)
                return
            }
            assert.NoError(t, err)

            // 验证结果
            assert.Equal(t, tt.want, got)
        })
    }
}
```

## 文件组织

### 测试文件命名

```go
// 源文件
user_service.go

// 测试文件（必须以 _test.go 结尾）
user_service_test.go
```

### 文件长度

- 普通文件：≤ 800 行
- 测试文件：≤ 1600 行（2x）

### 同包测试

```go
// ✅ 正确：测试文件与源文件在同一包
package service

// user_service.go
type UserService struct {}

// user_service_test.go
package service  // 同一包

func TestUserService_Create(t *testing.T) {
    // 可以访问私有方法和字段
}
```

## 检查工具

### gofmt

```bash
# 检查格式
gofmt -l .

# 格式化
gofmt -w .
```

### golint

```bash
# 安装
go install golang.org/x/lint/golint@latest

# 检查
golint ./...
```

### go vet

```bash
# 静态检查
go vet ./...
```

### goimports

```bash
# 安装
go install golang.org/x/tools/cmd/goimports@latest

# 格式化 import
goimports -w .
```

## 总结

**核心规范：**
1. 使用 gofmt 格式化
2. Import 分 3 组
3. error 作为最后返回值
4. 使用驼峰命名
5. 特殊名词保持原有写法（ID, API, URL, HTTP）
6. 测试函数命名清晰
7. 提前返回，减少嵌套
8. 常量代替魔法数字
9. 测试文件 ≤ 1600 行
10. 测试函数 ≤ 160 行

---

**返回 [主文档](../SKILL.md)**
