# C3 — Token / 凭证处理

## 标准

Token 是 skill 翻车的高频原因，必须满足：

1. **不放占位串**：SKILL 示例里出现 `<api-token>` 这种占位，Agent 真的会原样复制粘贴。
2. **不依赖 Agent sandbox 环境变量**：`$API_TOKEN` 在不少 Agent 沙箱里**不会**继承用户 shell；必须文档明示「**优先用** `find_dm.sh` 的自动加载，**或** 用真实 token 字符串」。
3. **失效特征写明**：401 / 403 时怎么排查、token 真实长度大致多少、含什么特殊字符（如 `.` 段分隔）。
4. **Token 不写进日志/不打印**：`find_dm.sh` 自动加载成功时 stderr 输出 mask 后版本（如 `tai_pat_7Mjn****aKH4`）即可。

## 真实踩过的坑（必看）

### 坑 1 — `$API_TOKEN` 在 sandbox 取不到

Agent 在某些产品的沙箱中执行 shell，**不继承**用户 zshrc/bashrc。结果：

```bash
"$DM" --token "$API_TOKEN" --gateway ... project list
# → 401 Unauthorized: PAT Token 无效或已过期  （$API_TOKEN 展开为空）
```

修复方案：`find_dm.sh` 自动从 `~/.zshrc` / `~/.bashrc` / `~/.profile` / `~/.bash_profile` / `~/.zprofile` 抓取 `api_token_...` 并 export 到当前 shell；找不到时打印明确提示。**SKILL 里告诉 Agent**：执行命令时要 `source find_dm.sh`，让脚本帮你把 token 注进环境。

### 坑 2 — 正则把 token 截短

`find_dm.sh` 早期用 `grep -oE 'tai_pat_[A-Za-z0-9_-]{30,}'` 抓 token，**少了 `.`**。真实 token 含 `.` 段分隔（约 110 字符），正则在第一个 `.` 处截断 → 截出来 51 字符 → CLI 401。

修复正则：

```bash
grep -oE 'tai_pat_[A-Za-z0-9_.-]{30,}'
```

并加长度健全检查：

```bash
if [ -n "${API_TOKEN:-}" ] && [ ${#API_TOKEN} -lt 70 ]; then
  echo "⚠️  API_TOKEN 长度异常 (${#API_TOKEN})；可能被截断或不是完整 PAT" >&2
fi
```

### 坑 3 — SKILL 里写"占位串" Agent 真的复制

SKILL 示例：

```bash
"$DM" --token "<api-token>" --gateway ...   # ❌ Agent 真的把这条命令原样发了
```

→ 401。

修复：所有示例统一用 `--token "$API_TOKEN"`（配合 §坑 1 的 source），或在文档明确说明「**把这里的字符串替换成你拿到的真实 token，不要原样使用**」。

## 检查项

- [ ] SKILL 里 token 示例**绝对不**写 `xxxxx` / `yyyyy` / `<your-token>` 这类占位裸串。
- [ ] 配套脚本（如 `find_dm.sh`）实现 token 自动加载，正则**包含** `.` 字符（`[A-Za-z0-9_.-]`）。
- [ ] Token 长度做 sanity check，过短给出明确警告。
- [ ] SKILL 写明 401 排查路径：`echo ${#API_TOKEN}` 看长度、检查正则、检查是否在同一条命令里 source。
- [ ] 自动加载 + 实际使用 token，**必须在同一条命令**里：`unset ... && source ... && "$DM" --token "$API_TOKEN" ...`。
- [ ] Token 不出现在任何持久化日志/截图/示例输出里（mask 后再贴）。

## 验证脚本

```bash
# 1. 人为 unset，看 find_dm.sh 能否自救
unset API_TOKEN
unset SKILL_DIR DM
source "<SKILL_DIR>/find_dm.sh"
echo "len=${#API_TOKEN}"   # 期望 ~110

# 2. 长度异常警告
export API_TOKEN="api_token_too_short"
unset SKILL_DIR DM
source "<SKILL_DIR>/find_dm.sh"   # 期望 stderr 输出 ⚠️

# 3. 命令真跑通
unset SKILL_DIR DM && source "<SKILL_DIR>/find_dm.sh" \
  && "$DM" --token "$API_TOKEN" --gateway <url> <list-cmd>
```

## SKILL 文案建议

在 SKILL 顶部「配置 Token」一节，给出**唯一推荐写法**：

````markdown
## 配置 Token

CLI 用 `--token` 接收 PAT。`find_dm.sh` 会自动从 `~/.zshrc` / `~/.bashrc` 等
shell 配置文件里抓取你的 `API_TOKEN` 并 export 到当前 shell。

**唯一推荐写法**：每条 datamind 命令都带 source 前缀：

```bash
unset SKILL_DIR DM && source "<SKILL_DIR>/find_dm.sh" \
  && "$DM" --token "$API_TOKEN" --gateway <url> <subcommand>
```

如果 source 后报 token 未找到 / 401，请先：

1. `echo ${#API_TOKEN}` 看长度（正常 ~110）
2. 检查 `~/.zshrc` 里 `export API_TOKEN=api_token_...` 是否完整
3. 还不行联系 SRE 重发 PAT
````
