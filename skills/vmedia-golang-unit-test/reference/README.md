# Go 单元测试参考文档

本目录包含 Go 单元测试的详细参考文档。

## 文档列表

### 1. [覆盖率达标检查](./coverage-check.md)
覆盖率自动补测机制:
- 覆盖率目标分层（Entity 90%, Logic 80%, Protocol 70%）
- 自动补测流程和策略
- 补测用例生成模板
- 补测限制和人工介入条件

### 2. [Mocker 使用指南](./mocker-guide.md)
GOOM Mocker 库的完整使用指南:
- 基本用法
- 接口 Mock
- 结构体 Mock
- 函数 Mock
- 全局变量 Mock
- 高级特性(When、Returns、Origin)
- 调试和问题排查

### 3. [第三方库 Mock](./third-party-mock.md)
常见第三方库的推荐 Mock 方案:
- 数据库(database/sql, GORM) - go-sqlmock
- Redis - miniredis
- HTTP 客户端 - httptest
- 时间相关 - 依赖注入

### 4. [最佳实践](./best-practices.md)
测试编写的最佳实践和常见陷阱:
- 测试设计原则
- 函数长度控制策略
- 测试数据管理
- Mock 使用原则
- 常见陷阱和解决方案

### 5. [代码风格规范](./code-style.md)
完整的代码风格要求:
- 格式化和换行
- Import 规范
- 错误处理规范
- 命名规范
- 控制结构规范
- 魔法数字处理

### 6. [AI 生成指导](./ai-guide.md)
AI 辅助测试生成的指导原则:
- 测试生成策略
- 安全的生成流程
- 质量控制要点
- Mock 使用建议

## 快速导航

### 按问题查找

| 问题 | 参考文档 |
|------|---------|
| 如何提升覆盖率? | [覆盖率达标检查](./coverage-check.md) |
| 如何自动补测? | [覆盖率达标检查](./coverage-check.md) |
| 如何 Mock 接口? | [Mocker 使用指南](./mocker-guide.md) |
| 如何 Mock 数据库? | [第三方库 Mock](./third-party-mock.md) |
| 测试函数太长怎么办? | [最佳实践](./best-practices.md) |
| Import 如何分组? | [代码风格规范](./code-style.md) |
| AI 如何生成测试? | [AI 生成指导](./ai-guide.md) |

### 按技术栈查找

| 技术 | 参考文档 |
|------|---------|
| GORM | [第三方库 Mock](./third-party-mock.md) - 使用 sqlmock |
| Redis | [第三方库 Mock](./third-party-mock.md) - 使用 miniredis |
| HTTP | [第三方库 Mock](./third-party-mock.md) - 使用 httptest |
| Mocker | [Mocker 使用指南](./mocker-guide.md) |
| Testify | [最佳实践](./best-practices.md) |

## 使用建议

### 新手阅读顺序

1. 先阅读 [../SKILL.md](../SKILL.md) 了解基础规范
2. 查看 [Mocker 使用指南](./mocker-guide.md) 学习 Mock
3. 阅读 [第三方库 Mock](./third-party-mock.md) 了解正确的 Mock 方式
4. 参考 [最佳实践](./best-practices.md) 提升测试质量
5. 查阅 [代码风格规范](./code-style.md) 规范代码

### 进阶阅读

- 重点学习 [最佳实践](./best-practices.md) 中的测试设计原则
- 深入理解 [Mocker 使用指南](./mocker-guide.md) 中的高级特性
- 掌握 [代码风格规范](./code-style.md) 中的所有规范

### AI 用户

如果你是使用 AI 辅助生成测试,务必阅读:
- [AI 生成指导](./ai-guide.md) - 了解安全的生成流程
- [代码风格规范](./code-style.md) - 确保生成的代码符合规范
- [最佳实践](./best-practices.md) - 提升生成质量

---

**返回 [主文档](../SKILL.md)** | **查看 [示例代码](../examples/)**
