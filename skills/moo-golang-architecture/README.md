# Golang 架构设计技能包

Go 语言 Web 应用的架构设计指南，基于 tRPC-Go 框架。

## 目录结构

```
golang-architecture/
├── SKILL.md                        # 主技能文档（架构模式 + 快速开始）
├── README.md                       # 本文件
├── reference/                      # 详细参考文档
│   ├── architecture.md             # 架构模式深度对比
│   ├── clean-architecture.md       # Clean Architecture 完整指南
│   ├── hexagonal-architecture.md   # 六边形架构完整实现
│   ├── ddd-patterns.md             # DDD 战术和战略模式
│   ├── patterns.md                 # Go 设计模式大全
│   └── tech-stack.md               # 技术栈选型对比
└── templates/                      # 项目模板
    └── standard-project/           # 标准 tRPC-Go 项目模板
```

## 架构选择

**默认三层架构（Handler → Service → Repository），按需演进。**

详细的演进参考文档在 `reference/` 目录中，仅在复杂度明确超出三层架构时查阅。

## 相关技能包

- **[golang-code-style](../golang-code-style/)** — 编码规范与实战规则
- **[golang-unit-test](../golang-unit-test/)** — 单元测试开发规范
