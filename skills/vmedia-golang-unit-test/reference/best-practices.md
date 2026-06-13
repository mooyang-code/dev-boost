# 测试编写最佳实践

本文档总结 Go 单元测试的最佳实践和常见陷阱。

## 测试设计原则

### 1. 测试独立性

每个测试应该能够独立运行，不依赖其他测试。

```go
// ❌ 错误：测试之间共享状态
var sharedDB *gorm.DB

func TestA(t *testing.T) {
    sharedDB.Create(&User{Name: "test"})
}

func TestB(t *testing.T) {
    // 依赖 TestA 创建的数据
    var user User
    sharedDB.First(&user, "name = ?", "test")
}
```

```go
// ✅ 正确：每个测试独立
func TestA(t *testing.T) {
    db := setupTestDB(t)
    defer cleanupDB(db)

    db.Create(&User{Name: "test"})
    // ...
}

func TestB(t *testing.T) {
    db := setupTestDB(t)
    defer cleanupDB(db)

    db.Create(&User{Name: "test"})  // 自己准备数据
    var user User
    db.First(&user, "name = ?", "test")
    // ...
}
```

### 2. 一个测试一个场景

每个测试函数只测试一个具体场景。

```go
// ❌ 错误：一个测试测试多个场景
func TestUserService_CRUD(t *testing.T) {
    service := NewUserService()

    // Create
    user := service.Create(&User{Name: "test"})
    assert.NotNil(t, user.ID)

    // Read
    found, _ := service.GetByID(user.ID)
    assert.Equal(t, "test", found.Name)

    // Update
    user.Name = "updated"
    service.Update(user)

    // Delete
    service.Delete(user.ID)
}
```

```go
// ✅ 正确：每个场景独立测试
func TestUserService_Create_ValidUser_ShouldSuccess(t *testing.T) {
    service := NewUserService()

    user := service.Create(&User{Name: "test"})

    assert.NotNil(t, user.ID)
    assert.Equal(t, "test", user.Name)
}

func TestUserService_GetByID_ExistingUser_ShouldReturnUser(t *testing.T) {
    service := NewUserService()
    created := service.Create(&User{Name: "test"})

    found, err := service.GetByID(created.ID)

    assert.NoError(t, err)
    assert.Equal(t, created.ID, found.ID)
}

func TestUserService_GetByID_NonExistingUser_ShouldReturnError(t *testing.T) {
    service := NewUserService()

    _, err := service.GetByID(999)

    assert.Error(t, err)
}
```

### 3. 测试命名要清晰

使用格式：`Test<结构体名>_<函数名>_<场景描述>_<期望结果>`

```go
// ✅ 好的命名
func TestUserService_Create_ValidUser_ShouldSuccess(t *testing.T)
func TestUserService_Create_DuplicateEmail_ShouldReturnError(t *testing.T)
func TestUserService_Create_EmptyName_ShouldReturnValidationError(t *testing.T)

// ❌ 不好的命名
func TestCreate(t *testing.T)
func TestCreate1(t *testing.T)
func TestCreate2(t *testing.T)
```

### 4. 使用表驱动测试

对于多个相似场景，使用表驱动测试。

```go
func TestValidateEmail(t *testing.T) {
    tests := []struct {
        name    string
        email   string
        wantErr bool
    }{
        {
            name:    "valid_email",
            email:   "test@example.com",
            wantErr: false,
        },
        {
            name:    "invalid_email_no_at",
            email:   "testexample.com",
            wantErr: true,
        },
        {
            name:    "invalid_email_no_domain",
            email:   "test@",
            wantErr: true,
        },
        {
            name:    "empty_email",
            email:   "",
            wantErr: true,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            err := ValidateEmail(tt.email)

            if tt.wantErr {
                assert.Error(t, err)
            } else {
                assert.NoError(t, err)
            }
        })
    }
}
```

## 函数长度控制策略

### 测试函数长度限制

**规则：** 测试函数体最多 **160 行**（普通函数的 2 倍）

### 策略 1：提取辅助函数

```go
// ❌ 超长测试函数（200+ 行）
func TestComplexFlow(t *testing.T) {
    // 准备测试数据（50 行）
    user := &User{...}
    order := &Order{...}
    // ...

    // 设置 Mock（60 行）
    mock := mocker.Create()
    defer mock.Reset()
    // ...

    // 执行测试（40 行）
    // ...

    // 验证结果（50 行）
    // ...
}
```

```go
// ✅ 提取辅助函数
func TestComplexFlow(t *testing.T) {
    // 准备测试数据
    user, order := prepareTestData()

    // 设置 Mock
    mock := setupMocks(t)
    defer mock.Reset()

    // 执行测试
    result, err := executeFlow(user, order)

    // 验证结果
    verifyResult(t, result, err)
}

func prepareTestData() (*User, *Order) {
    // 50 行数据准备
    return user, order
}

func setupMocks(t *testing.T) *mocker.Mocker {
    // 60 行 Mock 设置
    return mock
}

func verifyResult(t *testing.T, result *Result, err error) {
    // 50 行验证逻辑
}
```

### 策略 2：拆分测试场景

```go
// ❌ 一个测试测试多个场景（180 行）
func TestUserService_Operations(t *testing.T) {
    // 测试创建（60 行）
    // ...

    // 测试更新（60 行）
    // ...

    // 测试删除（60 行）
    // ...
}
```

```go
// ✅ 拆分为多个测试
func TestUserService_Create(t *testing.T) {
    // 60 行
}

func TestUserService_Update(t *testing.T) {
    // 60 行
}

func TestUserService_Delete(t *testing.T) {
    // 60 行
}
```

### 策略 3：使用 testify suite

对于有共同 setup/teardown 的测试：

```go
type UserServiceTestSuite struct {
    suite.Suite
    service *UserService
    mock    *mocker.Mocker
}

func (s *UserServiceTestSuite) SetupTest() {
    // 每个测试前执行
    s.mock = mocker.Create()
    s.service = NewUserService()
}

func (s *UserServiceTestSuite) TearDownTest() {
    // 每个测试后执行
    s.mock.Reset()
}

func (s *UserServiceTestSuite) TestCreate_ValidUser() {
    // 测试逻辑
}

func (s *UserServiceTestSuite) TestCreate_InvalidUser() {
    // 测试逻辑
}

func TestUserServiceSuite(t *testing.T) {
    suite.Run(t, new(UserServiceTestSuite))
}
```

## 测试数据管理

### 1. 测试数据工厂

```go
// 定义测试数据构造函数
func NewTestUser(opts ...func(*User)) *User {
    user := &User{
        ID:    1,
        Name:  "test",
        Email: "test@example.com",
        Age:   20,
    }

    for _, opt := range opts {
        opt(user)
    }

    return user
}

// 使用
func TestUserService_Create(t *testing.T) {
    // 默认用户
    user1 := NewTestUser()

    // 自定义用户
    user2 := NewTestUser(func(u *User) {
        u.Name = "custom"
        u.Age = 30
    })

    // ...
}
```

### 2. 测试数据构建器

```go
type UserBuilder struct {
    user *User
}

func NewUserBuilder() *UserBuilder {
    return &UserBuilder{
        user: &User{
            ID:    1,
            Name:  "test",
            Email: "test@example.com",
        },
    }
}

func (b *UserBuilder) WithName(name string) *UserBuilder {
    b.user.Name = name
    return b
}

func (b *UserBuilder) WithEmail(email string) *UserBuilder {
    b.user.Email = email
    return b
}

func (b *UserBuilder) Build() *User {
    return b.user
}

// 使用
func TestUserService_Create(t *testing.T) {
    user := NewUserBuilder().
        WithName("custom").
        WithEmail("custom@example.com").
        Build()

    // ...
}
```

## Mock 使用原则

### 1. 只 Mock 必要的依赖

```go
// ❌ 过度 Mock
func TestUserService_GetUser(t *testing.T) {
    mock := mocker.Create()
    defer mock.Reset()

    // 只需要 userRepo.GetByID，但 Mock 了所有方法
    mock.Interface(&userRepo).Method("GetByID").Return(...)
    mock.Interface(&userRepo).Method("Create").Return(...)
    mock.Interface(&userRepo).Method("Update").Return(...)
    mock.Interface(&userRepo).Method("Delete").Return(...)
    mock.Interface(&orderRepo).Method("GetByUserID").Return(...)
    // ...
}
```

```go
// ✅ 只 Mock 需要的
func TestUserService_GetUser(t *testing.T) {
    mock := mocker.Create()
    defer mock.Reset()

    // 只 Mock 测试用到的方法
    mock.Interface(&userRepo).Method("GetByID").Return(...)
}
```

### 2. Mock 应该模拟真实行为

```go
// ❌ Mock 行为不真实
mock.Interface(&userRepo).Method("GetByID").Return(
    &User{ID: 1},  // 总是返回成功
    nil,
)
```

```go
// ✅ Mock 行为符合业务逻辑
mock.Interface(&userRepo).Method("GetByID").Apply(
    func(_ *mocker.IContext, ctx context.Context, id int64) (*User, error) {
        if id <= 0 {
            return nil, errors.New("invalid id")
        }
        if id == 999 {
            return nil, errors.New("not found")
        }
        return &User{ID: id}, nil
    },
)
```

### 3. 避免 Mock 简单函数

```go
// ❌ 没必要 Mock 纯函数
func add(a, b int) int {
    return a + b
}

mock.Func(add).Return(5)  // 完全没必要
```

```go
// ✅ 直接调用
result := add(2, 3)  // 简单纯函数无需 Mock
```

## 常见陷阱和解决方案

### 陷阱 1：忘记清理 Mock

```go
// ❌ 忘记清理
func TestSomething(t *testing.T) {
    mock := mocker.Create()
    mock.Func(utils.GenerateID).Return("mock-id")

    // 测试逻辑
    // ...

    // 忘记 Reset()，影响其他测试！
}
```

```go
// ✅ 使用 defer 确保清理
func TestSomething(t *testing.T) {
    mock := mocker.Create()
    defer mock.Reset()  // 即使 panic 也会执行

    mock.Func(utils.GenerateID).Return("mock-id")

    // 测试逻辑
    // ...
}
```

### 陷阱 2：测试依赖执行顺序

```go
// ❌ 测试依赖顺序
func TestA(t *testing.T) {
    globalVar = "A"
}

func TestB(t *testing.T) {
    // 依赖 TestA 先执行
    assert.Equal(t, "A", globalVar)
}
```

```go
// ✅ 测试独立
func TestA(t *testing.T) {
    localVar := "A"
    // ...
}

func TestB(t *testing.T) {
    localVar := "B"  // 自己准备数据
    // ...
}
```

### 陷阱 3：过度断言

```go
// ❌ 过度断言内部实现
func TestUserService_Create(t *testing.T) {
    service := &UserService{}
    user := &User{Name: "test"}

    result := service.Create(user)

    // 断言太多内部实现细节
    assert.NotNil(t, service.lastCreatedID)
    assert.Equal(t, 1, service.createCallCount)
    assert.True(t, service.validationCalled)
    // ...
}
```

```go
// ✅ 只断言公开契约
func TestUserService_Create(t *testing.T) {
    service := &UserService{}
    user := &User{Name: "test"}

    result := service.Create(user)

    // 只断言公开行为和结果
    assert.NotNil(t, result.ID)
    assert.Equal(t, "test", result.Name)
}
```

### 陷阱 4：测试名称不清晰

```go
// ❌ 不清晰的测试名称
func TestCreate(t *testing.T) {}
func TestCreate2(t *testing.T) {}
func TestError(t *testing.T) {}
```

```go
// ✅ 清晰的测试名称
func TestUserService_Create_ValidUser_ShouldSuccess(t *testing.T) {}
func TestUserService_Create_DuplicateEmail_ShouldReturnError(t *testing.T) {}
func TestUserService_Create_EmptyName_ShouldReturnValidationError(t *testing.T) {}
```

### 陷阱 5：忽略错误处理测试

```go
// ❌ 只测试成功路径
func TestUserService_GetUser(t *testing.T) {
    service := &UserService{}

    user, _ := service.GetUser(1)  // 忽略 error

    assert.Equal(t, "test", user.Name)
}
```

```go
// ✅ 测试错误路径
func TestUserService_GetUser_Success(t *testing.T) {
    service := &UserService{}

    user, err := service.GetUser(1)

    assert.NoError(t, err)
    assert.Equal(t, "test", user.Name)
}

func TestUserService_GetUser_NotFound(t *testing.T) {
    service := &UserService{}

    _, err := service.GetUser(999)

    assert.Error(t, err)
    assert.Contains(t, err.Error(), "not found")
}

func TestUserService_GetUser_DatabaseError(t *testing.T) {
    // Mock 数据库错误
    // ...
}
```

## 断言最佳实践

### 使用合适的断言方法

```go
// ❌ 不好的断言
assert.True(t, user.Name == "test")  // 错误信息不清晰
assert.True(t, len(list) > 0)
assert.True(t, err != nil)
```

```go
// ✅ 好的断言
assert.Equal(t, "test", user.Name)  // 清晰的错误信息
assert.NotEmpty(t, list)
assert.Error(t, err)
```

### require vs assert

```go
// ✅ 使用 require 处理致命错误
func TestUserService_GetUser(t *testing.T) {
    service := &UserService{}

    user, err := service.GetUser(1)
    require.NoError(t, err)  // 如果有错误，停止测试

    // 后续断言依赖 user 不为 nil
    assert.Equal(t, "test", user.Name)  // 不会 panic
}
```

```go
// ❌ 使用 assert 可能导致 panic
func TestUserService_GetUser(t *testing.T) {
    service := &UserService{}

    user, err := service.GetUser(1)
    assert.NoError(t, err)  // 即使有错误，继续执行

    // 如果 user 为 nil，这里会 panic
    assert.Equal(t, "test", user.Name)  // panic!
}
```

## 测试覆盖率

### 合理的覆盖率目标

| 代码层级 | 最低覆盖率 | 原因 |
|---------|-----------|------|
| Entity/Domain | ≥ 90% | 核心业务逻辑，必须充分测试 |
| Logic/Service | ≥ 80% | 业务逻辑层，需要全面测试 |
| Adapter/Protocol | ≥ 70% | 适配层，重点测试关键路径 |

### 不要为了覆盖率而测试

```go
// ❌ 无意义的测试
func TestGetter(t *testing.T) {
    user := &User{Name: "test"}
    assert.Equal(t, "test", user.GetName())  // 只是简单的 getter
}
```

```go
// ✅ 测试有价值的行为
func TestUser_ValidateName(t *testing.T) {
    user := &User{Name: ""}
    err := user.Validate()
    assert.Error(t, err)  // 测试业务逻辑
}
```

## 性能优化

### 1. 并行测试

```go
func TestUserService_Create(t *testing.T) {
    t.Parallel()  // 标记为可并行

    // 测试逻辑（确保测试独立）
    // ...
}
```

**注意：** 使用 Mocker Mock 全局函数/变量时，不能使用 `t.Parallel()`

### 2. 避免重复的 Setup

```go
// ❌ 每个测试都重复 setup
func TestA(t *testing.T) {
    db := setupDB()  // 慢
    defer db.Close()
    // ...
}

func TestB(t *testing.T) {
    db := setupDB()  // 慢
    defer db.Close()
    // ...
}
```

```go
// ✅ 使用 testify suite 共享 setup
type ServiceTestSuite struct {
    suite.Suite
    db *gorm.DB
}

func (s *ServiceTestSuite) SetupSuite() {
    // 整个 suite 执行一次
    s.db = setupDB()
}

func (s *ServiceTestSuite) TearDownSuite() {
    s.db.Close()
}

func (s *ServiceTestSuite) TestA() {
    // 使用 s.db
}

func (s *ServiceTestSuite) TestB() {
    // 使用 s.db
}
```

## 总结

**核心原则：**
1. 测试应该独立、可重复
2. 一个测试一个场景
3. 命名清晰，表达意图
4. 只 Mock 必要的依赖
5. 测试公开契约，不是实现细节
6. 重视错误路径测试
7. 提取辅助函数控制长度
8. 使用合适的断言方法
9. 合理设置覆盖率目标
10. 保持测试简单、易懂

---

**返回 [主文档](../SKILL.md)**
