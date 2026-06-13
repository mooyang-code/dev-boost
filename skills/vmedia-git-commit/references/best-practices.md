# Commit / PR 最佳实践

## Commit 规则

1. 多次提交，边写边 commit，不要攒到最后；
2. 每个 commit 对应一个逻辑模块，建议 300~400 行以内；
3. PR 前整理：合并零碎 commit、拆分过大 commit，保证一个 commit 只做一件事；
4. 若 commit 最终会合并主干，message 必须规范，并建议关联 GitHub Issue 或 PR；
5. body 需包含：a) 本次变更做了什么；b) 如何自测。

## PR 规则

1. 一个 PR 控制在 3 个 commit 以内；
2. 一个 commit 只描述一样变更，一个 PR 只做一件事；
3. PR 描述包含总体信息，commit 包含具体信息；
4. 推到 main/master 的代码必须能 work，不影响线上。

### 并行开发分支策略

基于分支 A 拉分支 B 继续开发，PR 时 B→A，Review 只展示模块 B 的 diff：

```
main
 └── branch-A  (模块A，提 PR)
       └── branch-B  (模块B，提 PR: B→A)
```

### 功能开关

功能依赖其他模块未就绪时，合并主干后先关闭项目配置中的 feature flag，条件具备后再开启。

## 修改已提交的 commit message

```bash
git rebase -i HEAD~N
# 将目标 commit 前缀改为 reword，保存后修改 message
```
