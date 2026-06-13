# tRPC 常用模式详解

tRPC-Go 生态中的常用编码模式，包含完整示例。

---

## 1. 重试模式 — retry-go

### 基础用法

```go
import "github.com/avast/retry-go"

// 简单重试
err := retry.Do(
    func() error {
        return callExternalService(ctx)
    },
    retry.Attempts(3),
    retry.Delay(100*time.Millisecond),
)
```

### 带指数退避

```go
err := retry.Do(
    func() error {
        return callExternalService(ctx)
    },
    retry.Attempts(5),
    retry.Delay(200*time.Millisecond),
    retry.DelayType(retry.BackOffDelay),  // 200ms, 400ms, 800ms, 1.6s
    retry.MaxDelay(5*time.Second),
)
```

### 条件重试

```go
err := retry.Do(
    func() error {
        return callExternalService(ctx)
    },
    retry.Attempts(3),
    retry.RetryIf(func(err error) bool {
        // 只对可重试的错误进行重试
        return isRetryableError(err)
    }),
    retry.Context(ctx),  // 支持 context 取消
)
```

### 完整生产示例

```go
func (c *EventProcessor) processWithRetry(ctx context.Context, event *Event, cfg *RetryConfig) error {
    return retry.Do(
        func() error {
            return c.processEvent(ctx, event)
        },
        retry.Attempts(uint(cfg.RetryCount+1)),
        retry.Delay(time.Duration(cfg.RetryIntervalMs)*time.Millisecond),
        retry.LastErrorOnly(true),
        retry.Context(ctx),
        retry.OnRetry(func(n uint, err error) {
            log.InfoContextf(ctx, "处理事件重试(%d/%d)，事件ID: %s, 错误: %v",
                n, cfg.RetryCount, event.Id, err)
        }),
    )
}
```

---

## 2. 并发模式 — GoAndWait

### 基础并发

```go
import "trpc.group/trpc-go/trpc-go"

err := trpc.GoAndWait(
    func() error { /* 任务1 */ return nil },
    func() error { /* 任务2 */ return nil },
    func() error { /* 任务3 */ return nil },
)
```

### 聚合多个数据源

```go
func (s *Service) GetProfile(ctx context.Context, uid string) (*Profile, error) {
    var (
        user   *User
        avatar *Avatar
        prefs  *Preferences
    )

    err := trpc.GoAndWait(
        func() error {
            var err error
            user, err = s.userSvc.Get(ctx, uid)
            return err
        },
        func() error {
            var err error
            avatar, err = s.avatarSvc.Get(ctx, uid)
            return err
        },
        func() error {
            var err error
            prefs, err = s.prefsSvc.Get(ctx, uid)
            return err
        },
    )
    if err != nil {
        return nil, err
    }

    return &Profile{User: user, Avatar: avatar, Preferences: prefs}, nil
}
```

### 批量处理模式

```go
func (s *Service) BatchProcess(ctx context.Context, items []*Item) error {
    handlers := make([]func() error, 0, len(items))
    for _, item := range items {
        item := item  // 闭包捕获
        handlers = append(handlers, func() error {
            return s.processItem(ctx, item)
        })
    }
    return trpc.GoAndWait(handlers...)
}
```

---

## 3. GORM 使用模式

### 初始化 — tRPC 插件方式

```go
import "trpc.group/trpc-go/trpc-database/gorm"

// 通过 tRPC 配置初始化（推荐）
cli, err := gorm.NewClientProxy("trpc.mysql.server.service")

// trpc_go.yaml 配置示例
// plugins:
//   database:
//     gorm:
//       service:
//         - name: trpc.mysql.server.service
//           dsn: user:password@tcp(host:port)/d_mydb?charset=utf8mb4&parseTime=True
//           max_idle: 10
//           max_open: 100
//           max_lifetime: 180000
```

### CRUD 操作（必须带 ctx）

```go
// 创建
func (r *Repo) Create(ctx context.Context, user *User) error {
    return r.db.WithContext(ctx).Create(user).Error
}

// 查询
func (r *Repo) FindByID(ctx context.Context, id int) (*User, error) {
    var user User
    err := r.db.WithContext(ctx).First(&user, id).Error
    if err != nil {
        return nil, err
    }
    return &user, nil
}

// 条件查询
func (r *Repo) List(ctx context.Context, status string, limit int) ([]*User, error) {
    var users []*User
    err := r.db.WithContext(ctx).
        Where("c_status = ?", status).
        Order("c_created_time DESC").
        Limit(limit).
        Find(&users).Error
    return users, err
}

// 更新
func (r *Repo) Update(ctx context.Context, id int, updates map[string]interface{}) error {
    return r.db.WithContext(ctx).
        Model(&User{}).
        Where("c_id = ?", id).
        Updates(updates).Error
}

// 删除
func (r *Repo) Delete(ctx context.Context, id int) error {
    return r.db.WithContext(ctx).Delete(&User{}, id).Error
}
```

### 事务

```go
func (r *Repo) Transfer(ctx context.Context, fromID, toID int, amount float64) error {
    return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
        if err := tx.Model(&Account{}).
            Where("c_id = ?", fromID).
            Update("c_balance", gorm.Expr("c_balance - ?", amount)).Error; err != nil {
            return err
        }
        if err := tx.Model(&Account{}).
            Where("c_id = ?", toID).
            Update("c_balance", gorm.Expr("c_balance + ?", amount)).Error; err != nil {
            return err
        }
        return nil
    })
}
```

### 单测 — sqlmock

```go
// 与 trpc-database/gorm 官方 README 推荐方式一致
import (
    "github.com/DATA-DOG/go-sqlmock"
    "gorm.io/driver/mysql"
    "gorm.io/gorm"
    "github.com/stretchr/testify/assert"
)

func TestFindByID(t *testing.T) {
    // 1. 创建 mock DB
    db, mock, err := sqlmock.New()
    assert.NoError(t, err)
    defer db.Close()

    gormDB, err := gorm.Open(mysql.New(mysql.Config{
        Conn:                      db,
        SkipInitializeWithVersion: true,
    }), &gorm.Config{})
    assert.NoError(t, err)

    // 2. 设置期望
    rows := sqlmock.NewRows([]string{"c_id", "c_name"}).
        AddRow(1, "test-user")
    mock.ExpectQuery("SELECT").WillReturnRows(rows)

    // 3. 执行测试
    repo := NewUserRepository(gormDB)
    user, err := repo.FindByID(context.Background(), 1)

    // 4. 断言
    assert.NoError(t, err)
    assert.Equal(t, "test-user", user.Name)
    assert.NoError(t, mock.ExpectationsWereMet())
}
```

---

## 4. Redis 使用模式

### 初始化 — goredis 插件（推荐）

```go
import "trpc.group/trpc-go/trpc-database/goredis"

// trpc_go.yaml 配置
// plugins:
//   database:
//     goredis:
//       service:
//         - name: trpc.redis.server.service
//           address: host:port
//           password: xxx

rdb := goredis.NewClientProxy("trpc.redis.server.service")
```

### 常用操作

```go
// 必须带 ctx
func (c *Cache) Get(ctx context.Context, key string) (string, error) {
    return c.rdb.Get(ctx, key).Result()
}

func (c *Cache) Set(ctx context.Context, key string, value interface{}, ttl time.Duration) error {
    return c.rdb.Set(ctx, key, value, ttl).Err()
}
```

---

## 5. 本地缓存模式

### localcache

```go
import "trpc.group/trpc-go/trpc-database/localcache"

// 适用：单机缓存、低频变更的配置/字典数据
cache := localcache.New(
    localcache.WithTTL(5 * time.Minute),
    localcache.WithMaxSize(1000),
)

cache.Set("key", value)
val, ok := cache.Get("key")
```

---

## 6. 日志模式

### tRPC Log（必须带 ctx）

```go
import "trpc.group/trpc-go/trpc-go/log"

// ✅ 带 ctx 的日志（推荐，自动携带 TraceID）
log.InfoContextf(ctx, "处理事件成功，事件ID: %s", eventID)
log.ErrorContextf(ctx, "处理失败: %+v", err)
log.WarnContextf(ctx, "缓存未命中，key: %s", key)

// ❌ 不带 ctx 的日志（仅在初始化等无 ctx 场景使用）
log.Infof("服务启动完成")
```

---

## 7. 配置管理模式

### tRPC Config（支持热更新）

```go
import (
    "trpc.group/trpc-go/trpc-go/config"
    "gopkg.in/yaml.v2"
)

type BusinessConfig struct {
    RetryCount      int  `yaml:"retry_count"`
    RetryIntervalMs int  `yaml:"retry_interval_ms"`
    EnableFeatureX  bool `yaml:"enable_feature_x"`
}

func LoadBusinessConfig() (*BusinessConfig, error) {
    conf, err := config.Load("business.yaml",
        config.WithCodec("yaml"),
        config.WithProvider("file"),
    )
    if err != nil {
        return nil, fmt.Errorf("load config failed: %w", err)
    }

    c := &BusinessConfig{}
    if err = yaml.Unmarshal(conf.Bytes(), c); err != nil {
        return nil, fmt.Errorf("unmarshal config failed: %w", err)
    }

    log.InfoContextf(trpc.BackgroundContext(), "配置加载成功: %+v", c)
    return c, nil
}
```

---

## 8. trpc_go.yaml 配置模板

完整的 tRPC 服务配置模板，涵盖 server、client、plugins 三大块。

```yaml
global:
  namespace: ${namespace}              # Production / Development
  env_name: ${env_name}                # 非正式环境下多环境名称
  container_name: ${container_name}
  local_ip: ${local_ip}

server:
  app: ${app}
  server: ${server}
  bin_path: /usr/local/trpc/bin/
  conf_path: /usr/local/trpc/conf/
  data_path: /usr/local/trpc/data/
  filter:
    - file                          # 监控上报
    - recovery                         # panic 恢复
    - validation                       # 参数校验
  admin:
    ip: ${local_ip}
    port: ${ADMIN_PORT}
    read_timeout: 3000                 # ms
    write_timeout: 60000               # ms
  service:
    # ---- tRPC 协议服务 ----
    - name: trpc.${app}.${server}.YourService
      network: tcp
      protocol: trpc
      timeout: 30000                   # ms
      registry: none
      ip: ${ip}

    # ---- HTTP 协议服务 ----
    - name: trpc.${app}.${server}.YourServiceHttp
      network: tcp
      protocol: http
      timeout: 30000
      registry: none
      ip: ${ip}
      filter:
        - authorize                    # HTTP 鉴权过滤器

    # ---- 定时任务（timer 协议）----
    - name: trpc.${app}.${server}.CronJob
      nic: eth1
      port: ${port}
      network: "0 0/10 * * * *?scheduler=schedule"  # cron 表达式
      protocol: timer
      timeout: 60000

    # ---- Kafka 消费者 ----
    - name: trpc.${app}.${server}.KafkaConsumer
      address: broker:9092?topics=my_topic&group=my_group&strategy=range&maxRetry=10
      protocol: kafka
      timeout: 10000000

client:
  filter:
    - file
  namespace: ${namespace}
  timeout: 5000                        # 默认超时 ms
  service:
    # ---- MySQL（GORM 插件）----
    - name: trpc.mysql.myapp
      target: dsn://user:password@tcp(host:port)/d_mydb?charset=utf8mb4&parseTime=True&loc=Local

    # ---- Redis ----
    - name: trpc.redis.myapp
      target: redis://:password@host:port
      timeout: 60000

    # ---- 项目内 tRPC 服务（DNS/IP寻址）----
    - name: trpc.video_media.some_service.SomeService
      namespace: ${namespace}
      target: dns://trpc.video_media.some_service.SomeService
      timeout: 5000

    # ---- 外部 HTTP 服务（DNS 寻址）----
    - name: trpc.http.external
      target: dns://api.example.com
      timeout: 10000
      protocol: http

    # ---- COS 对象存储 ----
    - name: trpc.cos.Access
      namespace: Production
      network: tcp
      protocol: http
      target: dns://appid:bucketid
      timeout: 9000
      disable_servicerouter: true

plugins:
  # ---- 远程配置中心（local-yaml）----
  config:
    local-yaml:
      timeout: 3000
      address_list: ${local-yaml_address_list}
      providers:
        - name: local-yaml
          appid: ${app}.${server}
          env_name: ${env_name}
          namespace: ${namespace}
          tick: 2000                   # 同步间隔 ms

  # ---- 监控（file/metrics）----
  telemetry:
    file:
      verbose: error                   # debug / info / error
      config:
        metrics_config:
          enable: true
        traces_config:
          enable: true
          processor:
            sampler:
              fraction: 1              # 采样比例，生产环境建议 0.001
              error_fraction: 1        # 出错时采样比例
            disable_trace_body: false  # true 可提升性能
        logs_config:
          enable: true
          processor:
            level: INFO                # ERROR / INFO / DEBUG
        version: 1
      resource:
        platform: PCG-123             # 部署平台

  # ---- 服务发现 / 注册 ----
  # 公开项目通常不配置私有注册中心插件；客户端优先使用 ip://、dns://、dsn://。

  # ---- 日志 ----
  log:
    default:
      - writer: file                # file/metrics 远程日志
      - writer: file                   # 本地文件日志
        level: info
        writer_config:
          log_path: ${log_path}
          filename: trpc.log
          roll_type: size
          max_age: 7                   # 天
          max_size: 10                 # MB
          max_backups: 10
          compress: false

  # ---- 数据库插件（按需启用）----
  database:
    gorm:
      max_idle: 20
      max_open: 100
      max_lifetime: 180000             # ms
      logger:
        slow_threshold: 200            # ms
        log_level: 4                   # 1:Silent 2:Error 3:Warn 4:Info
```

### 配置要点

| 板块 | 关键配置 | 说明 |
|------|---------|------|
| **server.service** | `protocol` | `trpc` / `http` / `timer` / `kafka` |
| **server.service** | `registry: none` | 服务注册到DNS/IP |
| **client.service** | `target` | `dsn://`（数据库）/ `dns://`（内部服务）/ `dns://`（外部 HTTP）/ `redis://`（Redis） |
| **client.service** | `disable_servicerouter` | 跨命名空间调用时设为 `true` |
| **plugins.database.gorm** | `max_idle` / `max_open` | 连接池参数，按 QPS 调整 |
| **plugins.telemetry** | `fraction` | 采样率，生产环境不要设 1 |
| **timer 协议** | `network` | cron 表达式 + `?scheduler=schedule` |
| **kafka 协议** | `address` | `broker?topics=x&group=y&strategy=range` |
