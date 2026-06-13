# Domain-Driven Design（领域驱动设计）

## 概述

DDD 是 Eric Evans 提出的软件设计方法论，核心思想是**将复杂业务领域建模为软件模型**，通过统一语言（Ubiquitous Language）连接业务和技术。

---

## 核心概念

### 战略设计（Strategic Design）

| 概念 | 说明 | 示例 |
|------|------|------|
| **限界上下文（Bounded Context）** | 明确的业务边界 | 订单上下文、用户上下文、支付上下文 |
| **通用语言（Ubiquitous Language）** | 业务和技术团队共享的语言 | "下单"、"支付"、"发货" |
| **上下文映射（Context Mapping）** | 不同上下文之间的关系 | 订单上下文 → 支付上下文 |
| **防腐层（Anti-Corruption Layer）** | 隔离外部系统的影响 | 适配第三方支付接口 |

### 战术设计（Tactical Design）

| 概念 | 说明 | Go 实现 |
|------|------|---------|
| **实体（Entity）** | 具有唯一标识的对象 | User、Order |
| **值对象（Value Object）** | 无标识，不可变 | Email、Money、Address |
| **聚合（Aggregate）** | 一组相关对象的集合 | Order + OrderItem |
| **聚合根（Aggregate Root）** | 聚合的入口 | Order |
| **领域服务（Domain Service）** | 无状态的业务逻辑 | PricingService |
| **领域事件（Domain Event）** | 领域内发生的事件 | OrderPlaced、PaymentCompleted |
| **仓储（Repository）** | 持久化接口 | OrderRepository |
| **工厂（Factory）** | 创建复杂对象 | NewOrder() |

---

## Go 语言实现

### 1. 值对象（Value Object）

值对象是**不可变的**，通过值比较，没有唯一标识。

```go
// domain/value_objects/email.go
package value_objects

import (
	"errors"
	"regexp"
)

// Email 邮箱值对象
type Email struct {
	value string
}

// NewEmail 创建邮箱
func NewEmail(value string) (Email, error) {
	if !isValidEmail(value) {
		return Email{}, errors.New("无效的邮箱格式")
	}
	return Email{value: value}, nil
}

// String 获取值
func (e Email) String() string {
	return e.value
}

// Equals 值对象相等性比较
func (e Email) Equals(other Email) bool {
	return e.value == other.value
}

func isValidEmail(email string) bool {
	re := regexp.MustCompile(`^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`)
	return re.MatchString(email)
}
```

```go
// domain/value_objects/money.go
package value_objects

import "errors"

// Money 货币值对象
type Money struct {
	amount   int64  // 金额（分）
	currency string // 货币类型
}

// NewMoney 创建货币
func NewMoney(amount int64, currency string) (Money, error) {
	if amount < 0 {
		return Money{}, errors.New("金额不能为负数")
	}
	if currency == "" {
		return Money{}, errors.New("货币类型不能为空")
	}
	return Money{amount: amount, currency: currency}, nil
}

// Amount 获取金额
func (m Money) Amount() int64 {
	return m.amount
}

// Currency 获取货币类型
func (m Money) Currency() string {
	return m.currency
}

// Add 金额相加（值对象操作返回新对象）
func (m Money) Add(other Money) (Money, error) {
	if m.currency != other.currency {
		return Money{}, errors.New("货币类型不匹配")
	}
	return Money{
		amount:   m.amount + other.amount,
		currency: m.currency,
	}, nil
}

// Multiply 金额乘法
func (m Money) Multiply(factor int64) Money {
	return Money{
		amount:   m.amount * factor,
		currency: m.currency,
	}
}
```

### 2. 实体（Entity）

实体具有**唯一标识**，通过 ID 比较。

```go
// domain/entities/user.go
package entities

import (
	"errors"
	"myapp/domain/value_objects"
	"time"
)

// User 用户实体
type User struct {
	id        string
	email     value_objects.Email
	name      string
	createdAt time.Time
}

// NewUser 创建用户
func NewUser(id string, email value_objects.Email, name string) (*User, error) {
	if id == "" {
		return nil, errors.New("用户 ID 不能为空")
	}
	if name == "" {
		return nil, errors.New("姓名不能为空")
	}

	return &User{
		id:        id,
		email:     email,
		name:      name,
		createdAt: time.Now(),
	}, nil
}

// ID 获取 ID
func (u *User) ID() string {
	return u.id
}

// Email 获取邮箱
func (u *User) Email() value_objects.Email {
	return u.email
}

// Name 获取姓名
func (u *User) Name() string {
	return u.name
}

// ChangeEmail 修改邮箱（业务行为）
func (u *User) ChangeEmail(newEmail value_objects.Email) {
	u.email = newEmail
}

// Equals 实体相等性比较（通过 ID）
func (u *User) Equals(other *User) bool {
	return u.id == other.id
}
```

### 3. 聚合（Aggregate）

聚合是**一组相关对象的集合**，通过聚合根访问。

```go
// domain/aggregates/order.go
package aggregates

import (
	"errors"
	"myapp/domain/value_objects"
	"time"
)

// OrderStatus 订单状态
type OrderStatus string

const (
	OrderStatusPending   OrderStatus = "pending"
	OrderStatusPaid      OrderStatus = "paid"
	OrderStatusShipped   OrderStatus = "shipped"
	OrderStatusCancelled OrderStatus = "cancelled"
)

// OrderItem 订单项（值对象）
type OrderItem struct {
	productID string
	quantity  int64
	price     value_objects.Money
}

// NewOrderItem 创建订单项
func NewOrderItem(productID string, quantity int64, price value_objects.Money) (OrderItem, error) {
	if productID == "" {
		return OrderItem{}, errors.New("商品 ID 不能为空")
	}
	if quantity <= 0 {
		return OrderItem{}, errors.New("数量必须大于 0")
	}
	return OrderItem{
		productID: productID,
		quantity:  quantity,
		price:     price,
	}, nil
}

// Subtotal 计算小计
func (i OrderItem) Subtotal() value_objects.Money {
	return i.price.Multiply(i.quantity)
}

// Order 订单聚合根
type Order struct {
	id        string
	userID    string
	items     []OrderItem
	status    OrderStatus
	total     value_objects.Money
	createdAt time.Time
}

// NewOrder 创建订单（工厂方法）
func NewOrder(id, userID string, items []OrderItem) (*Order, error) {
	if id == "" {
		return nil, errors.New("订单 ID 不能为空")
	}
	if userID == "" {
		return nil, errors.New("用户 ID 不能为空")
	}
	if len(items) == 0 {
		return nil, errors.New("订单项不能为空")
	}

	// 计算总金额
	total, err := calculateTotal(items)
	if err != nil {
		return nil, err
	}

	return &Order{
		id:        id,
		userID:    userID,
		items:     items,
		status:    OrderStatusPending,
		total:     total,
		createdAt: time.Now(),
	}, nil
}

// ID 获取 ID
func (o *Order) ID() string {
	return o.id
}

// UserID 获取用户 ID
func (o *Order) UserID() string {
	return o.userID
}

// Items 获取订单项
func (o *Order) Items() []OrderItem {
	return o.items
}

// Status 获取状态
func (o *Order) Status() OrderStatus {
	return o.status
}

// Total 获取总金额
func (o *Order) Total() value_objects.Money {
	return o.total
}

// Pay 支付订单（业务规则）
func (o *Order) Pay() error {
	if o.status != OrderStatusPending {
		return errors.New("只有待支付订单可以支付")
	}
	o.status = OrderStatusPaid
	return nil
}

// Ship 发货（业务规则）
func (o *Order) Ship() error {
	if o.status != OrderStatusPaid {
		return errors.New("只有已支付订单可以发货")
	}
	o.status = OrderStatusShipped
	return nil
}

// Cancel 取消订单（业务规则）
func (o *Order) Cancel() error {
	if o.status == OrderStatusShipped {
		return errors.New("已发货订单不能取消")
	}
	o.status = OrderStatusCancelled
	return nil
}

// AddItem 添加订单项（业务规则）
func (o *Order) AddItem(item OrderItem) error {
	if o.status != OrderStatusPending {
		return errors.New("只有待支付订单可以添加商品")
	}

	o.items = append(o.items, item)

	// 重新计算总金额
	total, err := calculateTotal(o.items)
	if err != nil {
		return err
	}
	o.total = total

	return nil
}

// calculateTotal 计算总金额
func calculateTotal(items []OrderItem) (value_objects.Money, error) {
	if len(items) == 0 {
		return value_objects.Money{}, errors.New("订单项不能为空")
	}

	total := items[0].Subtotal()
	for i := 1; i < len(items); i++ {
		var err error
		total, err = total.Add(items[i].Subtotal())
		if err != nil {
			return value_objects.Money{}, err
		}
	}

	return total, nil
}
```

### 4. 领域服务（Domain Service）

当业务逻辑不属于任何实体或值对象时，使用领域服务。

```go
// domain/services/pricing_service.go
package services

import (
	"myapp/domain/value_objects"
)

// PricingService 定价服务（领域服务）
type PricingService struct{}

// NewPricingService 创建定价服务
func NewPricingService() *PricingService {
	return &PricingService{}
}

// CalculateDiscount 计算折扣（跨多个聚合的业务逻辑）
func (s *PricingService) CalculateDiscount(
	originalPrice value_objects.Money,
	userLevel string,
) (value_objects.Money, error) {
	var discountRate int64

	switch userLevel {
	case "VIP":
		discountRate = 20 // 8 折
	case "PREMIUM":
		discountRate = 10 // 9 折
	default:
		discountRate = 0 // 无折扣
	}

	discountAmount := originalPrice.Amount() * discountRate / 100
	return value_objects.NewMoney(
		originalPrice.Amount()-discountAmount,
		originalPrice.Currency(),
	)
}
```

### 5. 领域事件（Domain Event）

```go
// domain/events/order_events.go
package events

import "time"

// DomainEvent 领域事件接口
type DomainEvent interface {
	OccurredAt() time.Time
}

// OrderPlaced 订单已下单事件
type OrderPlaced struct {
	orderID    string
	userID     string
	occurredAt time.Time
}

// NewOrderPlaced 创建订单已下单事件
func NewOrderPlaced(orderID, userID string) OrderPlaced {
	return OrderPlaced{
		orderID:    orderID,
		userID:     userID,
		occurredAt: time.Now(),
	}
}

// OrderID 获取订单 ID
func (e OrderPlaced) OrderID() string {
	return e.orderID
}

// UserID 获取用户 ID
func (e OrderPlaced) UserID() string {
	return e.userID
}

// OccurredAt 获取发生时间
func (e OrderPlaced) OccurredAt() time.Time {
	return e.occurredAt
}

// OrderPaid 订单已支付事件
type OrderPaid struct {
	orderID    string
	occurredAt time.Time
}

// NewOrderPaid 创建订单已支付事件
func NewOrderPaid(orderID string) OrderPaid {
	return OrderPaid{
		orderID:    orderID,
		occurredAt: time.Now(),
	}
}

// OrderID 获取订单 ID
func (e OrderPaid) OrderID() string {
	return e.orderID
}

// OccurredAt 获取发生时间
func (e OrderPaid) OccurredAt() time.Time {
	return e.occurredAt
}
```

### 6. 仓储（Repository）

仓储是**聚合持久化的接口**，定义在领域层，实现在基础设施层。

```go
// domain/repositories/order_repository.go
package repositories

import (
	"context"
	"myapp/domain/aggregates"
)

// OrderRepository 订单仓储接口
type OrderRepository interface {
	// Save 保存订单（聚合根）
	Save(ctx context.Context, order *aggregates.Order) error

	// FindByID 根据 ID 查找订单
	FindByID(ctx context.Context, id string) (*aggregates.Order, error)

	// FindByUserID 根据用户 ID 查找订单列表
	FindByUserID(ctx context.Context, userID string) ([]*aggregates.Order, error)

	// Update 更新订单
	Update(ctx context.Context, order *aggregates.Order) error

	// Delete 删除订单
	Delete(ctx context.Context, id string) error
}
```

### 7. 应用服务（Application Service）

应用服务编排用例流程，调用领域对象和仓储。

```go
// application/services/order_service.go
package services

import (
	"context"
	"errors"

	"github.com/google/uuid"
	"myapp/domain/aggregates"
	"myapp/domain/events"
	"myapp/domain/repositories"
	"myapp/domain/value_objects"
)

// CreateOrderRequest 创建订单请求
type CreateOrderRequest struct {
	UserID string
	Items  []struct {
		ProductID string
		Quantity  int64
		Price     int64
		Currency  string
	}
}

// OrderService 订单应用服务
type OrderService struct {
	orderRepo repositories.OrderRepository
	eventBus  EventBus
}

// NewOrderService 创建订单服务
func NewOrderService(
	orderRepo repositories.OrderRepository,
	eventBus EventBus,
) *OrderService {
	return &OrderService{
		orderRepo: orderRepo,
		eventBus:  eventBus,
	}
}

// CreateOrder 创建订单
func (s *OrderService) CreateOrder(ctx context.Context, req CreateOrderRequest) (string, error) {
	// 1. 构建订单项
	var items []aggregates.OrderItem
	for _, item := range req.Items {
		money, err := value_objects.NewMoney(item.Price, item.Currency)
		if err != nil {
			return "", err
		}

		orderItem, err := aggregates.NewOrderItem(item.ProductID, item.Quantity, money)
		if err != nil {
			return "", err
		}

		items = append(items, orderItem)
	}

	// 2. 创建订单聚合
	orderID := uuid.New().String()
	order, err := aggregates.NewOrder(orderID, req.UserID, items)
	if err != nil {
		return "", err
	}

	// 3. 保存订单
	if err := s.orderRepo.Save(ctx, order); err != nil {
		return "", err
	}

	// 4. 发布领域事件
	event := events.NewOrderPlaced(order.ID(), order.UserID())
	s.eventBus.Publish(event)

	return order.ID(), nil
}

// PayOrder 支付订单
func (s *OrderService) PayOrder(ctx context.Context, orderID string) error {
	// 1. 加载聚合
	order, err := s.orderRepo.FindByID(ctx, orderID)
	if err != nil {
		return err
	}
	if order == nil {
		return errors.New("订单不存在")
	}

	// 2. 执行业务逻辑
	if err := order.Pay(); err != nil {
		return err
	}

	// 3. 保存聚合
	if err := s.orderRepo.Update(ctx, order); err != nil {
		return err
	}

	// 4. 发布领域事件
	event := events.NewOrderPaid(order.ID())
	s.eventBus.Publish(event)

	return nil
}

// EventBus 事件总线接口
type EventBus interface {
	Publish(event events.DomainEvent)
}
```

---

## 目录结构

```
myapp/
├── domain/                      # 领域层（核心）
│   ├── entities/                # 实体
│   │   └── user.go
│   ├── value_objects/           # 值对象
│   │   ├── email.go
│   │   └── money.go
│   ├── aggregates/              # 聚合
│   │   └── order.go
│   ├── services/                # 领域服务
│   │   └── pricing_service.go
│   ├── repositories/            # 仓储接口
│   │   └── order_repository.go
│   └── events/                  # 领域事件
│       └── order_events.go
├── application/                 # 应用层
│   └── services/
│       └── order_service.go
├── infrastructure/              # 基础设施层
│   ├── persistence/
│   │   └── postgres_order_repository.go
│   └── messaging/
│       └── event_bus.go
└── interfaces/                  # 接口层
    └── http/
        └── order_handler.go
```

---

## DDD 最佳实践

### 1. 聚合设计原则

```go
// ✅ 正确：订单聚合包含订单项
type Order struct {
	id     string
	items  []OrderItem  // 内部管理
	status OrderStatus
}

// ❌ 错误：订单项单独管理（破坏一致性）
type Order struct {
	id     string
	status OrderStatus
}

type OrderItem struct {
	orderID string  // 外部引用
}
```

### 2. 值对象不可变

```go
// ✅ 正确：操作返回新对象
func (m Money) Add(other Money) (Money, error) {
	return Money{amount: m.amount + other.amount}, nil
}

// ❌ 错误：修改自身
func (m *Money) Add(other Money) {
	m.amount += other.amount
}
```

### 3. 业务规则在领域层

```go
// ✅ 正确：业务规则在聚合中
func (o *Order) Pay() error {
	if o.status != OrderStatusPending {
		return errors.New("只有待支付订单可以支付")
	}
	o.status = OrderStatusPaid
	return nil
}

// ❌ 错误：业务规则在应用服务中
func (s *OrderService) PayOrder(orderID string) error {
	order := s.repo.FindByID(orderID)
	if order.Status != "pending" {  // 业务规则泄漏
		return errors.New("...")
	}
	order.Status = "paid"
	s.repo.Update(order)
}
```

---

## 何时使用 DDD

### 适合场景
- ✅ 复杂业务领域
- ✅ 业务规则频繁变化
- ✅ 需要与业务专家深度合作
- ✅ 长期维护的项目
- ✅ 微服务架构

### 不适合场景
- ❌ 简单 CRUD 应用
- ❌ 技术驱动的项目（非业务驱动）
- ❌ 业务规则极少
- ❌ 快速原型开发

---

## 总结

DDD 通过**统一语言**和**领域建模**将复杂业务映射为软件模型，提高了代码的可维护性和业务表达力。适合复杂业务场景，但需要投入时间进行领域建模。
