---
name: vmedia-golang-unit-test
description: 媒资组 Go 单元测试规范，使用 goom Mocker（github.com/tencent/goom）Mock 接口/函数/结构体，When 条件匹配。dao 层用 go-sqlmock，service/plugin/engine 层用 goom。遵循 2x 倍数规则（测试函数 160 行、文件 1600 行）。当编写单测、生成测试、提升覆盖率时触发。
---

# Go 单元测试开发规范

使用 goom Mocker 库（`github.com/tencent/goom`）编写符合团队规范的高质量单元测试，支持接口/函数/结构体 Mock + When 条件匹配，**测试代码享有 2x 长度限制**。

## 触发场景

- 用户需要为 Go 项目编写或生成单元测试
- 用户请求 "生成单测"、"写单元测试"、"补充测试"、"提高覆盖率"
- 用户要求设置测试基础设施和 Mock 框架
- 用户询问如何建立团队测试标准和最佳实践
- Code Review 中评估测试质量
- 用户需要学习高级 Mocking 技术
- 用户遇到测试失败问题需要调试
- 用户要求提升测试覆盖率到特定阈值
- 用户需要 Mock 接口、函数、结构体方法
- 用户需要处理第三方库（GORM、Redis、HTTP）的测试依赖
- 用户需要批量生成整个包的测试

## 测试生成模式

### 模式选择

| 模式 | 触发条件 | 特点 | 适用场景 |
|------|---------|------|---------|
| **快速模式** | 默认 / 单个函数 | 3-5个核心用例，1次重试 | 单函数、简单逻辑 |
| **完整模式** | `--full` / 批量生成 | 5-8个全面用例，3次重试，自动补测 | 复杂函数、整包生成 |
| **扫描模式** | `--scan` | 列出可测函数及复杂度 | 批量生成前的信息收集 |
| **覆盖率模式** | `--coverage <file>` | 针对低覆盖函数，自动补测 | 提升覆盖率 |

### 自动模式判断

```
输入包含 --scan / "扫描" / "列出函数"     → 扫描模式
输入包含 --coverage / "覆盖率"           → 覆盖率模式
输入包含 --full / "批量" / 多个函数       → 完整模式
指定单个函数 / --fast                    → 快速模式（默认）
```

### 覆盖率目标

| 层级 | 目标覆盖率 | 判断规则 |
|-----|-----------|---------|
| Entity/Domain | ≥ **90%** | 路径包含 `entity` |
| Logic/Service | ≥ **80%** | 路径包含 `logic` |
| Adapter/Protocol | ≥ **70%** | 路径包含 `repo` 或 `protocol` |
| 其他 | ≥ **70%** | 默认 |

**覆盖率达标检查详细流程**：见 [reference/coverage-check.md](./reference/coverage-check.md)

## 核心原则

### 0. 覆盖率验证标准（最高优先级）

**⚠️ 强制要求：所有覆盖率验证必须使用统一的标准命令**

```bash
go test -v -covermode=count -coverprofile=cover.out.tmp -coverpkg=./... '-gcflags=all=-N -l' ./...
```

**AI 执行规则：**
1. **唯一标准**：只能使用上述命令获取覆盖率，禁止使用其他变体
2. **测试必过**：命令执行必须无错误，所有测试用例必须通过
3. **以终为准**：以该命令输出的最终整体覆盖率数字为判断依据
4. **全量检查**：不允许只检查部分包或单个文件的覆盖率
5. **达标验证**：每次生成或补充测试后，都必须执行该命令验证达标情况

### 1. 同包测试

**测试文件与被测文件在同一包中:**
```
demo/
├── service/
│   ├── policy/
│   │   ├── policy.go
│   │   └── policy_test.go      # 同一包内
```

### 2. 2x 倍数规则

**测试代码的长度限制是普通代码的 2 倍:**

| 项目 | 普通代码 | 测试代码 | 倍数 |
|------|---------|---------|------|
| **文件长度** | 800 行 | **1600 行** | 2x |
| **函数长度** | 80 行 | **160 行** | 2x |
| **嵌套深度** | 4 层 | **4 层** | 1x |

### 3. Mocker 优先（goom）

**内部代码使用 goom Mocker，第三方库用官方方案:**
```go
import "github.com/tencent/goom"

// ✅ 内部接口用 goom Mocker
projectDAO := (dao.ProjectDAO)(nil)
mock.Interface(&projectDAO).Method("GetByProjectID").Apply(...)

// ❌ 不要 Mock GORM
// mock.Interface(&gormDB).Method("Create")...

// ✅ GORM 用 go-sqlmock（与 trpc-database/gorm 官方推荐一致）
db, mock, _ := sqlmock.New()
gormDB, _ := gorm.Open(mysql.New(mysql.Config{Conn: db}), &gorm.Config{})
```

**Mock 分层策略（按测试层级选择工具）：**

| 被测层级 | Mock 什么 | Mock 工具 |
|---------|----------|----------|
| **dao 层测试** | DB 连接 | `go-sqlmock` + `gorm.Open(mysql.New(...))` |
| **service 层测试** | dao 接口 | `goom mocker` |
| **plugin 层测试** | dao/storage 接口 | `goom mocker` |
| **engine 层测试** | Plugin 接口 | `goom mocker` |

### 4. 清晰的测试结构

```
准备数据 → 创建 Mock → 创建被测对象 → 执行测试 → 验证结果
```

## 快速开始

### 技术栈

```markdown
| 组件       | 工具/库                                   | 用途                |
|-----------|------------------------------------------|---------------------|
| **测试框架** | Go testing                             | 标准测试框架         |
| **断言库**   | testify/assert, testify/require        | 简化断言             |
| **Mock框架** | goom Mocker (`github.com/tencent/goom`)| Mock 内部依赖       |
| **参数匹配** | goom arg (`github.com/tencent/goom/arg`)| When 条件的参数匹配  |
| **DB Mock**  | go-sqlmock                             | Mock 数据库         |
| **Redis Mock** | miniredis                            | Mock Redis          |
| **HTTP Mock**  | httptest                             | Mock HTTP 服务      |
```

### 标准测试函数

```go
// 命名规范: Test<结构体名>_<函数名>_<场景描述>_<期望结果>
// 测试文件: service/project_test.go（不叫 service/project_service_test.go）
func TestProjectService_GetByID_ValidID_ShouldReturnProject(t *testing.T) {
    // 测试场景:获取有效项目ID对应的项目信息
    // 前置条件:数据库中存在该项目
    // 输入数据:有效的项目ID
    // 预期结果:返回对应的项目信息

    // 1. 准备测试数据
    expected := &model.Project{
        ProjectID: "media_cover",
        Name:      "专辑项目",
        Status:    "active",
    }

    // 2. 创建 Mock（goom mocker）
    mock := mocker.Create()
    defer mock.Reset()

    projectDAO := (dao.ProjectDAO)(nil)
    mock.Interface(&projectDAO).Method("GetByProjectID").Apply(
        func(_ *mocker.IContext, ctx context.Context, projectID string) (*model.Project, error) {
            return expected, nil
        },
    )

    // 3. 创建被测对象
    svc := &ProjectService{projectDAO: projectDAO}

    // 4. 执行测试
    got, err := svc.GetByID(context.Background(), "media_cover")

    // 5. 验证结果
    assert.NoError(t, err)
    assert.NotNil(t, got)
    assert.Equal(t, expected.ProjectID, got.ProjectID)
    assert.Equal(t, expected.Name, got.Name)
}
```

## goom Mocker 核心技术

> 完整文档: `github.com/tencent/goom` README。以下为常用 API 速查。

### Technique 1: Mock 接口方法

```go
// ❌ 错误:未初始化接口
var projectDAO dao.ProjectDAO  // nil,但类型信息已丢失
mock.Interface(&projectDAO).Method("GetByProjectID")...  // 无法工作

// ✅ 正确:显式类型转换保留类型信息
projectDAO := (dao.ProjectDAO)(nil)
mock.Interface(&projectDAO).Method("GetByProjectID").Apply(
    func(_ *mocker.IContext, ctx context.Context, projectID string) (*model.Project, error) {
        return &model.Project{ProjectID: projectID}, nil
    },
)
// ⚠️ 接口 Apply 第一个参数必须是 *mocker.IContext

// 简化:固定返回值
mock.Interface(&projectDAO).Method("GetByProjectID").Return(
    &model.Project{ProjectID: "media_cover"}, nil,
)

// ✅ 条件 Mock:不同参数返回不同结果（When）
mock.Interface(&projectDAO).Method("GetByProjectID").
    When("media_cover").Return(&model.Project{Name: "专辑"}, nil).
    When("media_video").Return(&model.Project{Name: "视频"}, nil)

// ✅ 使用 arg 匹配器进行灵活匹配
import "github.com/tencent/goom/arg"

mock.Interface(&projectDAO).Method("GetByProjectID").
    When(arg.Any()).Return(&model.Project{}, nil)  // 任意参数都匹配
```

### Technique 2: Mock 结构体方法

```go
// Mock 结构体的方法
// ⚠️ 结构体 Apply 第一个参数是 receiver 类型（不是 IContext）
mock.Struct(&DataProcessor{}).Method("Process").Apply(
    func(_ *DataProcessor, data string) (string, error) {
        return "processed: " + data, nil
    },
)

// 或使用 Return 简化
mock.Struct(&DataProcessor{}).Method("Validate").Return(true, nil)

// When 条件 Mock 同样适用
mock.Struct(&DataProcessor{}).Method("Process").
    When("input-a").Return("output-a", nil).
    When("input-b").Return("output-b", nil)
```

### Technique 3: Mock 函数和变量

```go
// Mock 全局函数（Apply 无需额外首参）
mock.Func(utils.GenerateID).Return("mock-id-123")

mock.Func(utils.GenerateID).Apply(func() string {
    return "custom-id"
})

// When 条件
mock.Func(time.Now).Return(fixedTime)

// Mock 全局变量
mock.Var(&globalClient).Set(mockClient)
// ⚠️ Set 值类型必须与原变量完全匹配，否则内存错误

// Mock 未导出的函数/方法/变量
mock.ExportFunc("github.com/mooyang-code/pkg.unexportedFunc").Apply(...)
mock.ExportMethod("github.com/mooyang-code/pkg.MyStruct.unexportedMethod").Apply(...)
mock.ExportStruct("github.com/mooyang-code/pkg.unexportedStruct").Method("M").Apply(...)
mock.UnExportedVar("github.com/mooyang-code/pkg.unexportedVar").Set(val)
```

### Technique 4: 清理与生命周期

```go
// ✅ 推荐:defer Reset 清理所有 Mock
mock := mocker.Create()
defer mock.Reset()

// 单个 Mock 取消（不影响其他 Mock）
m := mock.Func(utils.GenerateID).Return("mock-id")
m.Cancel()  // 仅取消这一个

// 获取原始函数引用（在 Apply 中调用原始实现）
m := mock.Func(utils.GenerateID).Origin(&originFn)
// originFn 现在指向 Mock 之前的原始函数
```

### Apply 首参规则速查

| Mock 类型 | Apply 首参 | 示例 |
|----------|-----------|------|
| **Interface** | `*mocker.IContext` | `func(_ *mocker.IContext, ctx context.Context, ...)` |
| **Struct** | receiver 类型 | `func(_ *MyStruct, ...)` |
| **Func** | 无特殊首参 | `func(args...) returns...`（与原函数签名一致） |

### Technique 5: 第三方库 Mock 策略

```go
// ❌ 错误:Mock 第三方库
gormDB := &gorm.DB{}
mock.Interface(&gormDB).Method("Create")...  // 不推荐!

// ✅ 正确:数据库用 go-sqlmock
db, mock, err := sqlmock.New()
require.NoError(t, err)
defer db.Close()

gormDB, err := gorm.Open(mysql.New(mysql.Config{
    Conn:                      db,
    SkipInitializeWithVersion: true,
}), &gorm.Config{})

// 设置期望
rows := sqlmock.NewRows([]string{"id", "name"}).AddRow(1, "test")
mock.ExpectQuery("SELECT (.+) FROM `users`").WillReturnRows(rows)

// ✅ 正确:Redis 用 miniredis
mr, err := miniredis.Run()
require.NoError(t, err)
defer mr.Close()

client := redis.NewClient(&redis.Options{Addr: mr.Addr()})
mr.Set("test-key", "test-value")

// ✅ 正确:HTTP 用 httptest
server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    w.Write([]byte(`{"status":"ok"}`))
}))
defer server.Close()

// 好处:使用官方支持的方案,稳定性更好
```

## 常见陷阱

### Pitfall 1: 过度 Mock 第三方库

```markdown
❌ 问题:尝试 Mock 第三方库的实现细节
   - Mock GORM 的 Create/Find 等方法
   - Mock Redis client 的 Get/Set
   - 容易出现兼容性问题

✅ 解决:使用官方推荐的测试方案
   - GORM → go-sqlmock
   - Redis → miniredis
   - HTTP → httptest
   - 这些工具专为测试设计,更稳定
```

### Pitfall 2: 测试不独立

```go
// ❌ 测试之间共享状态
var sharedService *PolicyService  // 全局变量

func TestA(t *testing.T) {
    sharedService.DoSomething()  // 修改了状态
}

func TestB(t *testing.T) {
    sharedService.DoSomethingElse()  // 依赖 TestA 的状态
}

// ✅ 每个测试独立创建对象
func TestA(t *testing.T) {
    service := &PolicyService{}  // 独立实例
    service.DoSomething()
}

func TestB(t *testing.T) {
    service := &PolicyService{}  // 独立实例
    service.DoSomethingElse()
}

// ✅ 使用 testify suite 管理共同的 setup
type PolicyServiceTestSuite struct {
    suite.Suite
    service *PolicyService
}

func (s *PolicyServiceTestSuite) SetupTest() {
    s.service = &PolicyService{}  // 每个测试前重新创建
}
```

### Pitfall 3: 忘记清理 Mock

```go
// ❌ 没有清理 Mock
func TestSomething(t *testing.T) {
    mock := mocker.Create()
    mock.Func(utils.GenerateID).Return("mock-id")
    // 测试代码...
    // 忘记 Reset,影响其他测试!
}

// ✅ 使用 defer 确保清理
func TestSomething(t *testing.T) {
    mock := mocker.Create()
    defer mock.Reset()  // 测试结束时自动清理所有 Mock

    mock.Func(utils.GenerateID).Return("mock-id")
    // 测试代码...
}

// ✅ 只取消单个 Mock（其他 Mock 保留）
func TestSomething(t *testing.T) {
    mock := mocker.Create()
    defer mock.Reset()

    m := mock.Func(utils.GenerateID).Return("mock-id")
    // ... 使用 mock ...
    m.Cancel()  // 仅取消这一个，其他 Mock 不受影响
}
```

## 测试执行

### 标准覆盖率报告命令（**必须遵守**）

**⚠️ 重要：AI 必须使用以下命令生成覆盖率报告，并以该命令输出的最终整体覆盖率结果为准**

```bash
# 生成覆盖率报告（标准命令）
go test -v -covermode=count -coverprofile=cover.out.tmp -coverpkg=./... '-gcflags=all=-N -l' ./...
```

**命令要求：**
1. **必须使用此命令**生成覆盖率报告，不得随意修改参数
2. **必须确保所有测试通过**，命令执行不报错
3. **必须以命令输出的最终整体覆盖率为准**进行达标判断
4. **禁止仅通过部分测试或单个包测试**来评估覆盖率

**参数说明：**
- `-v`: 显示详细输出
- `-covermode=count`: 统计每个语句的执行次数
- `-coverprofile=cover.out.tmp`: 输出覆盖率数据到文件
- `-coverpkg=./...`: 统计所有包的覆盖率（包括依赖）
- `'-gcflags=all=-N -l'`: 禁用编译器优化和内联
- `./...`: 运行所有包的测试

**查看覆盖率详情：**
```bash
# 查看总体覆盖率
go tool cover -func=cover.out.tmp | grep total

# 生成 HTML 报告
go tool cover -html=cover.out.tmp -o coverage.html
```

### Go < 1.23 兼容命令

```bash
# 运行单个包的测试
go test -gcflags=all=-l -v ./path/to/package

# 运行所有测试
go test -gcflags=all=-l -v ./...

# 查看覆盖率（快速）
go test -gcflags=all=-l -v -cover ./...

# 生成详细覆盖率报告（推荐用标准命令）
go test -gcflags=all=-l -coverprofile=coverage.out ./...
go tool cover -html=coverage.out
```

### Go >= 1.23 兼容命令

```bash
# 运行单个包的测试
go test -gcflags="all=-N -l" -ldflags=-checklinkname=0 -v ./path/to/package

# 运行所有测试
go test -gcflags="all=-N -l" -ldflags=-checklinkname=0 -v ./...

# 查看覆盖率（快速）
go test -gcflags="all=-N -l" -ldflags=-checklinkname=0 -v -cover ./...
```

**旧版本参数说明：**
- `-gcflags=all=-l`: 禁用内联优化(Go < 1.23)
- `-gcflags="all=-N -l"`: 禁用优化和内联(Go >= 1.23)
- `-ldflags=-checklinkname=0`: 禁用 linkname 检查(Go >= 1.23)
- `-v`: 显示详细输出
- `-cover`: 显示覆盖率

## 代码风格要点

### Import 分组

```go
import (
    // 1. 标准库
    "context"
    "errors"
    "testing"

    // 2. 第三方库
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"
    "github.com/tencent/goom"

    // 3. 项目内部包
    "github.com/mooyang-code/project/dao"
    "github.com/mooyang-code/project/model"
    "github.com/mooyang-code/project/service"
)
```

### 错误处理

```go
// ✅ 正确:error 作为最后一个返回参数
func doSomething() (int, error) {
    return 0, nil
}

// ✅ 正确:独立的错误流
result, err := doSomething()
if err != nil {
    // 错误处理
    return
}
// 正常流程

// ❌ 错误:error 不是最后一个参数
func doSomething() (error, int) {
    return nil, 0
}
```

### 命名规范

```go
// ✅ 正确:驼峰式,特殊名词保持原有写法
var apiClient *http.Client
var userID int64
var URLArray []string
var HTTPServer *http.Server

// ❌ 错误:特殊名词全小写或全大写位置错误
var ApiClient *http.Client  // Api 应该是 API
var userId int64            // Id 应该是 ID
var UrlArray []string       // Url 应该是 URL
```

## 最佳实践

1. **一个测试一个场景**: 每个测试函数只测试一个具体场景,保持简单
2. **提取辅助函数**: 超过 160 行时拆分或提取辅助函数
3. **使用测试套件**: 有共同 setup/teardown 时使用 testify suite
4. **避免过度 Mock**: 只 Mock 必要的依赖,保持测试真实性
5. **独立性**: 每个测试应该能独立运行,不依赖其他测试
6. **清理资源**: 使用 `defer mock.Reset()` 确保清理
7. **表驱动测试**: 多个相似场景用表驱动测试减少重复代码
8. **有意义的断言**: 使用 `assert.Equal` 而不是 `assert.True(a == b)`
9. **完整覆盖**: 包括正常流程、边界情况、异常处理
10. **清晰注释**: 在测试开头说明测试场景、前置条件、预期结果

## 覆盖率自动补测

### 补测流程

**⚠️ 关键要求：所有覆盖率判断必须基于标准覆盖率报告命令的输出结果**

```bash
# 必须使用此命令获取覆盖率数据
go test -v -covermode=count -coverprofile=cover.out.tmp -coverpkg=./... '-gcflags=all=-N -l' ./...
```

```
运行标准覆盖率命令 → 获取整体覆盖率 → 达标? → 是 → ✅ 完成
                                      ↓
                                     否
                                      ↓
                              分析未覆盖分支
                                      ↓
                              补测轮次 < 3?
                                /        \
                              是          否
                               ↓           ↓
                          生成补测用例   ⚠️ 输出报告
                               ↓        (人工介入)
                        运行标准覆盖率命令
                               ↓
                          验证测试通过
                               ↓
                          返回检查
```

### 自动补测策略

**补测前提：确保使用标准覆盖率报告命令，且所有现有测试通过**

根据未覆盖类型生成补测用例：

| 未覆盖类型 | 补测策略 | 示例用例名 |
|-----------|---------|-----------|
| 错误处理分支 | Mock 返回 error | `error_when_db_fails` |
| 空值/nil 检查 | 传入 nil 参数 | `nil_input_returns_error` |
| 边界条件 | 边界值（0, -1, MaxInt） | `edge_case_with_zero_value` |
| switch/case | 未覆盖 case 的输入 | `case_unknown_status` |
| 提前 return | 触发提前返回的条件 | `early_return_on_empty_list` |
| context cancel | Mock context 取消 | `context_cancelled` |

**每轮补测后必须：**
1. 执行标准覆盖率报告命令验证测试通过
2. 以命令输出的整体覆盖率为准判断是否达标
3. 测试不通过则修复后重新验证

### 补测限制

- **最大补测轮次**: 3 次
- **单轮最大新增用例**: 10 个
- **超过限制后**: 输出详细报告，建议人工介入

### 补测代码示例

```go
// 错误分支补测
{
    name: "error_when_dependency_fails",
    req:  &pb.Request{ID: 1},
    mockSetup: func(m *mock.MockRepo) {
        m.EXPECT().Get(gomock.Any(), int64(1)).
            Return(nil, errors.New("database error"))
    },
    wantErr: true,
},

// 边界条件补测
{
    name: "edge_case_with_zero_value",
    req:  &pb.Request{ID: 0},
    mockSetup: func(m *mock.MockRepo) {
        // 零值不应调用依赖
    },
    wantErr:     true,
    errContains: "invalid id",
},
```

详见：[reference/coverage-check.md](./reference/coverage-check.md)

## Resources

- **[reference/coverage-check.md](./reference/coverage-check.md)**: 覆盖率达标检查与自动补测流程
- **[reference/mocker-guide.md](./reference/mocker-guide.md)**: Mocker 库详细使用指南
- **[reference/third-party-mock.md](./reference/third-party-mock.md)**: 常见第三方库的 Mock 方案
- **[reference/best-practices.md](./reference/best-practices.md)**: 测试编写的最佳实践
- **[reference/code-style.md](./reference/code-style.md)**: 完整的代码风格要求
- **[reference/ai-guide.md](./reference/ai-guide.md)**: AI 测试生成指导原则
- **[examples/](./examples/)**: 完整示例代码
  - [基础测试示例](./examples/basic-test.md)
  - [Mock 使用示例](./examples/mock-examples.md)
  - [表驱动测试](./examples/table-driven.md)
  - [测试套件示例](./examples/test-suite.md)
