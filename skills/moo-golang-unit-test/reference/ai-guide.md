# AI 测试生成指导原则

本文档为 AI 辅助生成 Go 单元测试提供指导原则，确保生成的测试代码质量高、可维护。

## ⚠️ 首要规则：标准覆盖率验证

**AI 生成测试时，必须遵守以下覆盖率验证规则：**

```bash
# 标准覆盖率命令（唯一标准）
go test -v -covermode=count -coverprofile=cover.out.tmp -coverpkg=./... '-gcflags=all=-N -l' ./...
```

**强制要求：**
- ✅ 必须使用此命令验证测试和覆盖率
- ✅ 必须确保所有测试通过（命令执行无错误）
- ✅ 必须以此命令输出的整体覆盖率为准判断达标
- ❌ 禁止使用其他命令或参数变体
- ❌ 禁止仅验证部分包的覆盖率

**验证时机：**
1. 生成测试代码后
2. 每轮补测后
3. 最终交付前

## 核心原则

### 1. 安全第一

**在生成代码前必须：**
- 充分理解被测函数的业务逻辑
- 识别所有外部依赖
- 确认 Mock 策略的正确性
- 验证测试用例的完整性

**禁止：**
- 猜测函数行为
- 使用错误的 Mock 方式
- 生成无法编译的代码
- 忽略错误处理路径

### 2. 质量优先

**生成的测试必须：**
- 能够编译通过
- 能够运行成功
- 测试用例完整（正常+异常+边界）
- 代码风格符合规范
- Mock 使用正确

## 测试生成策略

### 阶段 1：分析被测函数

```
1. 读取被测函数源码
2. 识别函数签名
   - 参数类型和数量
   - 返回值类型
   - 是否有 context.Context
   - 是否返回 error
3. 识别依赖
   - 接口依赖（需要 Mock）
   - 结构体依赖（可能需要 Mock）
   - 全局函数依赖（可能需要 Mock）
   - 第三方库依赖（使用官方测试方案）
4. 分析业务逻辑
   - 正常流程
   - 错误处理分支
   - 边界条件
   - 特殊情况
```

### 阶段 2：设计测试用例

```
根据业务逻辑设计测试用例：

1. 正常流程（至少 1 个）
   - 有效输入，成功输出
   - 验证核心业务逻辑

2. 错误处理（每个错误分支 1 个）
   - 参数校验失败
   - 依赖调用失败
   - 业务规则违反
   - 系统异常

3. 边界条件（根据需要）
   - 空值/nil
   - 零值
   - 极端值（MaxInt, MinInt）
   - 空切片/空 map

4. 特殊场景（根据业务）
   - 并发场景
   - 超时场景
   - Context 取消
```

### 阶段 3：生成测试代码

```
按照标准结构生成：

1. 包声明和 import
2. 测试函数
   - 遵循命名规范
   - 添加测试注释
3. 准备测试数据
4. 设置 Mock
   - 选择正确的 Mock 方式
   - 设置合理的 Mock 行为
5. 创建被测对象
6. 执行测试
7. 验证结果
   - 使用合适的断言
   - 验证错误信息
```

### 阶段 4：验证和优化

**⚠️ 关键：必须使用标准覆盖率命令进行验证**

```bash
# 1. 语法检查
go vet ./...

# 2. 运行测试并生成覆盖率报告（标准命令）
go test -v -covermode=count -coverprofile=cover.out.tmp -coverpkg=./... '-gcflags=all=-N -l' ./...

# 3. 检查整体覆盖率（以此为准判断达标）
go tool cover -func=cover.out.tmp | grep total

# 4. 生成 HTML 报告分析未覆盖分支
go tool cover -html=cover.out.tmp -o coverage.html
```

**验证要求：**
1. 所有测试必须通过（命令执行无错误）
2. 以标准命令输出的整体覆盖率为准判断达标
3. 覆盖率未达标时，进入自动补测流程
4. 代码审查
   - 检查风格规范
   - 检查函数长度
   - 检查 Mock 使用
5. 优化
   - 提取重复代码
   - 简化复杂逻辑
   - 添加必要注释

## 生成流程示例

### 示例：为 UserService.GetUser 生成测试

**步骤 1：分析函数**

```go
// 被测函数
type UserService struct {
    repo UserRepo
}

func (s *UserService) GetUser(ctx context.Context, id int64) (*User, error) {
    if id <= 0 {
        return nil, errors.New("invalid id")
    }

    user, err := s.repo.GetByID(ctx, id)
    if err != nil {
        return nil, fmt.Errorf("failed to get user: %w", err)
    }

    return user, nil
}
```

**分析结果：**
- 参数：`ctx context.Context`, `id int64`
- 返回：`*User`, `error`
- 依赖：`UserRepo` 接口（需要 Mock）
- 业务逻辑：
  - 校验 id > 0
  - 调用 repo.GetByID
  - 返回用户或错误

**步骤 2：设计测试用例**

```
1. normal_with_valid_id - 正常流程，有效 ID
2. error_when_id_is_zero - 边界条件，ID 为 0
3. error_when_id_is_negative - 边界条件，ID 为负数
4. error_when_repo_fails - 错误处理，repo 调用失败
5. error_when_user_not_found - 错误处理，用户不存在
```

**步骤 3：生成测试代码**

```go
package service

import (
    "context"
    "errors"
    "testing"

    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"
    "github.com/tencent/goom"

    "github.com/mooyang-code/project/model"
)

func TestUserService_GetUser(t *testing.T) {
    tests := []struct {
        name      string
        id        int64
        mockSetup func(*mocker.Mocker) UserRepo
        wantUser  *User
        wantErr   bool
        errMsg    string
    }{
        {
            name: "normal_with_valid_id",
            id:   1,
            mockSetup: func(mock *mocker.Mocker) UserRepo {
                repo := (UserRepo)(nil)
                mock.Interface(&repo).Method("GetByID").Return(
                    &User{ID: 1, Name: "test"},
                    nil,
                )
                return repo
            },
            wantUser: &User{ID: 1, Name: "test"},
            wantErr:  false,
        },
        {
            name:      "error_when_id_is_zero",
            id:        0,
            mockSetup: func(mock *mocker.Mocker) UserRepo {
                return (UserRepo)(nil)  // 不会调用 repo
            },
            wantErr: true,
            errMsg:  "invalid id",
        },
        {
            name:      "error_when_id_is_negative",
            id:        -1,
            mockSetup: func(mock *mocker.Mocker) UserRepo {
                return (UserRepo)(nil)
            },
            wantErr: true,
            errMsg:  "invalid id",
        },
        {
            name: "error_when_repo_fails",
            id:   1,
            mockSetup: func(mock *mocker.Mocker) UserRepo {
                repo := (UserRepo)(nil)
                mock.Interface(&repo).Method("GetByID").Return(
                    nil,
                    errors.New("database error"),
                )
                return repo
            },
            wantErr: true,
            errMsg:  "failed to get user",
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            // 设置 Mock
            mock := mocker.Create()
            defer mock.Reset()

            repo := tt.mockSetup(mock)

            // 创建 Service
            service := &UserService{repo: repo}

            // 执行测试
            got, err := service.GetUser(context.Background(), tt.id)

            // 验证错误
            if tt.wantErr {
                require.Error(t, err)
                assert.Contains(t, err.Error(), tt.errMsg)
                return
            }

            // 验证结果
            require.NoError(t, err)
            assert.Equal(t, tt.wantUser.ID, got.ID)
            assert.Equal(t, tt.wantUser.Name, got.Name)
        })
    }
}
```

**步骤 4：验证和优化**

**⚠️ 必须使用标准覆盖率命令验证**

```bash
# 1. 语法检查
go vet ./...

# 2. 运行测试并生成覆盖率报告（标准命令）
go test -v -covermode=count -coverprofile=cover.out.tmp -coverpkg=./... '-gcflags=all=-N -l' ./...

# 3. 检查整体覆盖率（以此结果为准）
go tool cover -func=cover.out.tmp | grep total
```

**验证要求：**
- ✅ 所有测试通过（命令执行无错误）
- ✅ 以标准命令输出的整体覆盖率为准
- ✅ 覆盖率未达标时，自动进入补测流程

## Mock 使用指南

### 选择正确的 Mock 方式

```
决策树：

被测依赖是什么？
├─ 内部接口 → 使用 Mocker Mock 接口
├─ 内部结构体 → 使用 Mocker Mock 结构体方法
├─ 全局函数 → 使用 Mocker Mock 函数
├─ GORM → 使用 go-sqlmock
├─ Redis → 使用 miniredis
├─ HTTP Client → 使用 httptest
└─ 其他第三方库 → 查阅官方测试方案
```

### 接口 Mock 模板

```go
// 1. 创建 Mock
mock := mocker.Create()
defer mock.Reset()

// 2. Mock 接口
repo := (UserRepo)(nil)  // ⚠️ 必须类型转换

// 3. 设置 Mock 行为
mock.Interface(&repo).Method("GetByID").Apply(
    func(_ *mocker.IContext, ctx context.Context, id int64) (*User, error) {
        // ⚠️ 第一个参数必须是 *mocker.IContext
        if id == 1 {
            return &User{ID: 1, Name: "test"}, nil
        }
        return nil, errors.New("not found")
    },
)

// 或使用简化语法
mock.Interface(&repo).Method("GetByID").Return(
    &User{ID: 1, Name: "test"},
    nil,
)

// 4. 注入到被测对象
service := &Service{repo: repo}
```

### 第三方库 Mock 模板

```go
// ❌ 错误：直接 Mock GORM
// gormDB := &gorm.DB{}
// mock.Interface(&gormDB).Method("Create")...

// ✅ 正确：使用 go-sqlmock
db, sqlMock, err := sqlmock.New()
require.NoError(t, err)
defer db.Close()

gormDB, err := gorm.Open(mysql.New(mysql.Config{
    Conn:                      db,
    SkipInitializeWithVersion: true,
}), &gorm.Config{})
require.NoError(t, err)

// 设置期望
sqlMock.ExpectQuery("SELECT (.+) FROM users").
    WillReturnRows(sqlmock.NewRows([]string{"id", "name"}).AddRow(1, "test"))

// 使用
repo := &UserRepo{db: gormDB}
```

## 质量检查清单

### 代码生成前

- [ ] 已读取并理解被测函数源码
- [ ] 已识别所有外部依赖
- [ ] 已设计完整的测试用例（正常+异常+边界）
- [ ] 已确定正确的 Mock 策略

### 代码生成后

- [ ] 代码能够编译通过（`go build`）
- [ ] 代码通过静态检查（`go vet`）
- [ ] 测试能够运行成功（`go test`）
- [ ] 测试覆盖率达标
- [ ] Import 分组正确
- [ ] 命名符合规范
- [ ] 函数长度 ≤ 160 行
- [ ] 使用了 `defer mock.Reset()`
- [ ] 错误处理完整
- [ ] 断言使用正确（require vs assert）

## 常见错误和修复

### 错误 1：接口 Mock 不生效

```go
// ❌ 错误：类型信息丢失
var userRepo UserRepo
mock.Interface(&userRepo).Method("GetByID")...  // 不生效！

// ✅ 修复：使用类型转换
userRepo := (UserRepo)(nil)
mock.Interface(&userRepo).Method("GetByID")...
```

### 错误 2：Apply 参数错误

```go
// ❌ 错误：缺少 *mocker.IContext 参数
mock.Interface(&repo).Method("GetByID").Apply(
    func(ctx context.Context, id int64) (*User, error) {
        return &User{}, nil
    },
)

// ✅ 修复：添加 *mocker.IContext 作为第一个参数
mock.Interface(&repo).Method("GetByID").Apply(
    func(_ *mocker.IContext, ctx context.Context, id int64) (*User, error) {
        return &User{}, nil
    },
)
```

### 错误 3：忘记清理 Mock

```go
// ❌ 错误：忘记 Reset
func TestSomething(t *testing.T) {
    mock := mocker.Create()
    // 忘记 defer mock.Reset()
    // ...
}

// ✅ 修复：使用 defer
func TestSomething(t *testing.T) {
    mock := mocker.Create()
    defer mock.Reset()
    // ...
}
```

### 错误 4：直接 Mock 第三方库

```go
// ❌ 错误：直接 Mock GORM
gormDB := &gorm.DB{}
mock.Interface(&gormDB).Method("Create")...

// ✅ 修复：使用 go-sqlmock
db, mock, _ := sqlmock.New()
gormDB, _ := gorm.Open(mysql.New(mysql.Config{Conn: db}), &gorm.Config{})
```

### 错误 5：断言使用错误

```go
// ❌ 错误：可能导致 panic
user, err := service.GetUser(1)
assert.NoError(t, err)
assert.Equal(t, "test", user.Name)  // 如果 err != nil，user 是 nil，panic!

// ✅ 修复：使用 require 处理致命错误
user, err := service.GetUser(1)
require.NoError(t, err)  // 失败则停止
assert.Equal(t, "test", user.Name)  // 安全
```

## 覆盖率自动补测

### 补测触发条件

**⚠️ 补测必须基于标准覆盖率命令的输出结果**

```bash
# 标准覆盖率命令（必须使用）
go test -v -covermode=count -coverprofile=cover.out.tmp -coverpkg=./... '-gcflags=all=-N -l' ./...
```

```
运行标准覆盖率命令 → 检查整体覆盖率 → 未达标？
                                      ↓
                                     是
                                      ↓
                              分析未覆盖分支
                                      ↓
                              生成补测用例
                                      ↓
                          运行标准覆盖率命令验证
                                      ↓
                              轮次 < 3？
                                /      \
                              是        否
                               ↓         ↓
                           继续补测   输出报告
```

**补测流程要求：**
1. 每轮补测前：使用标准命令获取当前覆盖率
2. 生成补测用例：针对未覆盖分支设计测试用例
3. 每轮补测后：使用标准命令验证测试通过且覆盖率提升
4. 以标准命令输出的整体覆盖率为准判断是否达标

### 补测用例类型

| 未覆盖类型 | 生成策略 | 示例用例名 |
|-----------|---------|-----------|
| 错误处理分支 | Mock 返回 error | `error_when_db_fails` |
| nil 检查 | 传入 nil | `nil_input_returns_error` |
| 边界条件 | 边界值 | `edge_case_with_zero_value` |
| switch case | 未覆盖的 case | `case_unknown_status` |
| 提前 return | 触发条件 | `early_return_on_empty_list` |

详见：[覆盖率达标检查](./coverage-check.md)

## 输出格式

### 成功输出

```markdown
## ✅ 测试生成成功

### 生成文件
- `service/user_service_test.go` (新增)

### 测试统计
- 测试函数: 1
- 测试用例: 5
- 覆盖率: 85.2%

### 测试用例
1. normal_with_valid_id - 正常流程
2. error_when_id_is_zero - 边界条件
3. error_when_id_is_negative - 边界条件
4. error_when_repo_fails - 错误处理
5. error_when_user_not_found - 错误处理

### 运行测试
```bash
# 使用标准覆盖率命令
go test -v -covermode=count -coverprofile=cover.out.tmp -coverpkg=./... '-gcflags=all=-N -l' ./service

# 查看覆盖率
go tool cover -func=cover.out.tmp | grep total
```
```

### 失败输出

```markdown
## ❌ 测试生成失败

### 错误信息
Mock 设置错误：接口 UserRepo 未正确初始化

### 问题分析
在 line 25:
```go
var userRepo UserRepo  // 应该使用类型转换
mock.Interface(&userRepo)...
```

### 建议修复
```go
userRepo := (UserRepo)(nil)  // 使用类型转换保留类型信息
mock.Interface(&userRepo)...
```

### 参考文档
- [Mocker 使用指南](./mocker-guide.md)
```

## 总结

**AI 生成测试的核心要点：**
1. 充分分析被测函数
2. 设计完整的测试用例
3. 选择正确的 Mock 方式
4. 生成符合规范的代码
5. 验证代码质量
6. 自动补测提升覆盖率
7. 提供清晰的输出和错误信息

**记住：**
- 安全第一，质量优先
- 理解后再生成，不要猜测
- Mock 使用要正确
- 测试用例要完整
- 代码风格要规范
- 验证要充分

---

**返回 [主文档](../SKILL.md)**
