---
name: vmedia-git-commit
description: Use when writing git commit messages for GitHub-hosted vmedia projects. Covers Conventional Commit type prefixes, GitHub issue and pull request references, commit granularity rules, PR strategy, and branch management. Triggers when generating, reviewing, or fixing commit messages.
---

# vmedia Git Commit 规范

## Commit Message 格式

```
<type>(<scope>): <subject> (#ISSUE)

<body>（可选）
```

**规则：**
- `type` 后跟 `: `（冒号 + 空格），全小写
- `scope` 可选，填写影响范围（如 package 名、模块名）
- 合入主干的业务变更建议关联 GitHub Issue 或 PR，便于追踪需求、任务和缺陷
- `body` 需说明：① 本次变更做了什么；② 如何自测

## Type 速查表

| Type | 用途 |
|------|------|
| `feat` | 新功能 |
| `fix` | 修复 bug |
| `docs` | 文档变更 |
| `style` | 格式调整（不影响运行逻辑） |
| `refactor` | 重构（非新增功能，非修 bug） |
| `test` | 增加或修改测试用例 |
| `chore` | 构建/辅助工具/配置变动（不改 src/test） |

## GitHub 关联格式

```
#123              # 引用 issue 或 PR
GH-123            # 文本化引用
Closes #123       # 合并后自动关闭 issue
Fixes #123        # 合并后自动关闭 bug issue
```

## 示例

```bash
# 关联 GitHub issue
git commit -m 'feat: add transport stream support (#123)'
git commit -m 'feat(player): add subtitle render (#456)'

# 关闭 GitHub issue
git commit -m 'fix: 修复分页偏移量计算错误' -m 'Fixes #789'

# 无 issue（仅限文档、依赖或临时本地 commit）
git commit -m 'docs: 更新 README 快速开始章节'
git commit -m 'refactor: 提取 toProjectInfo 辅助函数'
git commit -m 'chore: 更新 go.mod 依赖版本'
```

## GitHub 分支保护建议

- 使用 PR 合并主干，开启 required reviews 和 status checks
- squash merge 时保留 Conventional Commit 标题
- 需要自动关闭 issue 时，在 PR 描述或 commit body 中写 `Closes #123`

## 常见错误

| 错误 | 正确 |
|------|------|
| `feat:新功能` | `feat: 新功能`（冒号后必须有空格） |
| `Feat: 新功能` | `feat: 新功能`（type 全小写） |
| `feature: 新功能` | `feat: 新功能`（使用规范缩写） |
| `fix bug` | `fix: 修复登录页跳转异常`（缺少 type 和冒号） |
| 合主干无 issue 关联 | 补充 `(#123)`、`Closes #123` 或在 PR 描述中关联 |

## Commit 粒度与 PR 策略

> 详细规则见 `references/best-practices.md`

**核心原则：**
- 每个 commit 对应一个逻辑模块，建议 300~400 行以内
- 边写边 commit，不要攒到最后
- PR 前整理：合并零碎 commit、拆分过大 commit
- **一个 PR 控制在 3 个 commit 以内，只做一件事**

## 修改已提交的 commit message

```bash
git rebase -i HEAD~N
# 将目标 commit 前缀改为 reword，保存后修改 message
```
