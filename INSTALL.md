# 安装说明（给 AI 编程助手读）

用户把这份文件交给你，是要你在本机装好 `ai-dev-flow` 和 `/next` 两个 skill。按下面的步骤做，做完用三行告诉用户结果。用户说什么语言就用什么语言回复。

## 1. 检查环境

- 系统要是 Windows，并且装了 PowerShell 7（运行 `pwsh --version` 能看到 7.x）。不是 Windows 就告诉用户：规则可以用，但脚本跑不了，问用户还装不装。没有 `pwsh` 就给出安装命令 `winget install Microsoft.PowerShell`，由用户决定装不装，你不要自己装。
- 看本机有哪些宿主：有 `~/.claude` 目录说明装了 Claude Code，有 `~/.codex` 目录或者能运行 `codex` 命令说明装了 Codex。两个都没有，也照样装到 `~/.agents/skills/`。

## 2. 拿到源文件

- 当前目录就是这个仓库（里面有 `skills/ai-dev-flow/SKILL.md`），直接用当前目录。
- 否则把仓库 `git clone --depth 1` 到一个新建的临时目录。

## 3. 复制到用户级 skill 目录

把源文件里的 `skills/ai-dev-flow`、`skills/next` 两个目录复制到 `~/.agents/skills/` 下面（Codex 从这里读用户级 skill）。

目标目录已经存在时，先跟源文件比一下：

- 内容一样：跳过这一步。
- 内容不一样：列出哪些文件不同，问用户覆盖还是保留。不要直接覆盖，那里可能有用户自己的修改。

## 4. 接上 Claude Code

装了 Claude Code 的话，在 `~/.claude/skills/` 下面给这两个 skill 各建一个目录链接（junction），指向第 3 步复制好的目录，这样两边用的是同一份：

```powershell
foreach ($n in 'ai-dev-flow', 'next') {
    New-Item -ItemType Junction -Path "$env:USERPROFILE\.claude\skills\$n" -Target "$env:USERPROFILE\.agents\skills\$n"
}
```

`~/.claude/skills/<名字>` 已经存在时：已经是指向同一个目录的链接，就跳过；是普通目录，或者指向别处，就问用户怎么处理，不要删。

## 5. 确认装好了

- 逐个比对源文件和 `~/.agents/skills/` 下的两个目录，确认内容完全一致；装了 Claude Code 的，再确认两个链接都指向对的目录。
- 告诉用户：新开一个会话 skill 才会加载；装好以后在项目里说 `/next`，或者直接说"想做 X"就能用。

## 6. 可选功能（一次问完）

下面三项默认都不装。把它们一次列给用户，问要哪几项，推荐先都不装，用顺了再加：

1. **推送到手机**：通过 Bark 推送，只推需要用户决定或出手的事。用户要装，就向用户要 Bark 的推送地址，写进 `%APPDATA%\ai-dev-flow\notify.json`：`{ "bark": "https://api.day.app/<key>", "barkLevels": ["user", "stuck"] }`。这个文件放在本机，不要提交到任何仓库，也不要把 key 打印出来。
2. **会话等权限时弹通知**（只适用于 Claude Code）：在 `~/.claude/settings.json` 的 `hooks.Notification` 里加一条命令：`pwsh -NoProfile -File <~/.agents/skills/ai-dev-flow 的完整路径>/scripts/notify.ps1 -Hook`。改之前先读原文件，保留里面已有的设置。
3. **合并后在后台跑全量测试**：建一个计划任务，每 15 分钟运行一次 `conhost.exe --headless <pwsh 完整路径> -NoProfile -File <skill 完整路径>/scripts/watch.ps1 -Config <总览>\projects.json`。这项要先有多项目总览，详见 `skills/ai-dev-flow/modules/portfolio.md`。没有总览就跳过这项，并告诉用户为什么。

## 7. 收尾

第 2 步克隆过临时目录的，告诉用户这个目录的路径，由用户决定删不删。

## 升级

用户要升级时，同样按这份说明做一遍：第 3 步会把新旧两版的差别列出来交给用户决定，第 4 步的链接已经建好的会跳过。
