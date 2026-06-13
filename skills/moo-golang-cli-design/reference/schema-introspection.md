# schema 自省命令

> "Agent 不应该靠记忆/猜测知道有哪些命令、参数、枚举值。"

## 用法

```bash
<cli> schema --all                    # 整棵命令树（递归所有子命令）
<cli> schema clean create             # 单命令（放在 .commands[0]）
<cli> schema --exit-codes-only        # 仅退出码契约（无命令树）
<cli> schema                          # 仅顶层一级子命令大纲（不含 flags）
<cli> schema --include-hidden         # 含 cobra Hidden=true 的命令
```

## 输出契约

```json
{
  "cli_name": "<your-cli>",
  "description": "...",
  "global_flags": [{"name":"output","type":"string","default":"json","usage":"...","enum":["json","table"]}, ...],
  "commands": [
    {
      "path": "<your-cli> clean create",
      "use": "create [flags]",
      "short": "...",
      "long": "...",
      "flags": [
        {"name":"mode","type":"string","usage":"...","required":true,"enum":["udf","builtin"]},
        ...
      ],
      "subcommands": [...]
    }
  ],
  "exit_codes": [{"code":0,"name":"ExitOK","meaning":"..."}, ...],
  "error_types": ["generic_error","invalid_argument","not_found",...],
  "stderr_format": "NDJSON 单行结构化错误（CLIError）+ 进度日志",
  "stdout_format": "结构化数据（json / table），由 --output 控制"
}
```

## 关键设计

- **不调任何 RPC**，全部从 cobra 内存元数据生成
- 通过 cobra annotation 标注枚举值，让 Agent 直接拿到合法值（无需读 Long 描述）
- 同时输出 `exit_codes` / `error_types`，让 Agent 程序化获取退出码契约

## 实现（直接拷贝 datamind 的 schema.go）

完整源码见 `github.com/mooyang-code/xData-mini/storage/cmd/cli/schema.go`，约 280 行。
关键代码片段：

### 注册 enum 值

```go
const AnnotationEnum = "moo.dm/enum"   // 改成你 CLI 的命名空间

// RegisterEnum 给 flag 标注枚举可选值，schema 输出会带上 enum 字段。
// 调用方：
//   cleanCreateCmd.Flags().String("mode", "", "udf / builtin")
//   RegisterEnum(cleanCreateCmd, "mode", "udf", "builtin")
func RegisterEnum(cmd *cobra.Command, flagName string, values ...string) {
    f := cmd.Flags().Lookup(flagName)
    if f == nil { return }
    if f.Annotations == nil {
        f.Annotations = map[string][]string{}
    }
    f.Annotations[AnnotationEnum] = values
}
```

### schema 命令注册

```go
var schemaCmd = &cobra.Command{
    Use:   "schema [command-path...]",
    Short: "导出 CLI 命令树和参数定义（JSON 自省）",
    RunE: func(cmd *cobra.Command, args []string) error {
        all, _          := cmd.Flags().GetBool("all")
        exitOnly, _     := cmd.Flags().GetBool("exit-codes-only")
        includeHidden,_ := cmd.Flags().GetBool("include-hidden")

        if exitOnly {
            return printOutput(buildSchemaResponse(nil, false, false))
        }

        var roots []*cobra.Command
        if len(args) > 0 {
            match, _, err := rootCmd.Find(args)
            if err != nil || match == nil || match == rootCmd {
                return NewNotFoundError(
                    "未找到命令: "+strings.Join(args, " "),
                    "用 <YOUR-CLI> schema --all 查看完整命令树",
                )
            }
            roots = []*cobra.Command{match}
        } else {
            roots = visibleSubcommands(rootCmd, includeHidden)
        }
        return printOutput(buildSchemaResponse(roots, all, includeHidden))
    },
}

func init() {
    schemaCmd.Flags().Bool("all", false, "递归导出所有子命令")
    schemaCmd.Flags().Bool("exit-codes-only", false, "仅输出退出码契约")
    schemaCmd.Flags().Bool("include-hidden", false, "包含 cobra Hidden=true 的命令/参数")
    rootCmd.AddCommand(schemaCmd)
}
```

### 排除噪声命令

cobra 会自动注入 `help` / `completion` 子命令。schema 输出应该屏蔽，避免 Agent 看到一堆无业务意义的子命令。

```go
func visibleSubcommands(c *cobra.Command, includeHidden bool) []*cobra.Command {
    out := make([]*cobra.Command, 0, len(c.Commands()))
    for _, sub := range c.Commands() {
        if sub.Name() == "help" || sub.Name() == "completion" {
            continue
        }
        if !includeHidden && sub.Hidden {
            continue
        }
        out = append(out, sub)
    }
    return out
}
```

### 必填 flag 的识别

cobra 通过 `Annotations[BashCompOneRequiredFlag]` 记录必填，pflag 自身没有 Required 字段。schema 要把 `MarkFlagRequired` 的 flag 暴露为 `"required": true`：

```go
func requiredFlagSet(c *cobra.Command) map[string]bool {
    set := map[string]bool{}
    c.Flags().VisitAll(func(f *pflag.Flag) {
        if vals, ok := f.Annotations[cobra.BashCompOneRequiredFlag]; ok {
            for _, v := range vals {
                if v == "true" { set[f.Name] = true }
            }
        }
    })
    return set
}
```

## Agent 推荐用法

```bash
# 不知道某命令有哪些参数
<cli> schema clean create | jq '.commands[0].flags | map({name,type,required,enum})'

# 看哪些 flag 有 enum 限制
<cli> schema --all | jq '
  .commands[]
  | .flags[]?
  | select(.enum)
  | {cmd: .path, flag: .name, enum: .enum}
'

# 看退出码契约
<cli> schema --exit-codes-only | jq '.exit_codes'
```

## 自检

```bash
# 1) 输出结构正确
<cli> schema --all | jq 'keys'
# → ["cli_name","commands","description","error_types","exit_codes","global_flags","stderr_format","stdout_format"]

# 2) 单命令模式
<cli> schema clean create | jq '.commands[0].flags | length'
# → > 0

# 3) 不存在子命令报错
<cli> schema not-a-cmd; echo $?
# → exit=3 + stderr {"error":"not_found",...}
```
