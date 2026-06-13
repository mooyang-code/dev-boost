# Go 架构参考文档

本目录包含 Go 语言架构设计的详细参考文档。

## 文档列表

### 1. [架构模式对比](./architecture.md)
对比不同架构模式的优劣和适用场景：
- 简单分层架构
- Clean Architecture（整洁架构）
- Hexagonal Architecture（六边形架构）
- DDD（领域驱动设计）
- Go Kit 风格
- 架构选择建议

### 2. [Clean Architecture](./clean-architecture.md)
Uncle Bob 的整洁架构在 Go 中的完整实现：
- 四层架构详解
- 依赖规则
- 完整代码示例
- 最佳实践和常见陷阱

### 3. [Hexagonal Architecture](./hexagonal-architecture.md)
六边形架构（端口和适配器）详解：
- 端口和适配器概念
- 输入/输出端口设计
- 完整 Go 实现
- 与 Clean Architecture 的对比

### 4. [DDD 模式](./ddd-patterns.md)
领域驱动设计的战术和战略模式：
- 实体、值对象、聚合
- 领域服务和领域事件
- 仓储模式
- DDD 最佳实践

### 5. [设计模式](./patterns.md)
Go 语言中常用的设计模式：
- 创建型模式（工厂、建造者、单例）
- 结构型模式（适配器、装饰器、代理）
- 行为型模式（策略、观察者、责任链）
- Go 特有模式（Option、Context、并发模式）

### 6. [技术栈选型](./tech-stack.md)
Go 生态技术栈对比和推荐：
- HTTP 框架（Gin、Echo、Chi）
- ORM/数据库（GORM、sqlx、ent）
- 配置管理（Viper、envconfig）
- 日志库（zap、logrus、slog）
- 依赖注入（Wire、fx）
- 测试库（testify、mocker）

## 使用建议

### 新手入门
1. 先阅读 [架构模式对比](./architecture.md) 了解全局
2. 从 [简单分层架构](./architecture.md#1-简单分层架构layered-architecture) 开始实践
3. 学习 [设计模式](./patterns.md) 中的基础模式
4. 参考 [技术栈选型](./tech-stack.md) 选择合适的工具

### 进阶学习
1. 阅读 [Hexagonal Architecture](./hexagonal-architecture.md)
2. 实践端口和适配器模式
3. 学习 [DDD 模式](./ddd-patterns.md) 的基础概念
4. 应用到实际项目中

### 高级应用
1. 深入学习 [Clean Architecture](./clean-architecture.md)
2. 掌握 [DDD 模式](./ddd-patterns.md) 的完整体系
3. 根据项目需求混合使用不同架构
4. 建立团队架构标准

## 快速导航

### 按场景选择

| 场景 | 推荐阅读 |
|------|---------|
| 小型 CRUD 应用 | [简单分层架构](./architecture.md#1-简单分层架构) |
| 中型 API 服务 | [Hexagonal Architecture](./hexagonal-architecture.md) |
| 大型企业应用 | [Clean Architecture](./clean-architecture.md) |
| 复杂业务领域 | [DDD 模式](./ddd-patterns.md) |
| 微服务架构 | [Hexagonal](./hexagonal-architecture.md) + [技术栈](./tech-stack.md) |
| 技术选型 | [技术栈选型](./tech-stack.md) |

### 按主题选择

| 主题 | 推荐阅读 |
|------|---------|
| 架构设计 | [架构模式对比](./architecture.md) |
| 依赖管理 | [Clean Architecture](./clean-architecture.md)、[Hexagonal](./hexagonal-architecture.md) |
| 业务建模 | [DDD 模式](./ddd-patterns.md) |
| 代码复用 | [设计模式](./patterns.md) |
| 工具选择 | [技术栈选型](./tech-stack.md) |

## 相关资源

### 返回主文档
- [../SKILL.md](../SKILL.md) - Go 架构设计主文档

### 模板代码
- [../templates/](../templates/) - 项目模板（待完善）

### 外部资源
- [Clean Architecture - Robert C. Martin](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
- [Hexagonal Architecture - Alistair Cockburn](https://alistair.cockburn.us/hexagonal-architecture/)
- [Domain-Driven Design - Eric Evans](https://www.domainlanguage.com/ddd/)
- [Go Project Layout](https://github.com/golang-standards/project-layout)
