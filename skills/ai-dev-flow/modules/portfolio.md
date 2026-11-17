# 多项目总览

用户同时推进几个项目时使用：问"各项目怎么样"、定跨项目的事（优先级、额度、接口、开停项目），或你在总览仓库里被打开。项目的事（方向、答复、看效果、批准）用户直接在那个项目的会话里说，总览不转述。你在总览里不写项目代码、不改项目队列、不派执行方、不合并。

## 1. 总览仓库

一个只在本地、永远不 push 的仓库，不放任何项目的代码、数据和密钥（可以写本机路径，这是唯一的例外）：

| 文件 | 内容 |
|---|---|
| `AGENTS.md` | 入口：按本模块工作，列出下面这些文件 |
| `INTENT.md` | 各项目的优先级、长期授权、额度分配、同时开着的会话上限、不做的事；用户确认 |
| `projects.json` | 项目清单（第 2 节） |
| `models.json` | 模型设置表（`orchestrate.md` 第 3 节） |
| `decisions.md` | 跨项目决定，一行一条带日期和原话 |
| `LESSONS.md` | 跨项目教训 |

## 2. 项目清单

```json
{
  "model": "<模型名>", "effort": "medium",
  "projects": [
    { "name": "应用", "path": "<本机路径>", "status": "推进中", "priority": 1, "trunk": "master",
      "dependsOn": ["引擎"], "note": "<一句话>",
      "trunkVerify": "pwsh -NoProfile -File scripts/verify.ps1", "trunkSetup": "<可选>" }
  ]
}
```

- `name`、`path`、`status`（推进中 / 维护 / 暂停）必填；`trunk` 不写用主检出当前分支；队列默认 `docs/queue.md`。
- `wake`（`new` 新开 / `message` 有会话就发消息，默认 `new`）、`session`（`cli` / `desktop`，默认 `cli`）、`model`、`effort` 给 `launch.ps1` 用（`hosts.md`）。
- `trunkVerify`、`trunkSetup` 开合并后后台全量（`harness.md` 第 2 节第 2 条）；暂停的项目不跑。清单顶层可调 `trunkIdleMinutes`（默认 30）、`trunkNightWindow`（默认 `"02:00-06:00"`）、`trunkMaxAgeHours`（默认 24）、`trunkParallel`、`trunkCpuThreshold`（默认 75）、`trunkTimeoutSeconds`（默认 1800）。项目全量的环境里有 `AI_DEV_FLOW_TRUNK=1`、`AI_DEV_FLOW_TRUNK_PARALLEL=<n>`，机器忙时另有 `AI_DEV_FLOW_MACHINE_BUSY=1`，项目的测试可据此调并行和超时。
- 信任等级不写在清单里，脚本从项目 `AGENTS.md` 读。
- 推进中的项目有上限（`INTENT.md`，默认 4）；新开、暂停、恢复都在 `decisions.md` 记一条。

## 3. 收状态和转达

- 收状态用脚本，不挨个进项目读 git log：`pwsh -NoProfile -File <skill>/scripts/status.ps1 -Config <总览>/projects.json [-All] [-Json] [-Project '<名字>']`。它列出每个项目的新提交、队列各状态、待用户和待放行的每一条、新决定、主干全量红、快检太慢、可能停滞、该清理的分支，只读。你按它的结果说，不猜会话还在不在跑。
- **跨项目的决定**写进受影响项目的 `docs/requests.md`（一个 `## <日期> <主题>` 小节：现象、决定、请求，状态"待转"），单独提交，再叫醒那个项目：清单写 `wake: message` 且有会话的发消息，没有的用 `launch.ps1` 开一个，开场只发 `/next`（具体做法见 `hosts.md`）。消息第一行写"来自 <项目> 会话"。
- 用户的批准和答复不由你转：告诉用户去哪个会话说。
- 项目往 ai-dev-flow 提请求（某条教训换项目也会犯、用户定了一条全项目都照做的规矩）：照上面的格式写进 ai-dev-flow 仓库的 `docs/requests.md`，只改这一个文件、单独提交，不写项目名和本机路径；再叫醒 ai-dev-flow 的会话（有就发一句"请求单新加了一节"，没有就等它下次开工）。

## 4. 通知

统一走 `scripts/notify.ps1 -Title <标题> -Body <正文> -Level <info|done|user|stuck>`。渠道放本机 `%APPDATA%\ai-dev-flow\notify.json`（不入库），如 `{ "bark": "https://api.day.app/<key>", "barkLevels": ["user", "stuck"], "toast": true }`：系统通知每次都弹，只有 `barkLevels` 里的级别推到手机，也就是只推要用户决定或出手的。

计划任务只留一个：每 15 分钟跑 `scripts/watch.ps1 -Config <总览>/projects.json`，它只拉起 `trunk-check.ps1`，不发通知。用 `conhost.exe --headless <pwsh 完整路径> -NoProfile -File ...` 启动，免得窗口闪。改计划任务是持久配置，用户同意才改。

## 5. 跨项目教训

同一条教训在 2 个以上项目出现的，写进总览 `LESSONS.md`，按顺序升级：本 skill 的脚本或模板；用户级 hook 或权限规则（安全设置，用户同意才改）；本 skill 某个模块里的一条。改 skill 作为一条请求交给 ai-dev-flow 仓库。
