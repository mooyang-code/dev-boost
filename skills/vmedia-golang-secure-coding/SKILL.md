---
name: vmedia-golang-secure-coding
description: Go 安全编码规范。涵盖 SQL 注入防御（字段名校验、禁止 fmt.Sprintf 拼接 SQL、JSON_QUOTE 替代手动引号、GORM 标准用法）、SSRF 防御（禁用 http.DefaultClient / 裸 http.Client 发起外部请求、强制复用项目 pkg/safehttp 而非每处裸写 scurl、AllowedHosts 来自配置不得硬编码、下载+校验双链路同口径、禁止遗留不安全的包级 httpClient）。当编写或 Review 涉及 DB 操作、HTTP 外部请求的 Go 代码时触发。
---

# Go 安全编码规范

基于实际漏洞修复经验沉淀，适用于所有使用 GORM 和 HTTP 客户端的 Go 项目。

## 触发场景

- 编写 DAO 层 / 存储层代码
- 编写发起 HTTP 外部请求的代码
- Code Review 含 DB 操作或 HTTP 调用的 PR
- 修复安全扫描告警

---

## 规则 1：SQL 注入防御

### 1.1 字段名必须校验（高危）

**动态字段名（来自配置、用户输入、filter）直接拼接进 SQL 语句会造成 SQL 注入。**

```go
// ❌ 危险：c.Field 来自用户输入，直接拼进 SQL
return fmt.Sprintf("%s %s ?", c.Field, sqlOp), []any{val}, nil

// ✅ 正确：先用正则白名单校验字段名，再拼接
var validFieldName = regexp.MustCompile(`^[a-zA-Z_][a-zA-Z0-9_]*$`)

func validateField(field string) error {
    if !validFieldName.MatchString(field) {
        return fmt.Errorf("invalid field name: %q", field)
    }
    return nil
}

func translateCondition(c filter.Condition) (string, []any, error) {
    if err := validateField(c.Field); err != nil {
        return "", nil, err
    }
    // 此后 c.Field 可安全使用
    return fmt.Sprintf("%s %s ?", c.Field, sqlOp), []any{val}, nil
}
```

**规则：** 所有非固定字段名（来自外部输入或配置）在拼入 SQL 前，必须通过 `^[a-zA-Z_][a-zA-Z0-9_]*$` 白名单正则校验。

### 1.2 禁止 fmt.Sprintf 构造 SQL 参数值

**即使字段名是固定的，也禁止用 fmt.Sprintf 构造参数值拼入 SQL。**

```go
// ❌ 危险：fmt.Sprintf 构造 JSON 字符串再传入 Where
Where("... AND JSON_CONTAINS(c_operations, ?) ...", fmt.Sprintf(`"%s"`, operation))

// ✅ 正确：使用 MySQL 内置函数 JSON_QUOTE(?) 在 DB 侧完成转义
//   operation 作为裸值直接传给占位符，驱动负责转义
Where("... AND JSON_CONTAINS(c_operations, JSON_QUOTE(?)) ...", operation)
```

**规则：** 所有值必须通过 GORM 占位符 `?` 传递，禁止在 Go 层拼接。如需构造 JSON 值，使用 `JSON_QUOTE(?)`，不要 `fmt.Sprintf`。

### 1.3 GORM 标准写法——使用链式调用，禁止字符串拼接

**GORM 推荐通过链式 `.Where()` 逐步构建查询，所有值走占位符。**

```go
// ✅ 正确：链式 Where，动态条件通过 if 追加，值全部参数化
func (d *UserDAO) Query(ctx context.Context, req *QueryRequest) (*QueryResult, error) {
    query := d.db.WithContext(ctx).Table(d.tableName)

    // 逐步追加过滤条件，每个值都走占位符
    if req.Filter != nil {
        whereClause, args, err := buildWhereFromFilter(req.Filter)
        if err != nil {
            return nil, fmt.Errorf("build where: %w", err)
        }
        if whereClause != "" {
            query = query.Where(whereClause, args...)
        }
    }

    // 游标分页：主键走占位符
    if req.Cursor != "" {
        query = query.Where(d.primaryKey+" > ?", req.Cursor)
    }

    pageSize := req.PageSize
    if pageSize <= 0 {
        pageSize = 100
    }

    if len(req.Fields) > 0 {
        query = query.Select(req.Fields)
    }

    rows, err := query.Order(d.primaryKey + " ASC").Limit(pageSize).Rows()
    if err != nil {
        return nil, fmt.Errorf("query rows: %w", err)
    }
    defer rows.Close()

    return scanRows(rows, d.primaryKey)
}

// ❌ 禁止：拼接字符串构造 WHERE 条件
query = query.Where("status = " + status)
query = query.Where(fmt.Sprintf("status = %d", status))

// ❌ 禁止：Raw() 查询业务表（拼接值）
d.db.Raw("SELECT * FROM t_video WHERE status = " + status)

// ❌ 禁止：Exec() 执行拼接 SQL
d.db.Exec(fmt.Sprintf("UPDATE t_video SET status=%d WHERE id=%s", status, id))
```

**`Raw()` / `Exec()` 使用限制：**
- 查询系统表时，优先用 GORM 内置 API 替代
  - `TableExists` → `db.Migrator().HasTable(tableName)`
  - 建表 → `db.AutoMigrate(&model.Foo{})`
- 确实需要 `Raw()` 时，**必须**全部参数化，绝不拼接值

---

## 规则 2：SSRF 防御

**禁止使用标准库 `http.DefaultClient` / 裸 `&http.Client{}` 直接对外部（尤其是用户可控）URL 发起请求。**

攻击者可传入私有地址（`169.254.169.254` 云元数据端点、`10.x`、`172.16/12`、`192.168/16`、`127.x` 等）让服务器代理访问内部资源。

### 2.1 铁律：用项目 `pkg/safehttp`，不要每处裸写安全策略

公开 GitHub 项目应在项目内统一封装安全客户端构造函数（例如 `pkg/safehttp.NewClient`），所有对外 HTTP 请求**必须**走它，不要每处复制 DNS/IP 校验、端口限制、超时等参数。

```go
// ✅ 正确：复用项目封装
import (
    appcfg "github.com/mooyang-code/your-project/config"
    "github.com/mooyang-code/your-project/pkg/safehttp"
)

func downloadCSV(ctx context.Context, fileURL string) ([]byte, error) {
    // timeout 传 0 -> 使用 safehttp 默认值 30s
    // AllowedHosts 必须来自配置 appcfg.Get().SafeHTTP.AllowedHosts
    client := safehttp.NewClient(0, appcfg.Get().SafeHTTP.AllowedHosts)

    req, err := http.NewRequestWithContext(ctx, http.MethodGet, fileURL, nil)
    if err != nil {
        return nil, err
    }
    resp, err := client.Do(req)
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()
    if resp.StatusCode != http.StatusOK {
        return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
    }
    return io.ReadAll(resp.Body)
}
```

```go
// ❌ 反模式 1：http.DefaultClient
resp, err := http.DefaultClient.Do(req)

// ❌ 反模式 2：包级不安全 httpClient，易被误用
var httpClient = &http.Client{Timeout: 10 * time.Second}  // 删除它
resp, err := httpClient.Do(req)

// ❌ 反模式 3：每处临时创建带不同校验规则的 client，配置散落
client := safehttp.NewClient(10*time.Second, []string{"example.com"})

// ❌ 反模式 4：用 checkurl 做 host 白名单校验
//   checkurl 只做字符串级 scheme/host 白名单，
//   不解析 DNS → 无法挡住 DNS Rebinding / 白名单域名解析到私有网络的情况。
//   必须用项目 safehttp.NewClient，它在 DNS 层做 IP 判定。
checkStatus, _ := secapi.CheckUrl(url, schemeWL, hostWL)
```

### 2.2 `safehttp.NewClient` 的双层语义（重要）

安全客户端应对每个连接做两层检查，理解语义才能正确使用 `AllowedHosts`：

| 层 | 作用 | 规则 |
|---|------|------|
| 域名层 | host 是否在 `WithHosts` 白名单 | 命中白名单 → 直接放行，跳过 IP 检查 |
| IP 层  | DNS 解析后的 IP 是否为公网 IP  | 公网 IP -> 放行；私有网段/本机地址/链路本地地址 -> 拒绝 |

`safehttp.NewClient(timeout, allowedHosts)` 内部传入的 hosts = `["*"] + allowedHosts`：

- `"*"`：允许公网访问，但仍走 IP 层检查；
- `allowedHosts`：**仅用于放通"域名固定、但 DNS 解析结果为私有 IP"的受信任服务**。公开项目通常应尽量为空；确有需要时必须来自配置和代码评审。

```go
// ✅ AllowedHosts 来自 yaml 配置，不硬编码
client := safehttp.NewClient(0, appcfg.Get().SafeHTTP.AllowedHosts)
```

```yaml
# config/app.yaml
safe_http:
  allowed_hosts:
    - assets.example.com
```

**规则：**
- `AllowedHosts` **必须**来自配置，禁止在 Go 代码里写死业务域名；
- `AllowedHosts` 只能放**后端代码自己生成 URL 所用的固定受信任域名**，绝不能放用户可控域名（否则有 DNS 重绑定攻击风险）；
- 传空 slice 表示只允许 DNS 解析为公网 IP 的请求（更严格）。

### 2.3 双链路同口径：下载 + 前置校验都要用 safe client

对同一个用户传入的 URL，任何对它发起的 HTTP 请求都要走 safe client，**不能只防下载不防校验**。

典型错误场景：`service.Create` 里先 `HEAD` 校验 URL 可达，再把任务丢给 worker 去 `GET` 下载。如果只把 `GET` 下载换成 safe client，`HEAD` 校验仍用 `http.DefaultClient`，攻击者仍可在校验阶段访问私有网络。

```go
// ✅ 两处都要换
func (s *Service) validateURL(ctx context.Context, fileURL string) error {
    req, _ := http.NewRequestWithContext(ctx, http.MethodHead, fileURL, nil)
    client := safehttp.NewClient(10*time.Second, appcfg.Get().SafeHTTP.AllowedHosts)
    resp, err := client.Do(req)
    // ...
}

func (p *Plugin) download(ctx context.Context, fileURL string) ([]byte, error) {
    client := safehttp.NewClient(0, appcfg.Get().SafeHTTP.AllowedHosts)
    // ...
}
```

**Review checklist：** 当一个用户可控 URL 在代码里被 `HEAD` / `GET` / `POST` 多次访问时，确认**每一处**都走 `safehttp.NewClient`，不要漏掉"前置校验"这类低频路径。

### 2.4 清理遗留的不安全包级变量

改造存量代码时，如果原代码有包级 `var httpClient = &http.Client{...}` 这类不安全变量，替换调用点后**必须一并删除该变量**，避免：
- 后续同事误用；
- 未来新加的调用点又绕过 safe client。

Go 包级变量未使用不会编译报错，但属于代码债，Review 时应主动指出。

### 2.5 适用场景

所有接受外部传入 URL 并发起 HTTP 请求的代码路径，包括但不限于：

- 下载用户上传的文件（CSV、ID 文件、Excel 等）；
- 下载前的可达性/权限/大小预校验（HEAD 请求）；
- UDF / 插件里用户配置中声明的 HTTP 回调；
- webhook / 消息通知推送；
- 任何以用户传入 URL 作为参数的 HTTP 请求。

固定目标地址的内部服务调用（如走 local-yaml 下发的消息网关、ES 集群）可暂不改，但应加 TODO 注释逐步统一。

### 2.6 何时允许不走 safehttp

只有以下场景可以例外，且必须在代码里写明理由：

- 目标 URL 完全由可信配置（local-yaml / DNS/IP）下发，没有任何用户输入参与；
- 单元测试 mock 场景。

---

## 常见误区

| 误区 | 正确做法 |
|------|---------|
| "GORM 已经参数化了，不用担心字段名" | 字段名不会被 GORM 参数化，动态字段名必须手动校验 |
| "`fmt.Sprintf` 构造的是 JSON 格式，不是 SQL 注入" | 值必须通过占位符传递，使用 `JSON_QUOTE(?)` 替代 |
| "URL 来自可信系统，不用 scurl" | 内部调用链被攻击时同样会 SSRF，统一用 `safehttp.NewClient` |
| "`Raw()` 已经参数化了，是安全的" | 参数化 Raw() 虽然安全，但查询系统表优先用 GORM 内置 API |
| "字段名是固定写死的，不需要校验" | 固定字段名无需校验；**只有动态字段名才需要** |
| "用 `secapi.CheckUrl` + scheme/host 白名单就够了" | `checkurl` 只做字符串级 host 白名单，不挡 DNS Rebinding；必须用 `safehttp.NewClient`（scurl），在 DNS 层做 IP 判定 |
| "每次写 HTTP 调用都自己拼 `scurl.NewSafeClient(...)`" | 统一走项目封装 `pkg/safehttp.NewClient(timeout, appcfg.Get().SafeHTTP.AllowedHosts)` |
| "把 COS 业务域名直接写进代码的 AllowedHosts" | `AllowedHosts` 必须来自 yaml 配置 `safe_http.allowed_hosts`，禁止硬编码业务域名 |
| "下载接口换成 safe client 就行了" | 同一 URL 的**所有**访问点（HEAD 校验、GET 下载、POST 回调）都要统一换，否则校验链路仍能访问私有网络 |
| "只要不调用就行，旧的包级 `httpClient` 变量留着没事" | Go 不会报"包级变量未使用"，但它是反模式——必须删除，避免误用 |
| "`AllowedHosts` 里多加几个域名更安全" | 语义反了：`AllowedHosts` 里的域名是**跳过内网 IP 检查**（放通私有 IP），仅用于后端自生成的固定受信任域名；用户可控域名绝对不能加 |
