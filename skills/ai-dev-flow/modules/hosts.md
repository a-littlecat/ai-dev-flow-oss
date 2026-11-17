# 宿主相关的做法

各宿主（T3、Claude Code 桌面和命令行、Codex）的具体写法。用到哪个读哪段；没有这个宿主或工具的，跳过，不算失败。

## T3

- **派活**：`delegate_task`。`target` 写 `providerInstanceId`（如 `codex`、`antigravity`、`claudeAgent`）、模型和强度（`options`：Codex 是 `reasoningEffort`，Gemini 是 `thinking_level`，Claude 是 `effort`，都显式写）；写代码的每项 `isolation: "worktree"`。每个线程第一次派之前调一次 `orchestrator_capabilities`，要的模型不在里面就告诉用户，不自己换。派完等完成通知，不轮询。任务说明照 `orchestrate.md` 第 2 节自己写全（没有 `dispatch.ps1` 的固定尾部）。
- **找别的项目的会话**：`t3_thread_list`（按项目）认出线程，`t3_thread_send` 发消息；消息第一行写"来自 <项目> 会话"。

## Claude Code

- **后台子 agent**：Agent 工具，`isolation: "worktree"`，后台运行。worktree 默认从仓库默认分支开出（设置 `worktree.baseRef`）。
- **会话间发消息**：`ListAgents` 列出会话，`SendMessage` 发。`/next` 开的会话名字多半一样，先对上是哪个项目（看对方发来的消息，或 T3 线程列表），分不清就问用户，不猜着发。
- **开项目会话**：`pwsh -NoProfile -File <skill>/scripts/launch.ps1 -Project '<清单里的名字>' -Config <总览>/projects.json -Max <上限>`，在 PowerShell 里运行。开的是命令行后台会话（`claude --bg`），用命令行登录的账号；退出码 3 是已有会话（发消息），4 是到了上限，5 是清单要求开在桌面应用里。第一次用前：用户级设置加 `"worktree": { "bgIsolation": "none" }`；每个项目文件夹在命令行里信任过一次。
- **会话标题**：桌面应用里可以用 `set_session_title` 把 `/next` 的标题改成 `<项目> #<编号> <短语>`。只改含 `next` 或"队列"的自动标题，用户自己起的不碰。
- **通知 hook**：用户级 `Notification` hook 接 `notify.ps1 -Hook`，等权限、等回答时弹通知。改 hook 是安全设置，用户同意才改。

## Codex

- 用它原生的子 agent，每项一个 worktree。
- 审查（单向门档请 Codex 时）：`Get-Content -Raw -Encoding UTF8 <brief.md> | codex exec --ephemeral --sandbox workspace-write -m <model> -c model_reasoning_effort=high -C <tmp> -o <out.md> -`。

## 外部 CLI agent（dispatch.ps1）

项目配了 `scripts/dispatch.json` 的，用 `<skill>/scripts/dispatch.ps1` 派写或审（`-Agent`、`-Model`、`-Review <分支>`、`-Continue <分支>`、`-Wait`、`-List`、`-CleanReviews`）。配置格式和退出码见 `scripts/README.md` 和脚本开头的注释。`-Wait` 放进后台任务，等它的完成通知。
