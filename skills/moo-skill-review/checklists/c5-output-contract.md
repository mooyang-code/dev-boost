# C5 — stdout / stderr 契约

## 标准

CLI 的输出契约必须在 SKILL 里**明文写一段**，让 Agent 知道：

1. 业务结果**永远在 stdout**，且为单一格式（推荐 JSON，且**不可配置**）。
2. 进度 / 提示 / 警告 / 加载日志一律在 stderr。
3. exit code 语义清晰：0 = 业务成功；非 0 = 业务/系统错误。

## 为什么要明确写

Agent 决策的核心信息源就是这三件套（stdout / stderr / exit）。任何含糊都会变成"Agent 自我怀疑 → 多查 / 重试 / 回退"。

实际踩坑：

- CLI 删了 `--output table`、固定 JSON 后没在 SKILL 显式写「stdout 永远 JSON」→ Agent 仍主动加 `--output json`，遇到 `unknown flag` 又重试。
- find_cli.sh 自动 source 加载 token 时把提示写 stderr，Agent 用 `2>/dev/null` 吞掉所有 stderr，于是出错时**完全不知道**为什么。

## 检查项

- [ ] SKILL 顶部有「**输出契约**」一节，3 行讲清 stdout/stderr/exit。
- [ ] CLI 真实行为符合契约：`<cli> <readonly-cmd>` 输出能被 `jq` 直接解析；不混入任何非 JSON 行。
- [ ] **stderr 不污染 stdout**：跑 `<cmd> 2>/dev/null | jq .` 必须能正常解析（用这条做 lint）。
- [ ] **exit code** 至少区分：0=成功 / 2=用法错误 / 4=权限/认证 / 1 或具体语义码=业务失败。详情让作者参考 `moo-golang-cli-design`。
- [ ] **过期 flag 全清**：跑 `rg -nE '\-\-(output|format)\s+(json|table|csv)' skills/<your-skill>/` 排查，比对真实 CLI flag。
- [ ] **告诉 Agent 别用 `2>/dev/null`** 吞 stderr：写在 SKILL 反模式里。

## SKILL 文案建议

````markdown
## 输出契约（必读）

| 通道 | 内容 | Agent 怎么用 |
|-----|------|-------------|
| stdout | 业务结果，**始终是 JSON**，可直接 `\| jq .` | 解析、传递给下一步 |
| stderr | 加载提示 / 警告 / 错误详情 | 出错排查；**不要** `2>/dev/null` 吞掉 |
| exit | 0=成功；2=用法错；4=认证错；其它=业务失败 | 决定是否重试、是否升级失败 |

### 反模式

- ❌ `cmd 2>/dev/null | python3 -c json.load` —— stderr 信息丢失，stdin 空时抛错
- ❌ 自加 `--output json` —— CLI 已强制 JSON，加这个会 `unknown flag`
- ❌ 用 `--output <file>` 当文件输出 —— 不存在；要写文件就 stdout 重定向 `> out.json`
````

## review 时一行 lint

```bash
# 任意一条只读命令的 stdout 必须能直接 jq
unset SKILL_DIR CLI_BIN && source "<SKILL_DIR>/find_cli.sh" \
  && "$CLI_BIN" --token "$API_TOKEN" --gateway <url> <list-cmd> | jq -e . >/dev/null \
  && echo "stdout=clean JSON OK" || echo "❌ stdout 被污染"
```
