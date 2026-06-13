# Go 设计模式

## 概述

本文档涵盖 Go 语言中常用的设计模式和惯用法（idioms）。

---

## 创建型模式

### 1. 工厂模式（Factory Pattern）

#### 简单工厂

```go
// domain/user.go
package domain

import "errors"

// UserType 用户类型
type UserType string

const (
	UserTypeAdmin    UserType = "admin"
	UserTypeCustomer UserType = "customer"
	UserTypeGuest    UserType = "guest"
)

// User 用户接口
type User interface {
	GetPermissions() []string
}

// AdminUser 管理员用户
type AdminUser struct {
	id string
}

func (u *AdminUser) GetPermissions() []string {
	return []string{"read", "write", "delete"}
}

// CustomerUser 普通用户
type CustomerUser struct {
	id string
}

func (u *CustomerUser) GetPermissions() []string {
	return []string{"read", "write"}
}

// GuestUser 访客用户
type GuestUser struct {
	id string
}

func (u *GuestUser) GetPermissions() []string {
	return []string{"read"}
}

// NewUser 用户工厂（简单工厂）
func NewUser(id string, userType UserType) (User, error) {
	switch userType {
	case UserTypeAdmin:
		return &AdminUser{id: id}, nil
	case UserTypeCustomer:
		return &CustomerUser{id: id}, nil
	case UserTypeGuest:
		return &GuestUser{id: id}, nil
	default:
		return nil, errors.New("未知用户类型")
	}
}
```

#### 工厂方法

```go
// infrastructure/logger/logger.go
package logger

import (
	"io"
	"log"
	"os"
)

// Logger 日志接口
type Logger interface {
	Info(msg string)
	Error(msg string)
}

// consoleLogger 控制台日志
type consoleLogger struct {
	logger *log.Logger
}

func (l *consoleLogger) Info(msg string) {
	l.logger.Println("[INFO]", msg)
}

func (l *consoleLogger) Error(msg string) {
	l.logger.Println("[ERROR]", msg)
}

// fileLogger 文件日志
type fileLogger struct {
	logger *log.Logger
	file   *os.File
}

func (l *fileLogger) Info(msg string) {
	l.logger.Println("[INFO]", msg)
}

func (l *fileLogger) Error(msg string) {
	l.logger.Println("[ERROR]", msg)
}

// NewConsoleLogger 创建控制台日志
func NewConsoleLogger() Logger {
	return &consoleLogger{
		logger: log.New(os.Stdout, "", log.LstdFlags),
	}
}

// NewFileLogger 创建文件日志
func NewFileLogger(filename string) (Logger, error) {
	file, err := os.OpenFile(filename, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
	if err != nil {
		return nil, err
	}

	return &fileLogger{
		logger: log.New(file, "", log.LstdFlags),
		file:   file,
	}, nil
}

// NewLogger 通用工厂
func NewLogger(logType string, output io.Writer) Logger {
	switch logType {
	case "console":
		return &consoleLogger{logger: log.New(output, "", log.LstdFlags)}
	case "file":
		return &fileLogger{logger: log.New(output, "", log.LstdFlags)}
	default:
		return NewConsoleLogger()
	}
}
```

### 2. 建造者模式（Builder Pattern）

```go
// domain/query_builder.go
package domain

import "strings"

// SQLQuery SQL 查询
type SQLQuery struct {
	table      string
	columns    []string
	where      []string
	orderBy    string
	limit      int
	offset     int
}

// QueryBuilder 查询建造者
type QueryBuilder struct {
	query *SQLQuery
}

// NewQueryBuilder 创建建造者
func NewQueryBuilder() *QueryBuilder {
	return &QueryBuilder{
		query: &SQLQuery{},
	}
}

// Table 设置表名
func (b *QueryBuilder) Table(table string) *QueryBuilder {
	b.query.table = table
	return b
}

// Select 设置查询列
func (b *QueryBuilder) Select(columns ...string) *QueryBuilder {
	b.query.columns = columns
	return b
}

// Where 添加条件
func (b *QueryBuilder) Where(condition string) *QueryBuilder {
	b.query.where = append(b.query.where, condition)
	return b
}

// OrderBy 设置排序
func (b *QueryBuilder) OrderBy(orderBy string) *QueryBuilder {
	b.query.orderBy = orderBy
	return b
}

// Limit 设置限制
func (b *QueryBuilder) Limit(limit int) *QueryBuilder {
	b.query.limit = limit
	return b
}

// Offset 设置偏移
func (b *QueryBuilder) Offset(offset int) *QueryBuilder {
	b.query.offset = offset
	return b
}

// Build 构建查询
func (b *QueryBuilder) Build() string {
	var sb strings.Builder

	// SELECT
	sb.WriteString("SELECT ")
	if len(b.query.columns) == 0 {
		sb.WriteString("*")
	} else {
		sb.WriteString(strings.Join(b.query.columns, ", "))
	}

	// FROM
	sb.WriteString(" FROM ")
	sb.WriteString(b.query.table)

	// WHERE
	if len(b.query.where) > 0 {
		sb.WriteString(" WHERE ")
		sb.WriteString(strings.Join(b.query.where, " AND "))
	}

	// ORDER BY
	if b.query.orderBy != "" {
		sb.WriteString(" ORDER BY ")
		sb.WriteString(b.query.orderBy)
	}

	// LIMIT
	if b.query.limit > 0 {
		sb.WriteString(" LIMIT ")
		sb.WriteString(string(rune(b.query.limit)))
	}

	// OFFSET
	if b.query.offset > 0 {
		sb.WriteString(" OFFSET ")
		sb.WriteString(string(rune(b.query.offset)))
	}

	return sb.String()
}

// 使用示例
// query := NewQueryBuilder().
//     Table("users").
//     Select("id", "name", "email").
//     Where("age > 18").
//     Where("status = 'active'").
//     OrderBy("created_at DESC").
//     Limit(10).
//     Build()
```

### 3. 单例模式（Singleton Pattern）

```go
// infrastructure/database/database.go
package database

import (
	"sync"

	"gorm.io/gorm"  // 生产环境通过 trpc-database/gorm 插件获取 *gorm.DB
	instance *gorm.DB
	once     sync.Once
)

// GetDB 获取数据库单例
func GetDB() *gorm.DB {
	once.Do(func() {
		// 初始化数据库连接
		instance = initDB()
	})
	return instance
}

func initDB() *gorm.DB {
	// 数据库初始化逻辑
	return nil
}
```

---

## 结构型模式

### 1. 适配器模式（Adapter Pattern）

```go
// infrastructure/adapters/stripe_adapter.go
package adapters

import (
	"context"
	"myapp/domain/ports"
)

// StripeClient 第三方 Stripe 客户端
type StripeClient struct {
	apiKey string
}

// ChargeCard Stripe 原生方法
func (c *StripeClient) ChargeCard(amount int, cardToken string) (string, error) {
	// 调用 Stripe API
	return "stripe_transaction_id", nil
}

// StripePaymentAdapter Stripe 支付适配器（适配 PaymentGateway 接口）
type StripePaymentAdapter struct {
	client *StripeClient
}

// NewStripePaymentAdapter 创建适配器
func NewStripePaymentAdapter(apiKey string) ports.PaymentGateway {
	return &StripePaymentAdapter{
		client: &StripeClient{apiKey: apiKey},
	}
}

// ProcessPayment 实现 PaymentGateway 接口
func (a *StripePaymentAdapter) ProcessPayment(ctx context.Context, amount int64, method string) (string, error) {
	// 适配逻辑：将接口参数转换为 Stripe 参数
	transactionID, err := a.client.ChargeCard(int(amount), method)
	if err != nil {
		return "", err
	}
	return transactionID, nil
}
```

### 2. 装饰器模式（Decorator Pattern）

```go
// infrastructure/logger/decorator.go
package logger

import "time"

// Logger 日志接口
type Logger interface {
	Log(msg string)
}

// basicLogger 基础日志
type basicLogger struct{}

func (l *basicLogger) Log(msg string) {
	println(msg)
}

// TimestampDecorator 时间戳装饰器
type TimestampDecorator struct {
	logger Logger
}

func NewTimestampDecorator(logger Logger) Logger {
	return &TimestampDecorator{logger: logger}
}

func (d *TimestampDecorator) Log(msg string) {
	timestamp := time.Now().Format("2006-01-02 15:04:05")
	d.logger.Log("[" + timestamp + "] " + msg)
}

// LevelDecorator 日志级别装饰器
type LevelDecorator struct {
	logger Logger
	level  string
}

func NewLevelDecorator(logger Logger, level string) Logger {
	return &LevelDecorator{logger: logger, level: level}
}

func (d *LevelDecorator) Log(msg string) {
	d.logger.Log("[" + d.level + "] " + msg)
}

// 使用示例
// logger := &basicLogger{}
// logger = NewTimestampDecorator(logger)
// logger = NewLevelDecorator(logger, "INFO")
// logger.Log("Hello World")
// 输出：[2024-01-01 12:00:00] [INFO] Hello World
```

### 3. 代理模式（Proxy Pattern）

```go
// infrastructure/cache/cache_proxy.go
package cache

import (
	"context"
	"myapp/domain/repositories"
	"time"
)

// CachedUserRepository 用户仓储缓存代理
type CachedUserRepository struct {
	repo  repositories.UserRepository
	cache Cache
	ttl   time.Duration
}

// NewCachedUserRepository 创建缓存代理
func NewCachedUserRepository(
	repo repositories.UserRepository,
	cache Cache,
	ttl time.Duration,
) repositories.UserRepository {
	return &CachedUserRepository{
		repo:  repo,
		cache: cache,
		ttl:   ttl,
	}
}

// FindByID 查找用户（带缓存）
func (r *CachedUserRepository) FindByID(ctx context.Context, id string) (*User, error) {
	// 1. 尝试从缓存获取
	cacheKey := "user:" + id
	if user, found := r.cache.Get(cacheKey); found {
		return user.(*User), nil
	}

	// 2. 缓存未命中，从数据库查询
	user, err := r.repo.FindByID(ctx, id)
	if err != nil {
		return nil, err
	}

	// 3. 写入缓存
	r.cache.Set(cacheKey, user, r.ttl)

	return user, nil
}

// Cache 缓存接口
type Cache interface {
	Get(key string) (interface{}, bool)
	Set(key string, value interface{}, ttl time.Duration)
}
```

---

## 行为型模式

### 1. 策略模式（Strategy Pattern）

```go
// domain/strategies/discount_strategy.go
package strategies

import "myapp/domain/value_objects"

// DiscountStrategy 折扣策略接口
type DiscountStrategy interface {
	Calculate(price value_objects.Money) value_objects.Money
}

// NoDiscountStrategy 无折扣策略
type NoDiscountStrategy struct{}

func (s *NoDiscountStrategy) Calculate(price value_objects.Money) value_objects.Money {
	return price
}

// PercentageDiscountStrategy 百分比折扣策略
type PercentageDiscountStrategy struct {
	percentage int64
}

func NewPercentageDiscountStrategy(percentage int64) DiscountStrategy {
	return &PercentageDiscountStrategy{percentage: percentage}
}

func (s *PercentageDiscountStrategy) Calculate(price value_objects.Money) value_objects.Money {
	discountAmount := price.Amount() * s.percentage / 100
	finalPrice, _ := value_objects.NewMoney(price.Amount()-discountAmount, price.Currency())
	return finalPrice
}

// FixedAmountDiscountStrategy 固定金额折扣策略
type FixedAmountDiscountStrategy struct {
	amount value_objects.Money
}

func NewFixedAmountDiscountStrategy(amount value_objects.Money) DiscountStrategy {
	return &FixedAmountDiscountStrategy{amount: amount}
}

func (s *FixedAmountDiscountStrategy) Calculate(price value_objects.Money) value_objects.Money {
	finalPrice, _ := price.Add(s.amount.Multiply(-1))
	return finalPrice
}

// PriceCalculator 价格计算器
type PriceCalculator struct {
	strategy DiscountStrategy
}

func NewPriceCalculator(strategy DiscountStrategy) *PriceCalculator {
	return &PriceCalculator{strategy: strategy}
}

func (c *PriceCalculator) SetStrategy(strategy DiscountStrategy) {
	c.strategy = strategy
}

func (c *PriceCalculator) Calculate(price value_objects.Money) value_objects.Money {
	return c.strategy.Calculate(price)
}

// 使用示例
// price, _ := value_objects.NewMoney(10000, "CNY")
// calculator := NewPriceCalculator(NewPercentageDiscountStrategy(20))
// finalPrice := calculator.Calculate(price)  // 8000
```

### 2. 观察者模式（Observer Pattern）

```go
// domain/events/event_dispatcher.go
package events

import "sync"

// Event 事件接口
type Event interface {
	Name() string
}

// EventHandler 事件处理器
type EventHandler func(event Event)

// EventDispatcher 事件分发器
type EventDispatcher struct {
	handlers map[string][]EventHandler
	mu       sync.RWMutex
}

// NewEventDispatcher 创建事件分发器
func NewEventDispatcher() *EventDispatcher {
	return &EventDispatcher{
		handlers: make(map[string][]EventHandler),
	}
}

// Subscribe 订阅事件
func (d *EventDispatcher) Subscribe(eventName string, handler EventHandler) {
	d.mu.Lock()
	defer d.mu.Unlock()

	d.handlers[eventName] = append(d.handlers[eventName], handler)
}

// Dispatch 分发事件
func (d *EventDispatcher) Dispatch(event Event) {
	d.mu.RLock()
	handlers := d.handlers[event.Name()]
	d.mu.RUnlock()

	for _, handler := range handlers {
		go handler(event) // 异步处理
	}
}

// OrderPlacedEvent 订单已下单事件
type OrderPlacedEvent struct {
	orderID string
	userID  string
}

func (e OrderPlacedEvent) Name() string {
	return "order.placed"
}

// 使用示例
// dispatcher := NewEventDispatcher()
//
// // 订阅事件
// dispatcher.Subscribe("order.placed", func(event Event) {
//     e := event.(OrderPlacedEvent)
//     fmt.Println("发送邮件通知:", e.userID)
// })
//
// dispatcher.Subscribe("order.placed", func(event Event) {
//     e := event.(OrderPlacedEvent)
//     fmt.Println("更新库存:", e.orderID)
// })
//
// // 分发事件
// dispatcher.Dispatch(OrderPlacedEvent{orderID: "123", userID: "456"})
```

### 3. 责任链模式（Chain of Responsibility）

```go
// middleware/chain.go
package middleware

import "net/http"

// Middleware 中间件类型
type Middleware func(http.Handler) http.Handler

// Chain 中间件链
type Chain struct {
	middlewares []Middleware
}

// NewChain 创建中间件链
func NewChain(middlewares ...Middleware) Chain {
	return Chain{middlewares: middlewares}
}

// Then 应用中间件链
func (c Chain) Then(h http.Handler) http.Handler {
	for i := len(c.middlewares) - 1; i >= 0; i-- {
		h = c.middlewares[i](h)
	}
	return h
}

// LoggingMiddleware 日志中间件
func LoggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		println("Request:", r.Method, r.URL.Path)
		next.ServeHTTP(w, r)
	})
}

// AuthMiddleware 认证中间件
func AuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := r.Header.Get("Authorization")
		if token == "" {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// RecoveryMiddleware 恢复中间件
func RecoveryMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if err := recover(); err != nil {
				println("Panic:", err)
				http.Error(w, "Internal Server Error", http.StatusInternalServerError)
			}
		}()
		next.ServeHTTP(w, r)
	})
}

// 使用示例
// chain := NewChain(
//     RecoveryMiddleware,
//     LoggingMiddleware,
//     AuthMiddleware,
// )
// http.Handle("/api", chain.Then(apiHandler))
```

---

## Go 特有模式

### 1. Option 模式

```go
// infrastructure/server/server.go
package server

import "time"

// Server 服务器
type Server struct {
	host         string
	port         int
	readTimeout  time.Duration
	writeTimeout time.Duration
	maxConns     int
}

// Option 服务器选项
type Option func(*Server)

// WithHost 设置主机
func WithHost(host string) Option {
	return func(s *Server) {
		s.host = host
	}
}

// WithPort 设置端口
func WithPort(port int) Option {
	return func(s *Server) {
		s.port = port
	}
}

// WithReadTimeout 设置读超时
func WithReadTimeout(timeout time.Duration) Option {
	return func(s *Server) {
		s.readTimeout = timeout
	}
}

// WithWriteTimeout 设置写超时
func WithWriteTimeout(timeout time.Duration) Option {
	return func(s *Server) {
		s.writeTimeout = timeout
	}
}

// WithMaxConns 设置最大连接数
func WithMaxConns(maxConns int) Option {
	return func(s *Server) {
		s.maxConns = maxConns
	}
}

// NewServer 创建服务器
func NewServer(opts ...Option) *Server {
	// 默认值
	s := &Server{
		host:         "localhost",
		port:         8080,
		readTimeout:  30 * time.Second,
		writeTimeout: 30 * time.Second,
		maxConns:     1000,
	}

	// 应用选项
	for _, opt := range opts {
		opt(s)
	}

	return s
}

// 使用示例
// server := NewServer(
//     WithHost("0.0.0.0"),
//     WithPort(9000),
//     WithReadTimeout(60 * time.Second),
// )
```

### 2. 上下文模式（Context Pattern）

```go
// application/services/user_service.go
package services

import (
	"context"
	"time"
)

// UserService 用户服务
type UserService struct {
	repo UserRepository
}

// GetUser 获取用户（带超时控制）
func (s *UserService) GetUser(ctx context.Context, id string) (*User, error) {
	// 创建带超时的子上下文
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	// 使用通道接收结果
	resultCh := make(chan *User)
	errCh := make(chan error)

	go func() {
		user, err := s.repo.FindByID(ctx, id)
		if err != nil {
			errCh <- err
			return
		}
		resultCh <- user
	}()

	// 等待结果或超时
	select {
	case user := <-resultCh:
		return user, nil
	case err := <-errCh:
		return nil, err
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}
```

### 3. 并发模式

#### Worker Pool

```go
// pkg/worker/pool.go
package worker

import "sync"

// Job 任务
type Job func()

// WorkerPool 工作池
type WorkerPool struct {
	maxWorkers int
	jobQueue   chan Job
	wg         sync.WaitGroup
}

// NewWorkerPool 创建工作池
func NewWorkerPool(maxWorkers int, jobQueueSize int) *WorkerPool {
	return &WorkerPool{
		maxWorkers: maxWorkers,
		jobQueue:   make(chan Job, jobQueueSize),
	}
}

// Start 启动工作池
func (p *WorkerPool) Start() {
	for i := 0; i < p.maxWorkers; i++ {
		p.wg.Add(1)
		go p.worker()
	}
}

// worker 工作协程
func (p *WorkerPool) worker() {
	defer p.wg.Done()

	for job := range p.jobQueue {
		job()
	}
}

// Submit 提交任务
func (p *WorkerPool) Submit(job Job) {
	p.jobQueue <- job
}

// Stop 停止工作池
func (p *WorkerPool) Stop() {
	close(p.jobQueue)
	p.wg.Wait()
}

// 使用示例
// pool := NewWorkerPool(10, 100)
// pool.Start()
//
// for i := 0; i < 100; i++ {
//     pool.Submit(func() {
//         fmt.Println("Processing job")
//     })
// }
//
// pool.Stop()
```

#### Pipeline

```go
// pkg/pipeline/pipeline.go
package pipeline

// Generator 生成器
func Generator(nums ...int) <-chan int {
	out := make(chan int)
	go func() {
		for _, n := range nums {
			out <- n
		}
		close(out)
	}()
	return out
}

// Square 平方
func Square(in <-chan int) <-chan int {
	out := make(chan int)
	go func() {
		for n := range in {
			out <- n * n
		}
		close(out)
	}()
	return out
}

// Filter 过滤
func Filter(in <-chan int, fn func(int) bool) <-chan int {
	out := make(chan int)
	go func() {
		for n := range in {
			if fn(n) {
				out <- n
			}
		}
		close(out)
	}()
	return out
}

// 使用示例
// nums := Generator(1, 2, 3, 4, 5)
// squared := Square(nums)
// filtered := Filter(squared, func(n int) bool { return n > 10 })
//
// for n := range filtered {
//     fmt.Println(n)  // 16, 25
// }
```

---

## 总结

| 模式 | 场景 | Go 实现要点 |
|------|------|------------|
| **工厂模式** | 创建复杂对象 | 简单工厂函数 + 接口 |
| **建造者模式** | 构建复杂对象 | 链式调用 |
| **单例模式** | 全局唯一实例 | sync.Once |
| **适配器模式** | 接口转换 | 实现目标接口 |
| **装饰器模式** | 动态增强功能 | 接口嵌套 |
| **代理模式** | 控制访问 | 包装原始对象 |
| **策略模式** | 算法切换 | 接口 + 多实现 |
| **观察者模式** | 事件通知 | Channel + Goroutine |
| **责任链模式** | 请求处理链 | 中间件模式 |
| **Option 模式** | 可选参数 | 函数选项 |
| **Worker Pool** | 并发任务处理 | Goroutine + Channel |
| **Pipeline** | 数据流处理 | Channel 链 |

Go 语言的接口、Goroutine 和 Channel 特性使得很多设计模式的实现更加简洁和自然。
