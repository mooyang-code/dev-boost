# trpc-database 组件速查手册

> 仓库地址：`trpc.group/trpc-go/trpc-database`
> 本文档为 trpc-database 各数据层组件的快速参考指南。

---

## 1. 概述

trpc-database 是 tRPC-Go 框架的数据层组件集合。它封装了常见的开源数据库/中间件 SDK，使其能够复用 tRPC-Go 的**路由寻址、监控上报、拦截器（Filter）、配置管理**等生态能力，减少重复代码。

核心价值：
- 统一的 `trpc_go.yaml` 配置方式
- 自动接入 tRPC 调用链追踪和监控上报
- 支持 tRPC-Go 标准 selector、连接池与配置化路由
- 统一的连接池管理

---

## 2. 组件总览

### 关系型数据库

| 组件名 | 封装库 | 用途 | 推荐度 |
|--------|--------|------|--------|
| **gorm** | [gorm.io/gorm](https://github.com/go-gorm/gorm) | ORM 方式操作 MySQL/PostgreSQL/ClickHouse/SQLite | ⭐⭐⭐⭐⭐ |
| **mysql** | [go-sql-driver/mysql](https://github.com/go-sql-driver/mysql) + sqlx | 原生 SQL / sqlx 方式操作 MySQL | ⭐⭐⭐⭐ |
| **postgres** | 标准库 database/sql | 原生方式操作 PostgreSQL | ⭐⭐⭐ |

### 缓存 / KV 存储

| 组件名 | 封装库 | 用途 | 推荐度 |
|--------|--------|------|--------|
| **goredis** | [redis/go-redis](https://github.com/redis/go-redis) | Redis 客户端（功能更丰富） | ⭐⭐⭐⭐⭐ |
| **redis** | [gomodule/redigo](https://github.com/gomodule/redigo) | Redis 客户端（旧版封装） | ⭐⭐⭐ |
| **localcache** | 自研 | 单机本地 KV 缓存，LRU + TTL 淘汰 | ⭐⭐⭐⭐ |
| **etcd** | etcd 官方 SDK | 分布式 KV、配置中心、服务发现 | ⭐⭐⭐⭐ |
| **memcache** | 开源 SDK | Memcached 客户端 | ⭐⭐⭐ |

### 消息队列

| 组件名 | 封装库 | 用途 | 推荐度 |
|--------|--------|------|--------|
| **kafka** | [IBM/sarama](https://github.com/IBM/sarama) | Kafka 生产/消费 | ⭐⭐⭐⭐⭐ |
| **pulsar** | [apache/pulsar-client-go](https://github.com/apache/pulsar-client-go) | Pulsar 消息队列 | ⭐⭐⭐ |
| **rabbitmq** | 开源 SDK | RabbitMQ 消息队列 | ⭐⭐⭐ |
| **rocketmq-go** | rocketmq 5.x SDK | RocketMQ 消息队列 | ⭐⭐⭐ |

### 搜索 / 分析

| 组件名 | 封装库 | 用途 | 推荐度 |
|--------|--------|------|--------|
| **es** | [olivere/elastic](https://github.com/olivere/elastic) | Elasticsearch v6/v7 | ⭐⭐⭐⭐ |
| **clickhouse** | 通过 gorm 插件接入 | 列式分析数据库 | ⭐⭐⭐ |

### 文档数据库

| 组件名 | 封装库 | 用途 | 推荐度 |
|--------|--------|------|--------|
| **mongodb** | [mongo-driver](https://go.mongodb.org/mongo-driver) | MongoDB 文档存储 | ⭐⭐⭐⭐ |

### 其他

| 组件名 | 封装库 | 用途 | 推荐度 |
|--------|--------|------|--------|
| **tcvectordb** | 腾讯云向量数据库 SDK | 向量数据库 | ⭐⭐⭐ |
| **timer** | 自研 | 本地/分布式定时器 | ⭐⭐⭐ |
| **mqtt** | eclipse/paho.mqtt.golang | MQTT 协议 | ⭐⭐⭐ |

---

## 3. 核心组件快速上手

### 3.1 Gorm（推荐 ORM 方案）

```yaml
# trpc_go.yaml
client:
  service:
    - name: trpc.mysql.server.service
      target: dsn://root:123456@tcp(127.0.0.1:3306)/mydb?charset=utf8mb4&parseTime=True
```

```go
import "trpc.group/trpc-go/trpc-database/gorm"

// 初始化（需先调用 trpc.NewServer()）
cli, err := gorm.NewClientProxy("trpc.mysql.server.service")

// CRUD - 与标准 gorm 用法一致
cli.WithContext(ctx).Create(&user)
cli.WithContext(ctx).First(&user, 1)
cli.WithContext(ctx).Model(&user).Update("name", "new_name")
cli.WithContext(ctx).Delete(&user, 1)
```

> **重要**：务必使用 `WithContext(ctx)` 传递 tRPC 上下文，确保调用链追踪和监控生效。

### 3.2 GoRedis（推荐 Redis 方案）

```yaml
# trpc_go.yaml
client:
  service:
    - name: trpc.app.server.redis
      target: redis://:password@127.0.0.1:6379/0
      timeout: 60000
```

```go
import "trpc.group/trpc-go/trpc-database/goredis"

cli, err := goredis.New("trpc.app.server.redis")

// 标准 go-redis 用法，所有命令需传入 ctx
result, err := cli.Set(ctx, "key", "value", time.Minute).Result()
value, err := cli.Get(ctx, "key").Result()
```

**集群模式**：地址用逗号分隔：
```yaml
target: redis://:password@node1:6379,node2:6379,node3:6379/0
```

### 3.3 MySQL（原生 SQL / sqlx）

```yaml
# trpc_go.yaml
client:
  service:
    - name: trpc.mysql.xxx.xxx
      target: dsn://user:passwd@tcp(127.0.0.1:3306)/db?timeout=1s&parseTime=true&interpolateParams=true
```

```go
import "trpc.group/trpc-go/trpc-database/mysql"

proxy := mysql.NewClientProxy("trpc.mysql.xxx.xxx")

// 原生 SQL
_, err := proxy.Exec(ctx, "INSERT INTO users (name) VALUES (?)", "alice")

// sqlx: 查询到结构体
var user User
err := proxy.QueryToStruct(ctx, &user, "SELECT * FROM users WHERE id = ?", 1)

// sqlx: 查询多条
var users []User
err := proxy.QueryToStructs(ctx, &users, "SELECT * FROM users WHERE age > ?", 18)

// 事务
err := proxy.Transactionx(ctx, func(tx *sqlx.Tx) error {
    _, err := tx.Exec("UPDATE accounts SET balance = balance - ? WHERE id = ?", 100, 1)
    if err != nil {
        return err // 自动回滚
    }
    _, err = tx.Exec("UPDATE accounts SET balance = balance + ? WHERE id = ?", 100, 2)
    return err // nil 则自动提交
})
```

### 3.4 Kafka

**生产者：**

```yaml
# trpc_go.yaml
client:
  service:
    - name: trpc.kafka.producer.service
      target: kafka://127.0.0.1:9092?topic=my-topic

plugins:
  database:
    kafka: # 启用插件以支持优雅退出时自动关闭生产者
```

```go
import "trpc.group/trpc-go/trpc-database/kafka"

proxy := kafka.NewClientProxy("trpc.kafka.producer.service")
err := proxy.Produce(ctx, []byte("key"), []byte("value"))
```

**消费者：**

```yaml
# trpc_go.yaml
server:
  close_wait_time: 1000
  max_close_wait_time: 2000
  service:
    - name: trpc.kafka.consumer.service
      address: 127.0.0.1:9092?topics=my-topic&group=my-group
      protocol: kafka
```

```go
import (
    "trpc.group/trpc-go/trpc-database/kafka"
    "github.com/IBM/sarama"
)

type consumer struct{}

func (consumer) Handle(ctx context.Context, msg *sarama.ConsumerMessage) error {
    log.Infof("key=%s value=%s", msg.Key, msg.Value)
    return nil // 返回 nil 才确认消费成功；返回 error 会触发重试
}

func main() {
    s := trpc.NewServer()
    kafka.RegisterKafkaConsumerService(s.Service("trpc.kafka.consumer.service"), &consumer{})
    s.Serve()
}
```

> **注意**：Handle 中不要返回 error 来触发重试，容易导致消费卡住。建议业务自行实现重试逻辑。

### 3.5 LocalCache（本地缓存）

```go
import "trpc.group/trpc-go/trpc-database/localcache"

// 方式一：直接使用包级函数
localcache.Set("key", "value", 60) // TTL 60秒
val, found := localcache.Get("key")

// 方式二：创建独立实例（推荐）
lc := localcache.New(
    localcache.WithCapacity(10000),   // 最大容量
    localcache.WithExpiration(300),    // 默认 TTL 秒
)

lc.Set("key", "value")
val, found := lc.Get("key")

// 方式三：带自动加载
loadFn := func(ctx context.Context, key string) (interface{}, error) {
    return db.Query(key) // 缓存未命中时从数据源加载
}
lc := localcache.New(
    localcache.WithLoad(loadFn),
    localcache.WithExpiration(60),
)
val, err := lc.GetWithLoad(ctx, "user:123")
```

---

## 4. 配置模式参考

### 4.1 Gorm 连接池配置

```yaml
# trpc_go.yaml
database:
  gorm:
    max_idle: 20            # 最大空闲连接数（默认 10）
    max_open: 100           # 最大活跃连接数（默认 10000）
    max_lifetime: 180000    # 连接最大生命周期，毫秒（默认 3min）
    conn_max_idle_time: 0   # 空闲连接最长保持时间，毫秒（默认 0 不限制）
    logger:
      slow_threshold: 200   # 慢查询阈值，毫秒
      log_level: 4          # 1:Silent 2:Error 3:Warn 4:Info
    service:
      - name: trpc.mysql.server.service
        max_idle: 10
        max_open: 50
```

### 4.2 MySQL 连接池配置

```yaml
plugins:
  database:
    mysql:
      max_idle: 20          # 最大空闲连接数
      max_open: 100         # 最大活跃连接数
      max_lifetime: 180000  # 连接最大生命周期，毫秒
```

### 4.3 Redis（redigo）连接池配置

```yaml
plugins:
  database:
    redis:
      max_idle: 2048        # 最大空闲连接数
      max_active: 100       # 最大活跃连接数
      idle_timeout: 180000  # 空闲超时，毫秒
      default_timeout: 1000 # 读写超时，毫秒
```

### 4.4 GoRedis 连接池配置（通过 URL 参数）

```yaml
client:
  service:
    - name: trpc.app.server.redis
      # 连接池参数直接写在 URL 中
      target: redis://:pwd@host:6379/0?pool_size=100&min_idle_conns=10&conn_max_idle_time=300000
```

### 4.5 MongoDB 连接池配置

```yaml
client:
  service:
    - name: trpc.mongodb.xxx.xxx
      target: mongodb://user:pwd@host:27017/db?maxPoolSize=200&minPoolSize=10&maxIdleTimeMS=300000
      timeout: 800
```

---

## 5. 最佳实践

### 5.1 始终使用 WithContext 传递上下文

```go
// Gorm - 确保调用链追踪
cli.WithContext(ctx).Find(&users)

// GoRedis - 所有命令已要求 ctx 参数
cli.Get(ctx, "key")

// MySQL - 所有方法已要求 ctx 参数
proxy.Exec(ctx, "SELECT 1")
```

### 5.2 连接池配置建议

| 参数 | 建议值 | 说明 |
|------|--------|------|
| max_idle | 10~50 | 根据并发量调整，避免设为 0 导致不复用连接 |
| max_open | 50~200 | 不要超过数据库服务端的连接上限 |
| max_lifetime | 180000 (3min) | 避免使用过期连接，需小于数据库 wait_timeout |
| idle_timeout | 180000 (3min) | 定期回收空闲连接 |

> **关键提醒**：MySQL 插件 v0.3.0 之前，`max_idle` 未配置时默认为 0（不保留空闲连接），高并发下会导致 `TIME_WAIT` 堆积。务必显式配置。

### 5.3 超时处理

**Gorm 超时**：框架配置中的 `timeout` 对 gorm 不生效（插件会强制置零），需通过 DSN 参数或 `context.WithTimeout` 控制：
```yaml
# 通过 DSN 控制连接读写超时
target: dsn://root:pwd@tcp(host:3306)/db?readTimeout=500ms&writeTimeout=500ms&timeout=3s
```

```go
// 通过 context 控制单次请求超时
ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
defer cancel()
cli.WithContext(ctx).Find(&users)
```

**Kafka 生产者超时**：
```yaml
# 方式一：URL 参数（优先级最高）
target: kafka://host:9092?topic=test&produceTimeout=500

# 方式二：全局变量
kafka.Timeout = 2 * time.Second
```

### 5.4 Kafka 消费者注意事项

- Handle 返回 `nil` → 确认消费成功
- Handle 返回 `error` → 休眠 3s 后重试同一条消息（**容易导致消费卡住**）
- **推荐做法**：Handle 内部自行处理错误和重试，始终返回 `nil`
- 配置 `close_wait_time` 和 `max_close_wait_time` 以确保优雅退出

### 5.5 单元测试 Mock

**Gorm（使用 sqlmock，与官方 README 推荐一致）：**
```go
db, mock, _ := sqlmock.New()
defer db.Close()
gormDB, _ := gorm.Open(mysql.New(mysql.Config{Conn: db}))

mock.ExpectQuery(`SELECT`).WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(1))
```

**GoRedis（使用 redismock）：**
- 参考：https://github.com/go-redis/redismock

### 5.6 服务名命名规范

tRPC 服务名采用四段式：`trpc.{app}.{server}.{service}`

- Gorm 通过第二段识别驱动：`trpc.mysql.*.*`、`trpc.clickhouse.*.*`、`trpc.postgres.*.*`
- 非标准名称默认使用 mysql 驱动
- Kafka 消费者的 service name 可任意命名

### 5.7 公开项目寻址

公开 GitHub 项目优先使用标准直连或 DNS/IP selector：

```yaml
# Gorm
target: dsn://user:pwd@tcp(127.0.0.1:3306)/db?parseTime=True

# Redis (redigo)
target: redis://:password@127.0.0.1:6379/0

# tRPC service by IP
target: ip://127.0.0.1:9000

# HTTP service by DNS
target: dns://api.example.com:443
```

公开项目不要保留私有注册中心专用 scheme；如果需要服务发现，优先选择项目已显式引入的公开组件。

---

## 6. 常见问题速查

| 问题 | 组件 | 解决方案 |
|------|------|----------|
| `Context Canceled` | gorm/mysql | 删除 `client.timeout` 全局配置，或升级到最新版本 |
| `connection pool exhausted` | redis | 增大 `max_active`；检查是否有连接泄漏（Pipeline 未 Close） |
| `TIME_WAIT` 堆积 | mysql | 显式配置 `max_idle >= 10`，避免默认值 0 |
| `interpolateParams` 错误 | mysql | DSN 中添加 `&interpolateParams=true` |
| `Message contents does not match its CRC` | kafka | target 添加 `compression=none` 关闭 gzip |
| 消费卡住/无限重试 | kafka | Handle 内自行处理错误，始终返回 nil |
| Watch 长时间后收不到事件 | etcd | target 添加 `dial_keep_alive_time=30s&dial_keep_alive_timeout=5s` |
| 聚合查询 NULL 扫描失败 | mysql | SQL 使用 `COALESCE` 或 Go 中使用 `sql.NullInt64` |
| `unsupported db engine` | gorm | 服务名第二段需为 mysql/clickhouse/postgres/sqlite |
