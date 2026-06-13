# Go 单元测试开发技能包

本技能包整合了 Go 单元测试开发的完整规范，基于腾讯 Go 编码规范和 GOOM Mocker 最佳实践。支持**手动编写**和**AI 辅助生成**两种模式，提供覆盖率自动补测机制。

## 目录结构

```
golang-unit-test/
├── SKILL.md                  # 主技能文档(快速开始)
├── README.md                 # 本文件
├── reference/                # 详细参考文档
│   ├── coverage-check.md     # 覆盖率达标检查与自动补测
│   ├── mocker-guide.md       # Mocker 使用详细指南
│   ├── third-party-mock.md   # 第三方库 Mock 策略
│   ├── best-practices.md     # 测试编写最佳实践
│   ├── code-style.md         # 代码风格完整规范
│   └── ai-guide.md           # AI 测试生成指导
└── examples/                 # 示例代码
    ├── basic-test.md         # 基础测试示例
    ├── mock-examples.md      # Mock 使用示例
    ├── table-driven.md       # 表驱动测试
    └── test-suite.md         # 测试套件示例
```

## 快速开始

### 1. 新手入门

如果你是第一次编写 Go 单元测试:

1. **[SKILL.md](./SKILL.md)** - 阅读主技能文档
   - 核心规范快速参考
   - Mocker 快速使用
   - 运行测试的命令

2. **[基础测试示例](./examples/basic-test.md)** - 查看完整示例
   - 简单的单元测试示例
   - Mock 使用示例
   - 断言使用示例

3. **[Mocker 使用指南](./reference/mocker-guide.md)** - 深入学习 Mock
   - 接口 Mock
   - 结构体 Mock
   - 函数 Mock
   - 高级用法

### 2. 进阶学习

当你熟悉基础后:

1. **[第三方库 Mock](./reference/third-party-mock.md)** - 学习正确的 Mock 方式
   - 数据库 Mock (sqlmock)
   - Redis Mock (miniredis)
   - HTTP Mock (httptest)

2. **[最佳实践](./reference/best-practices.md)** - 提升测试质量
   - 测试设计原则
   - 常见陷阱
   - 性能优化

3. **[代码风格规范](./reference/code-style.md)** - 规范代码
   - Import 规范
   - 错误处理
   - 命名规范
   - 控制结构

### 3. 高级应用

#### 覆盖率提升

**[覆盖率达标检查](./reference/coverage-check.md)** - 自动化覆盖率提升
- 覆盖率目标分层策略（Entity 90%, Logic 80%, Protocol 70%）
- 自动补测流程（最多3轮）
- 未覆盖分支分析
- 智能补测用例生成

#### AI 辅助生成

**[AI 生成指导](./reference/ai-guide.md)** - AI 测试生成规范
- 安全的测试生成流程
- 质量控制策略
- 常见问题处理

## 核心特性

### 1. 测试编写规范

- **2x 倍数规则**: 测试函数 160 行、测试文件 1600 行
- **同包测试**: 测试文件与被测文件在同一包
- **Mocker 优先**: 内部代码用 Mocker，第三方库用官方方案
- **清晰结构**: 准备数据 → Mock → 执行 → 验证

### 2. 测试生成模式

| 模式 | 特点 | 适用场景 |
|------|------|---------|
| **快速模式** | 3-5个核心用例，1次重试 | 单函数、简单逻辑 |
| **完整模式** | 5-8个全面用例，3次重试，自动补测 | 复杂函数、整包生成 |
| **扫描模式** | 列出可测函数及复杂度 | 批量生成前信息收集 |
| **覆盖率模式** | 针对低覆盖函数补测 | 提升覆盖率 |

### 3. 覆盖率自动补测

- **分层目标**: Entity 90%, Logic 80%, Protocol 70%
- **智能补测**: 根据未覆盖类型自动生成用例
- **限制机制**: 最多3轮补测，单轮最多10个用例
- **人工介入**: 超过限制后输出详细报告

## 核心规范摘要

### 文件和函数限制

| 项目 | 普通代码 | 测试代码 |
|------|---------|---------|
| 文件长度 | 800 行 | **1600 行** |
| 函数长度 | 80 行 | **160 行** |
| 嵌套深度 | 4 层 | 4 层 |

### 命名规范

```go
// 测试函数命名
func Test<结构体名>_<函数名>_<场景描述>_<期望结果>(t *testing.T)

// 示例
func TestPolicyService_GetPolicy_ValidPolicyID_ShouldReturnPolicy(t *testing.T)
func TestUserService_CreateUser_DuplicateEmail_ShouldReturnError(t *testing.T)
```

### 技术栈

- **测试框架**: Go 内置 `testing`
- **断言库**: [Testify](https://github.com/stretchr/testify)
- **Mock 框架**: [GOOM Mocker](https://github.com/tencent/goom)
- **数据库 Mock**: [go-sqlmock](https://github.com/DATA-DOG/go-sqlmock)
- **Redis Mock**: [miniredis](https://github.com/alicebob/miniredis)

## 使用场景

### 我应该如何开始?

```
场景:
├── 第一次写 Go 单元测试 → 从 SKILL.md 开始,查看基础示例
├── 需要生成测试 → 了解四种测试生成模式（快速/完整/扫描/覆盖率）
├── 需要提升覆盖率 → 查看覆盖率达标检查文档，了解自动补测
├── 需要 Mock 数据库 → 查看第三方库 Mock 文档
├── 需要 Mock 接口/函数 → 查看 Mocker 使用指南
├── 测试函数过长 → 查看最佳实践的拆分策略
├── AI 生成测试 → 查看 AI 生成指导
└── 代码风格问题 → 查看代码风格规范
```

## 常见问题

### Q: 测试函数长度限制是多少?

A: 测试函数体长度限制是 **160 行**(普通函数的 2 倍)。超过时应拆分为多个测试函数或提取辅助函数。

### Q: 测试文件长度限制是多少?

A: 测试文件长度限制是 **1600 行**(普通文件的 2 倍)。超过时应考虑拆分文件。

### Q: 如何 Mock 接口?

A:
```go
// 1. 初始化接口为 nil
dao := (DAO)(nil)

// 2. 设置 Mock (第一个参数必须是 *mocker.IContext)
mock.Interface(&dao).Method("Get").Apply(
    func(_ *mocker.IContext, id int) (*Data, error) {
        return &Data{ID: id}, nil
    },
)

// 3. 注入到被测对象
service := &Service{dao: dao}
```

### Q: 可以 Mock GORM 吗?

A: **不推荐**。应使用 [go-sqlmock](https://github.com/DATA-DOG/go-sqlmock) 来 Mock 数据库操作,这是官方推荐的方式。参见[第三方库 Mock](./reference/third-party-mock.md)。

### Q: 如何运行测试?

A:

**标准覆盖率报告命令（强烈推荐）：**
```bash
# 生成完整覆盖率报告
go test -v -covermode=count -coverprofile=cover.out.tmp -coverpkg=./... '-gcflags=all=-N -l' ./...

# 查看总体覆盖率
go tool cover -func=cover.out.tmp | grep total

# 生成 HTML 报告
go tool cover -html=cover.out.tmp -o coverage.html
```

**兼容性命令：**
```bash
# Go < 1.23
go test -gcflags=all=-l -v ./...

# Go >= 1.23
go test -gcflags="all=-N -l" -ldflags=-checklinkname=0 -v ./...
```

### Q: M1 Mac 遇到 permission denied 怎么办?

A: 使用权限修复工具或切换到 AMD64 架构,详见 [SKILL.md](./SKILL.md)。

### Q: 如何提升测试覆盖率?

A:

**⚠️ 重要：必须使用标准覆盖率命令进行验证**

```bash
# 1. 生成标准覆盖率报告（必须使用此命令）
go test -v -covermode=count -coverprofile=cover.out.tmp -coverpkg=./... '-gcflags=all=-N -l' ./...

# 2. 查看总体覆盖率
go tool cover -func=cover.out.tmp | grep total

# 3. 查看详细覆盖率（按函数）
go tool cover -func=cover.out.tmp

# 4. 生成 HTML 报告分析未覆盖分支
go tool cover -html=cover.out.tmp -o coverage.html
```

**自动补测机制：**
- AI 会自动分析未覆盖分支，生成补测用例
- 最多进行 3 轮自动补测
- 每轮补测后必须运行标准覆盖率命令验证
- 以标准命令输出的整体覆盖率为准判断达标

详见：[覆盖率达标检查](./reference/coverage-check.md)

### Q: 测试覆盖率目标是多少?

A: 根据代码层级自动判断:
- Entity/Domain: ≥ 90%
- Logic/Service: ≥ 80%
- Adapter/Protocol: ≥ 70%
- 其他: ≥ 70%

## 相关资源

### 官方文档

- [Go Testing 包](https://pkg.go.dev/testing)
- [GOOM Mocker 公开仓库](https://github.com/tencent/goom)
- [Testify](https://github.com/stretchr/testify)

### 推荐阅读

- [Go Project Layout](https://github.com/golang-standards/project-layout)
- [Effective Go](https://go.dev/doc/effective_go)
- [Google Go Code Review Comments](https://github.com/golang/go/wiki/CodeReviewComments)

---

**开始你的 Go 单元测试之旅:从 [SKILL.md](./SKILL.md) 开始!** 🚀
