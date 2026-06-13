# Golang 编码规范技能包

Go 编码规范与实战规则，基于腾讯 Go 编码规范和团队实战经验。

## 目录结构

```
golang-code-style/
├── SKILL.md                              # 主技能文档（实战规则）
├── README.md                             # 本文件
└── reference/                            # 详细参考文档
    ├── tencent-go-standard.md            # 腾讯 Go 编码规范（精编版）
    ├── trpc-database.md                  # tRPC 数据库组件速查手册
    └── trpc-patterns.md                  # tRPC 常用模式详解
```

## 核心规则速览

| 规则 | 要点 |
|------|------|
| Context | ctx 作为第一个参数，不放结构体，不用 context.Background() |
| 卫语句 | 提前返回，消除箭头代码，嵌套 ≤ 4 层 |
| 重试 | 使用 retry-go，不要手写重试循环 |
| 并发 | 使用 tRPC GoAndWait，不要裸用 goroutine |
| 数据库 | 使用 trpc-database/gorm，必须 WithContext(ctx) |
| 缓存 | localcache（单机）或无极（分布式） |
| 组件 | 优先使用 trpc-database 生态组件 |
| 文档 | docs/ 必须包含设计文档和用户手册，代码变更同步文档和单测 |
| CLI | 每个项目必须有 CLI 工具，输出结构化 JSON，AI Agent 友好 |

## 相关技能包

- **[golang-architecture](../golang-architecture/)** — 架构设计与项目结构
- **[golang-unit-test](../golang-unit-test/)** — 单元测试开发规范
