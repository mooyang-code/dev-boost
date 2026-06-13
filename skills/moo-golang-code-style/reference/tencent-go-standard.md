# Go 编码规范（公开项目精编版）

> **本文档**：面向 GitHub 项目的精编整理版，保留通用 Go 规则及等级标记，优化结构与排版
> **工具落地**：建议使用 `golangci-lint`、`go vet`、`staticcheck`
> **参考基础**：[Google Golang 代码规范](https://github.com/golang/go/wiki/CodeReviewComments)

---

## 规则等级说明

| 等级 | 标记 | 含义 |
|------|------|------|
| **必须** | Mandatory | 必须采用，代码扫描工具视为错误 |
| **推荐** | Preferable | 理应采用，特殊情况可不采用，扫描工具不视为错误 |
| **可选** | Optional | 可参考，自行决定 |

---

## 快速参考总表

| 分类 | 规则 | 等级 |
|------|------|------|
| **代码风格** | 使用 `gofmt` 格式化 | 必须 |
| | 一行不超过 120 列 | 推荐 |
| | 遵循 `gofmt` 括号和空格规则 | 必须 |
| | 使用 `goimports` 管理 import | 必须 |
| | 不使用相对路径引入包 | 必须 |
| | 单元测试文件 `example_test.go`，函数以 `Test` 开头 | 必须 |
| | 单测文件行数限制 1600 行，函数 160 行 | 必须 |
| **错误处理** | `error` 必须处理或显式忽略 | 必须 |
| | `error` 必须是最后一个返回值 | 必须 |
| | 采用独立错误流处理 | 必须 |
| | 错误描述不需要标点结尾 | 必须 |
| | 不使用 `panic` 做一般错误处理 | 必须 |
| | `recover` 必须在 `defer` 中使用 | 必须 |
| | 使用 `fmt.Errorf("xxx: %w", err)` 包装错误（go1.13+） | 推荐 |
| **注释** | 包注释（main 包除外） | 必须 |
| | 导出的结构体/接口/函数/变量/常量/类型必须有注释 | 必须 |
| | 注释格式：`// 名称 描述` | 必须 |
| **命名规范** | 包名与目录一致，小写，不用下划线 | 推荐 |
| | 文件名小写+下划线 | 必须 |
| | 结构体/变量/常量/函数用驼峰命名 | 必须 |
| | 单函数接口以 `er` 为后缀 | 推荐 |
| | 接收器不用 `me`/`this`/`self` | 必须 |
| **控制结构** | `if` 中变量在左、常量在右 | 推荐 |
| | `range` 只需 key 时丢弃 value | 必须 |
| | `switch` 必须有 `default` | 必须 |
| | 禁止使用 `goto` | 必须 |
| **函数** | 参数不超过 5 个 | 推荐 |
| | `defer` 释放资源，禁止在循环中使用 | 必须 |
| | 文件不超过 800 行 | 必须 |
| | 函数不超过 80 行 | 推荐 |
| | 嵌套不超过 4 层 | 必须 |
| | 魔法数字用常量替代 | 必须 |
| **依赖管理** | go1.11+ 使用 go modules | 必须 |
| | `go.sum` 必须提交 | 推荐 |
| **应用服务** | 有 `README.md` | 推荐 |
| | 必须有接口测试 | 必须 |

---

## 一、代码风格

### 1.1 【必须】格式化

代码都必须用 `gofmt` 格式化。

### 1.2 【推荐】换行

- 建议一行代码不超过 **120 列**，超过时使用合理的换行方法。
- **例外场景**（可超过列数限制）：
  - 函数签名（但需考虑是否参数过多）
  - 长字符串文字（含 `\n` 时考虑用原始字符串字面量）
  - import 语句、工具生成代码、struct tag
  - 注释中的文档链接

```go
// ✅ 长函数签名可以超过列数限制
func (i *webImpl) GenerateAgentInstallLink(ctx context.Context, req *pb.GenerateAgentInstallLinkRequest) (*pb.GenerateAgentInstallLinkResponse, error) {
    ...
}

// ❌ 不要在函数签名中为满足列数换行
func (i *webImpl) GenerateAgentInstallLink(ctx context.Context,
    req *pb.GenerateAgentInstallLinkRequest) (*pb.GenerateAgentInstallLinkResponse, error) {
    ... // gofmt 会使签名与函数内语句对齐，降低可读性
}
```

### 1.3 【必须】括号和空格

- 遵循 `gofmt` 逻辑。
- 运算符和操作数之间留空格。
- 作为参数或数组下标时，紧凑展示，不需要空格。

### 1.4 【必须】import 规范

- 使用 `goimports` 自动格式化引入的包名。
- 分组原则：**标准库/内部包**（第一组） → **第三方包**（第二组），空行隔开。
- 标准包永远位于最上面的第一组。
- 不使用相对路径引入包。
- 包名与 git 路径名不一致或冲突时，使用别名。
- 【可选】第三方包名不符合规范可用别名修正。
- 【可选】匿名包引用建议单独分组，并添加注释说明。

```go
import (
    // 标准库 & 内部包
    "encoding/json"
    "myproject/models"
    "myproject/controller"
    "strings"

    // 第三方包
    "git.obc.im/obc/utils"
    "git.obc.im/dep/beego"
    opentracing "github.com/opentracing/opentracing-go"

    // 匿名引入（需注释说明）
    // import filesystem storage driver
    _ "github.com/mooyang-code/your-repo/pkg/storage/filesystem"
)
```

### 1.5 【必须】单元测试

- 测试文件命名：`example_test.go`
- 测试函数以 `Test` 开头，如 `TestExample`
- 存在 `func Foo` 时，单测可为 `func Test_Foo`；存在 `func (b *Bar) Foo` 时，可为 `func TestBar_Foo`
- 单测文件行数限制 **1600 行**，函数限制 **160 行**（均为普通文件的 2 倍）
- 每个重要的可导出函数都要编写测试用例，与正规代码一起提交

---

## 二、错误处理

### 2.1 【必须】error 处理

- `error` 作为返回值时，**必须处理**或赋值给明确忽略（`defer xx.Close()` 可不显式处理）。
- `error` 必须是**最后一个**返回参数。
- 错误描述**不需要标点结尾**。
- 采用**独立错误流**处理，不要将正常逻辑放在 `else` 中。
- 错误判断**独立处理**，不与其他变量组合逻辑判断。

```go
// ✅ 正确：独立错误流
if err != nil {
    return err
}
// normal code

// ❌ 错误：正常代码放在 else 中
if err != nil {
    // error handling
} else {
    // normal code
}
```

```go
// ❌ 错误：error 与其他条件混合判断
x, y, err := f()
if err != nil || y == nil {
    return err   // 当 y 与 err 都为 nil 时，调用者会产生错误逻辑
}

// ✅ 正确：分别判断
x, y, err := f()
if err != nil {
    return err
}
if y == nil {
    return errors.New("some error")
}
```

- 【推荐】不需要格式化的错误用 `errors.New("xxxx")`
- 【推荐】go1.13+，error 包装用 `fmt.Errorf("module xxx: %w", err)`

### 2.2 【必须】panic 处理

- **不要**用 `panic` 做一般错误处理，使用 `error` + 多返回值。
- **可以**用 `panic` 对不变量（invariant）进行断言。
- `func init()` 中初始化失败影响程序运行时，可以 `panic`。
- 全局变量初始化（如 `regexp.MustCompile`、`template.Must`）失败时，可以 `panic`。
- 导出方法一般不允许 `panic`。必须 `panic` 的方法应命名为 `MustXXX`，并在文档中说明。
- 不建议使用 `log.Fatal` 进行断言。

```go
// ✅ 可以对不变量断言
func readText(n Node) string {
    switch n := n.(type) {
    case *TextNode:
        return n.Text
    case *CommentNode:
        return n.Comment
    default:
        panic(fmt.Errorf("unexpected node type: %T", n))
    }
}
```

### 2.3 【必须】recover 处理

- **必须**在 `defer` 中使用。
- 业务逻辑中一般不需要使用 `recover`。
- 用于捕获**明确类型**的 `panic`，禁止滥用 `recover` 捕获全部异常。

```go
type FatalError string

func (e FatalError) Error() string { return string(e) }

func main() {
    defer func() {
        e := recover() // 返回 interface{}，不要假设是 error
        if e != nil {
            err, ok := e.(FatalError)
            if !ok {
                panic(e) // 继续抛出不认识的异常
            }
            // 响应抛出的错误
            _ = err
        }
    }()
    panic(FatalError("错误信息"))
}
```

---

## 三、注释

**总则**：
- 编码阶段同步写好注释，可通过 `godoc` 导出生成文档。
- 每个导出的（大写的）名字都应有文档注释。
- 所有注释掉的代码在 code review 前应删除，除非添加注释解释原因并标明后续处理建议。

### 3.1 【必须】包注释

每个包都应有包注释（main 包除外），格式：`// Package 包名 描述`。

```go
// Package math provides basic constants and mathematical functions.
package math
```

### 3.2 【必须】结构体注释

导出的结构体或接口必须有注释，格式：`// 结构体名 描述`。

```go
// User 用户结构定义了用户基础信息
type User struct {
    Name  string
    Email string
    // Demographic 族群
    Demographic string
}
```

### 3.3 【必须】方法注释

导出的函数或方法必须有注释，格式：`// 函数名 描述`。

```go
// NewAttrModel 是属性数据层操作类的工厂方法
func NewAttrModel(ctx *common.Context) *AttrModel {
    // ...
}
```

**例外方法**（可无注释）：`Write`、`Read`（IO）、`ServeHTTP`、`String`、`Unwrap`、`Error`、`Len`、`Less`、`Swap`。

### 3.4 【必须】变量和常量注释

导出的常量和变量必须有注释，格式：`// 变量名 描述`。

```go
// FlagConfigFile 配置文件的命令行参数名
const FlagConfigFile = "--config"

// 命令行参数
const (
    FlagConfigFile1 = "--config" // 配置文件的命令行参数名1
    FlagConfigFile2 = "--config" // 配置文件的命令行参数名2
)
```

### 3.5 【必须】类型注释

导出的类型定义和类型别名必须有注释。

```go
// StorageClass 存储类型
type StorageClass string

// FakeTime 标准库时间的类型别名
type FakeTime = time.Time
```

---

## 四、命名规范

### 4.1 【推荐】包命名

- 包名与目录一致，小写单词，不用下划线或混合大小写。
- 采用有意义、简短的包名，不与标准库冲突。
- 可谨慎使用广泛熟知的缩写（`strconv`、`syscall`、`fmt`）。
- **禁止**使用无意义包名：`util`、`common`、`misc`、`global`。包名应符合单一职责原则。
  - 注意：`xx/util/encryption` 这样的包名是允许的。
- 项目名可用中划线连接多个单词。

### 4.2 【必须】文件命名

- 小写，使用下划线分割单词，如 `user_model.go`。

### 4.3 【必须】结构体命名

- 驼峰命名，首字母根据访问控制大小写。
- 应是**名词或名词短语**：`Customer`、`WikiPage`、`AddressParser`，不应是动词。
- 避免 `Data`、`Info` 等意义太宽泛的名字。
- 声明和初始化采用**多行格式**。

### 4.4 【推荐】接口命名

- 单函数接口以 **`er`** 为后缀：`Reader`、`Writer`。
- 两函数接口综合两个函数名。
- 三个以上函数的接口，类似结构体命名。

```go
// Reader 字节数组读取接口
type Reader interface {
    Read(p []byte) (n int, err error)
}
```

### 4.5 【必须】变量命名

- 驼峰式，首字母根据访问控制大小写。
- 特有名词规则：
  - 私有且首个单词为特有名词 → 小写：`apiClient`
  - 其他情况用原有写法：`APIClient`、`repoID`、`UserID`
  - ❌ `UrlArray` → ✅ `urlArray` 或 `URLArray`
- 变量名倾向于**短命名**，尤其是局部变量（`c` > `lineCount`，`i` > `sliceIndex`）。
- 原则：使用和声明距离越远，名称越需要描述性。

### 4.6 【必须】常量命名

- 驼峰式。枚举常量需先创建相应类型。

```go
// Scheme 传输协议
type Scheme string

const (
    // HTTP 表示HTTP明文传输协议
    HTTP Scheme = "http"
    // HTTPS 表示HTTPS加密传输协议
    HTTPS Scheme = "https"
)
```

### 4.7 【必须】函数命名

- 驼峰式，首字母根据访问控制大小写。
- 代码生成工具自动生成的代码可排除此规则。

---

## 五、控制结构

### 5.1 【推荐】if

- 善用初始化语句建立局部变量：

```go
if err := file.Chmod(0664); err != nil {
    return err
}
```

- 两值判断时，**变量在左，常量在右**：

```go
// ✅ 正确
if err != nil { ... }
if errorCode == 0 { ... }

// ❌ 错误
if nil != err { ... }
if 0 == errorCode { ... }
```

- bool 类型直接判断真假：

```go
// ✅ 正确
if allowUserLogin { ... }
if !allowUserLogin { ... }

// ❌ 错误
if allowUserLogin == true { ... }
if allowUserLogin == false { ... }
```

### 5.2 【推荐】for

- 采用短声明建立局部变量：

```go
sum := 0
for i := 0; i < 10; i++ {
    sum += 1
}
```

### 5.3 【必须】range

- 只需 key 时，丢弃 value：`for key := range m { ... }`
- 只需 value 时，用下划线忽略 key：`for _, value := range array { ... }`

### 5.4 【必须】switch

- 必须有 `default` 分支。

```go
switch os := runtime.GOOS; os {
    case "darwin":
        fmt.Println("OS X.")
    case "linux":
        fmt.Println("Linux.")
    default:
        fmt.Printf("%s.\n", os)
}
```

### 5.5 【推荐】return

- 尽早 return，一旦有错误发生马上返回。

### 5.6 【必须】goto

- 业务代码**禁止使用** `goto`，框架或底层源码推荐尽量不用。

---

## 六、函数

### 6.1 【推荐】函数参数

- 返回相同类型的 2-3 个参数，或含义不清时，使用**命名返回**；其他情况不建议。
- 传入变量和返回变量以小写字母开头。
- 参数数量**不超过 5 个**。
- 尽量用值传递，非指针传递。
- `map`、`slice`、`chan`、`interface` 不要传递指针。

```go
func (n *Node) Parent1() *Node
func (n *Node) Parent2() (*Node, error)
func (f *Foo) Location() (lat, long float64, err error)
```

### 6.2 【必须】defer

- 存在资源管理时，紧跟 `defer` 释放资源。
- **先判断错误，再 defer 释放**。
- **禁止**在循环中使用 `defer`（应提取到闭包函数中）。

```go
// ✅ 正确：先判错再 defer
resp, err := http.Get(url)
if err != nil {
    return err
}
defer resp.Body.Close()

// ❌ 错误：循环中使用 defer
for _, v := range values {
    fields, err := db.Query(v)
    defer fields.Close() // 资源泄漏！
}

// ✅ 正确：循环中用闭包包裹
for _, v := range values {
    func() {
        fields, err := db.Query(v)
        if err != nil { ... }
        defer fields.Close()
        // 使用 fields
    }()
}
```

### 6.3 【推荐】方法的接收器

- 【推荐】以类名首字母小写作为接收器命名。
- 【推荐】函数超过 20 行时不要用单字符命名。
- 【必须】不能用 `me`、`this`、`self`。

### 6.4 代码行数限制

- 【必须】文件不超过 **800 行**。
- 【推荐】函数不超过 **80 行**。

### 6.5 【必须】嵌套

嵌套深度不超过 **4 层**。可通过提取子函数降低嵌套。

```go
// ❌ 嵌套过深
func (s *BookingService) AddArea(areas ...string) error {
    s.Lock()
    defer s.Unlock()
    for _, area := range areas {
        for _, has := range s.areas {
            if area == has {
                return srverr.ErrAreaConflict
            }
        }
        s.areas = append(s.areas, area)
    }
    return nil
}

// ✅ 提取子函数降低嵌套
func (s *BookingService) AddArea(areas ...string) error {
    s.Lock()
    defer s.Unlock()
    for _, area := range areas {
        if s.HasArea(area) {
            return srverr.ErrAreaConflict
        }
        s.areas = append(s.areas, area)
    }
    return nil
}

func (s *BookingService) HasArea(area string) bool {
    for _, has := range s.areas {
        if area == has {
            return true
        }
    }
    return false
}
```

### 6.6 【推荐】变量声明

变量声明尽量放在变量第一次使用前面，遵循**就近原则**。

### 6.7 【必须】魔法数字

魔数应使用常量或变量替代。魔数特征：缺乏解释的独特数值，影响可读性；多次出现时修改困难。

```go
// ❌ 魔法数字
total := 1.05 * price

// ✅ 使用命名常量
const TaxRate = 0.05
total := (1.0 + TaxRate) * price
```

**不属于魔数的常见情况**（上下文中含义一目了然且基本不会变化）：

```go
d = b*b - 4*a*c       // 一元二次方程判别式中的 4
if x%2 == 0 {}        // 判断奇偶的 2
for i := 0; i < max; i += 1 {} // 0 和 1
os.Exit(1)             // 表示程序错误的 1
```

> ⚠️ 注意：如果命名量与使用处距离很远，会破坏代码局部性，反而降低可读性。应权衡使用。

---

## 七、依赖管理

### 7.1 【必须】使用 go modules

go1.11 以上必须使用 go modules：

```bash
go mod init github.com/mooyang-code/myrepo
```

### 7.2 【推荐】代码提交

- GitHub 项目 module name 使用 `github.com/<org>/<repo>`，例如 `github.com/mooyang-code/myrepo`。
- 使用 go modules 的项目**不提交 vendor 目录**。
- `go.sum` 文件**必须提交**，不要添加到 `.gitignore`。

---

## 八、应用服务

### 8.1 【推荐】README.md

应用服务接口建议有 `README.md`，包括：
- 服务基本描述
- 使用方法
- 部署限制与要求
- 基础环境依赖（最低 go 版本、最低外部包版本等）

### 8.2 【必须】接口测试

应用服务必须有接口测试。

---

## 附录：常用工具

| 工具 | 用途 |
|------|------|
| `gofmt` | 自动格式化代码，保证与官方推荐格式一致 |
| `goimports` | 在 `gofmt` 基础上自动删除和引入包 |
| `go vet` | 静态分析源码问题（多余代码、提前 return、struct tag 等） |
| `golint` | 检测代码中不规范的地方 |

---

> 本文档面向公开 GitHub 项目整理，优先采用 Go 社区通用实践。
