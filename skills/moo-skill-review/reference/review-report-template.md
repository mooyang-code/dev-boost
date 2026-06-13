# Review 报告模板

> 一份合格的 skill review 报告应让作者**当天就能 patch**。短、准、可执行。

---

## 模板

````markdown
# moo-<skill-name> Review 报告 — <YYYY-MM-DD>

## 总评
<一句话：✅ 可上线 / ⚠️ 有改进项可上线 / ❌ 阻塞，必改后才能上>

## 必改项（阻塞）

| # | 类目 | 文件:行 | 问题 | 修复建议 |
|---|------|---------|------|---------|
| 1 | C2 CLI契约 | SKILL.md:42 | 命令缺 `source find_dm.sh` 前缀，跨 Shell 调用 `$DM` 为空 | 改为 `unset SKILL_DIR DM && source "<SKILL_DIR>/find_dm.sh" && "$DM" ...` |
| 2 | C3 Token | SKILL.md:88 | 示例用 `--token "<api-token>"` 占位串，Agent 会原样发 → 401 | 改为 `--token "$API_TOKEN"`（同条命令内 source） |
| 3 | C5 输出契约 | SKILL.md:120 | 残留 `--output json`，CLI 已删该 flag → `unknown flag` | 全文 rg 删除 `--output (json|table)` |

## 建议项（不阻塞）

| # | 类目 | 文件:行 | 建议 |
|---|------|---------|------|
| 1 | C6 schema | export.go:* | 给 `--filter` 加 `RegisterFlagJSONSchema` + `RegisterFlagRemarks`，Agent 不再猜 op |
| 2 | C4 轮询 | references/operations-guide.md | 加官方循环模板替代 Agent 自创的 for + python 解析 |

## 实跑回归（patch 后请按此顺序跑）

```bash
# 1. 同步到安装目录
INSTALL_DIR="<你的 Agent 安装目录>"
cp skills/<skill>/SKILL.md "$INSTALL_DIR/"
cp -r skills/<skill>/references "$INSTALL_DIR/"
cp skills/<skill>/find_dm.sh "$INSTALL_DIR/"
cp dist/moo-dm-* "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/"moo-dm-*

# 2. 验证 source + token 自加载
unset SKILL_DIR DM && source "$INSTALL_DIR/find_dm.sh" && "$DM" --version

# 3. 验证只读命令
unset SKILL_DIR DM && source "$INSTALL_DIR/find_dm.sh" \
  && "$DM" --token "$API_TOKEN" --gateway <url> project list | jq '.items|length'

# 4. 故意拼错参数，确认错误清晰
"$DM" export status --task fake-id 2>&1 | head -5; echo "exit=$?"
```

三条全绿 → 提 PR；任一不绿 → 回到对应 checklist。

## 关联 PR / Issue

- PR: <link>
- Issue: #<id>
````

---

## 使用提示

1. **必改项**和**建议项**严格区分；否则作者会把"建议"当"必改"，反而拖延上线。
2. 每条问题必须**带文件:行号**，并指明对应的 checklist 编号（c1~c7）。
3. **修复建议**直接给可粘贴 diff 或新代码片段；不要只说"应该改"。
4. **回归命令**写出来，让作者一次跑通即关闭 review 循环；不写则会出现"我改了但你说还有问题，到底跑没跑过"的扯皮。
5. 报告整体长度控制在 **2 屏内**，超出说明你在 review 时混入了与 skill 无关的代码风格/架构问题（应另开 issue）。
