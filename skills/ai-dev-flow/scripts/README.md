# 脚本

都用 `pwsh -NoProfile -File <skill>/scripts/<脚本>` 运行（`<skill>` 是 `$env:AI_DEV_FLOW`，默认 `~/.agents/skills/ai-dev-flow`）。参数和细节写在各脚本开头的注释里。

| 脚本 | 用途 |
|---|---|
| `dispatch.ps1` | 把一项交给外部 CLI agent（Codex、`claude -p` 等）写、审或修，项目配置在 `scripts/dispatch.json`（下面） |
| `models.ps1` | 按角色查模型设置表该派谁，审查自动跳过写方同一家（`modules/orchestrate.md` 第 3 节） |
| `status.ps1` | 按总览 `projects.json` 收各项目的状态，只读 |
| `launch.ps1` | 在一个项目里开命令行后台会话（`claude --bg`，默认 `/next`），按清单决定新开、发消息还是开在桌面 |
| `notify.ps1` | 系统通知；`barkLevels` 里的级别推到手机；`-Hook` 接 Claude Code 的 Notification hook |
| `watch.ps1` | 给计划任务每 15 分钟跑，只拉起 `trunk-check.ps1` |
| `trunk-check.ps1` | 合并后在本机后台跑全量：攒到机器空闲跑最新那棵树，只有超时不记红，真红写 `.agents/trunk-red.json`（`modules/harness.md` 第 2 节） |
| `verify-ledger.ps1` | 快检记账：同一棵树、同一条命令已绿就不再跑 |
| `check-md.ps1` | 文档格式检查：`.md` 里的控制字符、被拆断的表格行；放进各项目快检 |
| `archive-requests.ps1` | 把 `docs/requests.md` 里处理完的小节移到 `docs/requests-done.md` |
| `cleanup.ps1` | 合并后删已合进主干、没有未提交改动的 worktree 和分支 |

## dispatch.json

项目里的 `scripts/dispatch.json`（入库）：

```json
{
  "verify": "pwsh -NoProfile -File scripts/verify.ps1",
  "verifyReview": "pwsh -NoProfile -File scripts/verify.ps1 -Base {base}",
  "trunkVerify": true,
  "readFirst": ["AGENTS.md"],
  "protected": ["docs/queue.md"],
  "rules": ["真实数据只读，只用副本"],
  "docsOnly": ["*.md"],
  "agents": {
    "codex": { "model": "<模型名>",
               "build": "Get-Content -Raw -Encoding UTF8 {prompt} | codex exec --profile <完全访问的 profile> {model} -C {wt} -o {final} - *> {log}",
               "review": "Get-Content -Raw -Encoding UTF8 {prompt} | codex exec --sandbox workspace-write {model} -C {wt} -o {final} - *> {log}" },
    "claude": { "vendor": "claude", "model": "<模型名>",
                "build": "Get-Content -Raw -Encoding UTF8 {prompt} | claude -p {model} --permission-mode bypassPermissions 2> {log} | Set-Content -LiteralPath {final} -Encoding utf8NoBOM" }
  }
}
```

- `verify` 必填；`readFirst`、`protected`、`rules` 写进每份任务说明；`trunkVerify: true` 表示项目开了合并后全量，执行方和审查方只跑对照表选出的测试；`sparse` 填了做稀疏检出（`-Full` 关掉）；`minFreeMemoryMB` 可用内存不够时不派（退出 6）；`retry400Seconds` 接口 400 时的重试间隔。
- `{model}` 换成 `--model '<模型>'`（参数名不同写 `modelFlag`），`-Model` 优先于配置。`vendor: "claude"` 的在后台进程里去掉继承来的 `CLAUDE*`、`ANTHROPIC*` 环境变量，用命令行登录的账号。没写 `review` 的审查也用 `build` 的权限，完全访问的要另写一条收紧的 `review`。
- 退出码：4 写代码的一轮没留下新提交或有未提交改动；5 没写出最终回复；6 内存不够；127 agent 命令找不到。先看 `.agents/runs/<运行名>/final.md` 再决定，不直接派审查。
- 项目里放一个几行的 `scripts/dispatch.ps1` 转调本脚本，`AGENTS.md` 写这个入口：
  ```powershell
  $skill = if ($env:AI_DEV_FLOW) { $env:AI_DEV_FLOW } else { Join-Path $HOME '.agents/skills/ai-dev-flow' }
  & (Join-Path $skill 'scripts/dispatch.ps1') @args -Config (Join-Path $PSScriptRoot 'dispatch.json')
  exit $LASTEXITCODE
  ```
