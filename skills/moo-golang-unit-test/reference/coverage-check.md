# 覆盖率达标检查与自动补测

本文档定义覆盖率检查和自动补测的详细流程。

## ⚠️ 重要：标准覆盖率验证命令

**所有覆盖率判断必须基于以下标准命令的输出结果：**

```bash
go test -v -covermode=count -coverprofile=cover.out.tmp -coverpkg=./... '-gcflags=all=-N -l' ./...
```

**强制要求：**
- ✅ 必须使用此命令生成覆盖率报告
- ✅ 必须确保所有测试通过，命令执行无错误
- ✅ 必须以命令输出的最终整体覆盖率为准
- ❌ 禁止使用其他命令或参数变体
- ❌ 禁止仅检查部分包或单个文件

## 覆盖率目标

| 层级 | 目标覆盖率 | 判断规则 |
|-----|-----------|---------|
| Entity/Domain | ≥ **90%** | 路径包含 `entity` |
| Logic/Service | ≥ **80%** | 路径包含 `logic` |
| Adapter/Protocol | ≥ **70%** | 路径包含 `repo` 或 `protocol` |
| 其他 | ≥ **70%** | 默认 |

## 检查流程

```
┌─────────────────────────────────────────────────────────────┐
│                    覆盖率达标检查流程                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  生成测试 → 运行测试 → 获取覆盖率                             │
│                          ↓                                  │
│                    覆盖率 ≥ 目标？                            │
│                    /          \                             │
│                  是            否                            │
│                  ↓              ↓                            │
│              ✅ 完成      分析未覆盖分支                       │
│                              ↓                              │
│                        补测轮次 < 3？                         │
│                        /          \                         │
│                      是            否                        │
│                      ↓              ↓                        │
│                 生成补测用例    ⚠️ 输出报告                    │
│                      ↓          (人工介入)                   │
│                 运行测试                                     │
│                      ↓                                      │
│                 返回检查                                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## 执行步骤

### 1. 运行测试并获取覆盖率（标准命令）

**⚠️ 强制要求：必须使用以下标准命令生成覆盖率报告**

```bash
# 标准覆盖率报告命令
go test -v -covermode=count -coverprofile=cover.out.tmp -coverpkg=./... '-gcflags=all=-N -l' ./...

# 查看总体覆盖率
go tool cover -func=cover.out.tmp | grep total

# 生成 HTML 报告
go tool cover -html=cover.out.tmp -o coverage.html
```

**命令说明：**
- 必须使用 `-coverpkg=./...` 统计所有包的覆盖率
- 必须使用 `-covermode=count` 统计执行次数
- 必须使用 `'-gcflags=all=-N -l'` 禁用优化
- 必须确保所有测试通过，命令执行无错误
- **以此命令输出的最终整体覆盖率为准进行达标判断**

**禁止使用的替代方案：**
- ❌ 不要只测试单个包：`go test ./specific/package`
- ❌ 不要省略 `-coverpkg`：会导致覆盖率统计不完整
- ❌ 不要使用简化参数：可能导致统计不准确

### 2. 判断目标覆盖率

根据包路径自动判断目标：

```python
def get_target_coverage(pkg_path):
    if "entity" in pkg_path:
        return 90
    elif "logic" in pkg_path:
        return 80
    elif "repo" in pkg_path or "protocol" in pkg_path:
        return 70
    else:
        return 70
```

### 3. 分析未覆盖分支

**前提：使用标准覆盖率报告命令生成 cover.out.tmp 文件**

当覆盖率未达标时：

```bash
# 获取未覆盖的函数列表
go tool cover -func=cover.out.tmp | grep -v "100.0%"

# 生成 HTML 报告用于详细分析
go tool cover -html=cover.out.tmp -o coverage.html
```

分析内容：
- **未覆盖的函数** - 完全没有测试的函数
- **部分覆盖的分支** - if/else、switch、error 处理分支
- **边界条件** - 空值、零值、极端值处理

### 4. 自动补测策略

**每轮补测后必须执行标准覆盖率命令验证**

根据未覆盖类型生成补测用例：

| 未覆盖类型 | 补测策略 | 示例用例名 |
|-----------|---------|-----------|
| 错误处理分支 | Mock 返回 error | `error_when_db_fails` |
| 空值/nil 检查 | 传入 nil 参数 | `nil_input_returns_error` |
| 边界条件 | 边界值（0, -1, MaxInt） | `edge_case_with_zero_value` |
| switch/case | 未覆盖 case 的输入 | `case_unknown_status` |
| 提前 return | 触发提前返回的条件 | `early_return_on_empty_list` |
| context cancel | Mock context 取消 | `context_cancelled` |

**补测验证流程：**
1. 生成补测用例代码
2. 执行标准覆盖率命令：`go test -v -covermode=count -coverprofile=cover.out.tmp -coverpkg=./... '-gcflags=all=-N -l' ./...`
3. 确认所有测试通过（无错误）
4. 检查整体覆盖率是否达标
5. 未达标且未超过轮次限制，则进入下一轮补测

### 5. 补测限制

- **最大补测轮次**: 3 次
- **单轮最大新增用例**: 10 个
- **超过限制后**: 输出详细报告，建议人工介入

## 输出格式

### 达标输出

```markdown
## ✅ 覆盖率达标

- **目标**: 80%
- **实际**: 85.2%
- **状态**: ✅ 达标

### 生成统计
- 新增测试函数: 8
- 新增测试用例: 32
- 补测轮次: 1
```

### 未达标输出

```markdown
## ⚠️ 覆盖率未达标

- **目标**: 80%
- **实际**: 75.3%
- **差距**: 4.7%
- **补测轮次**: 3/3 (已达上限)

### 未覆盖分支（需人工处理）

| 文件 | 函数 | 行号 | 原因 |
|-----|------|------|------|
| task.go | init | 10-15 | init 函数难以测试 |
| task.go | handlePanic | 80-85 | panic/recover 场景 |

### 建议
1. `init` 函数：考虑重构为可测试的初始化方法
2. `handlePanic`：使用 mockey 进行 monkey patch
```

## 补测代码模板

### 错误分支补测

```go
{
    name: "error_when_dependency_fails",
    req:  &pb.Request{ID: 1},
    mockSetup: func(m *mock.MockRepo) {
        m.EXPECT().
            Get(gomock.Any(), int64(1)).
            Return(nil, errors.New("database error"))
    },
    wantErr: true,
},
```

### 边界条件补测

```go
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

### Context 取消补测

```go
{
    name: "context_cancelled",
    setupCtx: func() context.Context {
        ctx, cancel := context.WithCancel(context.Background())
        cancel() // 立即取消
        return ctx
    },
    wantErr:     true,
    errContains: "context canceled",
},
```
