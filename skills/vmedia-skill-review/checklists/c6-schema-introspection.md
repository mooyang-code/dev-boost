# C6 — 复杂参数 / JSON DSL 的 schema 自省

## 标准

凡是接 **JSON / DSL / 多枚举值** 的 flag（典型如 `--filter` / `--rules` / `--config` / `--mapping`），CLI 必须通过 `<cli> schema <subcmd>` 暴露：

1. **`flags[].usage`**：一句话说明
2. **`flags[].enum`**：枚举型 flag 的所有合法值
3. **`flags[].json_schema`**：完整 JSON Schema（含 `examples`）
4. **`flags[].remarks`**：自然语言备注（多段落，描述大小写、模糊匹配、option 字段值的特殊要求等）

SKILL 里**必须**写一条铁律：**拼复杂参数前先 `schema`，不要猜**。

## 真实踩过的坑

### 坑 1 — 猜操作符

Agent 凭印象写 `--filter '{"field":"title","op":"like","value":"庆余年"}'`：

```text
Error: unsupported op: like
```

实际合法 op 集合：`eq, ne, in, wildcard, prefix, gt, gte, lt, lte, range, exists, not_exists`。

### 坑 2 — option 字段传业务名

Agent 写 `value: "published"`：CLI 不报错，**但命中 0 条**——存储中 `status` 字段实际是数字 `4`。

### 坑 3 — 大小写 / 模糊匹配语义不清

Agent 不知道 `wildcard` 在 ES 路径下会去掉首尾 `*`、在 MySQL 路径下会翻译为 LIKE，于是反复试 `*关键词*` / `%关键词%` / `regex` 都失败。

## 解决方案：用 cobra annotation 注入 schema + remarks

CLI 端实现（参考 `cmd/cli/schema.go`）：

```go
const (
    AnnotationEnum       = "vmedia.dm/enum"
    AnnotationJSONSchema = "vmedia.dm/json_schema"
    AnnotationRemarks    = "vmedia.dm/remarks"
)

func RegisterFlagJSONSchema(cmd *cobra.Command, name, schema string) {
    _ = cmd.Flags().SetAnnotation(name, AnnotationJSONSchema, []string{schema})
}

func RegisterFlagRemarks(cmd *cobra.Command, name string, paragraphs ...string) {
    _ = cmd.Flags().SetAnnotation(name, AnnotationRemarks, paragraphs)
}
```

子命令 init 里：

```go
func init() {
    exportCreateCmd.Flags().String("filter", "", "Filter DSL (JSON)")
    RegisterFlagJSONSchema(exportCreateCmd, "filter", exportFilterJSONSchema)
    RegisterFlagRemarks(exportCreateCmd, "filter", exportFilterRemarks)
    RegisterEnum(exportCreateCmd, "format", "csv", "excel", "jsonl")
}
```

`schema` 命令读 annotation 输出到 `flags[].json_schema` / `flags[].remarks` / `flags[].enum`。

## 检查项

- [ ] 每个接 JSON / DSL 的 flag，schema 输出含 `json_schema`（完整 JSON Schema，含 `examples`）。
- [ ] 每个非平凡 flag 含 `remarks`（自然语言多段落，覆盖典型反例）。
- [ ] 每个枚举型 flag 含 `enum` 字段。
- [ ] `json_schema.description` 明确说 "option 字段必须先 `field-values` 拿真实 value"（或同等约束）。
- [ ] `examples` 至少 5 条，覆盖：单条件 / 多条件 AND / option 字段（用 value 不用 label）/ 列表 in / 范围 range。
- [ ] **SKILL 红线**：「拼 `--filter` / 任何复杂参数前必须先 `schema`」。
- [ ] **SKILL 给抽取片段**：`schema <subcmd> | jq '.commands[0].flags[]|select(.name=="filter")|{enum,json_schema,remarks}'`。

## 一行命令验证

```bash
"$DM" schema export create | jq '
  .commands[0].flags
  | map(select(.name=="filter"))
  | .[0]
  | {has_enum:(.enum|length>0), has_schema:(.json_schema|length>0), has_remarks:(.remarks|length>0)}
'
```

期望 `has_schema: true, has_remarks: true`（`enum` 不强制）。

## SKILL 文案建议

````markdown
### 📋 拼 --filter / 不确定任何 flag 含义前必须先 schema

```bash
unset SKILL_DIR DM && source "<SKILL_DIR>/find_dm.sh" \
  && "$DM" --token "$API_TOKEN" --gateway <url> schema export create \
  | jq '.commands[0].flags[] | select(.name=="filter") | {usage, enum, json_schema, remarks}'
```

输出包含：
- `usage`：一句话用法
- `enum`：枚举型 flag 的合法值
- `json_schema`：完整结构 + `examples`，照着 examples 改一改就能用
- `remarks`：模糊匹配 / option 字段 / 时间格式等关键备注

**禁止凭印象猜**——`like` / `contains` / `regex` 一律不支持；`option` 字段必须传真实 value（数字 4），不要传业务名（`published`）。
````
