param([string]$Script = (Join-Path $PSScriptRoot '../skills/ai-dev-flow/scripts/status.ps1'), [switch]$Keep)
# status.ps1 的检查：在系统临时目录建几个一次性仓库，对 -Json 和文本输出逐条断言；退出码 0 才算通过。-Keep 保留这些仓库便于查看。
#   pwsh -NoProfile -File tests/status.tests.ps1
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$root = Join-Path ([IO.Path]::GetTempPath()) ("status-fixture-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$fail = 0
function Check($name, $cond) { if ($cond) { "ok   $name" } else { "FAIL $name"; $script:fail++ } }
function G { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main @args; if ($LASTEXITCODE) { throw "git $args" } }
# 快检提速（队列 #70）：下面一百多处 `pwsh -NoProfile -File <脚本> ...` 改在本进程里跑，省掉每次新起 pwsh 的几秒。
# 这个函数比 pwsh.exe 先被找到，被测脚本里再调 `& pwsh -NoProfile -File ...`（脚本间调用）也走这里。
# 输出照子进程那样转成字符串，异常当退出码 1，退出码照传，当前目录跑完恢复。真起子进程的检查用 $PwshExe。
$PwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
function pwsh {
    # 管道送进来的（notify.ps1 -Hook 从标准输入读事件）照旧起子进程：本进程里调用读不到标准输入。
    $piped = @($input)
    if ($piped.Count) { $piped | & $PwshExe @args; return }
    $i = 0
    while ($i -lt $args.Count -and "$($args[$i])" -in '-NoProfile', '-NonInteractive') { $i++ }
    if ("$($args[$i])" -ne '-File') { & $PwshExe @args; return }
    $file = $args[$i + 1]
    $rest = @($args | Select-Object -Skip ($i + 2))
    # 按命令行的规矩绑参数：数组展开（脚本的参数数组）进来的 '-Json' 只是字符串，要对着脚本的参数表认出来。
    $params = (Get-Command -Name $file -CommandType ExternalScript).Parameters
    $named = @{}; $pos = [Collections.Generic.List[object]]::new()
    for ($k = 0; $k -lt $rest.Count; $k++) {
        $tok = $rest[$k]
        $m = if ($tok -is [string]) { [regex]::Match($tok, '^-([A-Za-z]\w*)(?::(.*))?$') }
        $hit = if ($m -and $m.Success) { @($params.Keys | Where-Object { $_ -like "$($m.Groups[1].Value)*" }) }
        if ($hit.Count -eq 1 -or ($hit -contains $m.Groups[1].Value)) {
            $name = if ($hit -contains $m.Groups[1].Value) { $m.Groups[1].Value } else { $hit[0] }
            if ($params[$name].SwitchParameter) { $named[$name] = if ($m.Groups[2].Success) { $m.Groups[2].Value -notin '$false', 'false', '0' } else { $true } }
            elseif ($m.Groups[2].Success) { $named[$name] = $m.Groups[2].Value }
            else { $k++; $named[$name] = $rest[$k] }
        }
        else { $pos.Add($tok) }
    }
    $posArr = $pos.ToArray()
    $global:LASTEXITCODE = 0
    Push-Location -LiteralPath (Get-Location).Path
    try { & $file @named @posArr | ForEach-Object { if ($_ -is [Management.Automation.ErrorRecord]) { $_ } else { "$_" } } }
    catch { Write-Error -ErrorRecord $_ -ErrorAction Continue; $global:LASTEXITCODE = 1 }
    finally { Pop-Location }
}

$a = Join-Path $root '项目 A'
$null = New-Item -ItemType Directory -Force -Path (Join-Path $a 'docs'), (Join-Path $a '.agents/digest')
G init -q $a
Set-Content -LiteralPath (Join-Path $a 'AGENTS.md') -Encoding utf8NoBOM -Value "- **信任等级 L1**（用户定）"
Set-Content -LiteralPath (Join-Path $a '.gitignore') -Encoding utf8NoBOM -Value '.agents/'
@'
# 队列

| # | 目标 | 完成标准 | 档 | 依赖 | 状态 |
|---|---|---|---|---|---|
| 1 | 写 a\|b 解析 | 过 | 自走 | 无 | 完成（合main abc） |
| 2 | 看界面 | 截图 | 看一眼 | 无 | **待用户**（等你看截图） |
| 3 | 推远程 | 授权 | 单向门 | 无 | 待用户 |
| 4 | 跑回归 | 绿 | 自走 | 1 | 在做（r2） |
| 5 | 说不准 | 绿 | 自走 | 无 | 部分已定：选了 A |
| 8 | 依赖已完成 | 绿 | 自走 | 1 | 待做 |
| 9 | 依赖还在做 | 绿 | 自走 | #4、1 | 待做 |
| 10 | 依赖别的项目 | 绿 | 自走 | 引擎 #22 | 待做 |
| 11 | 没有依赖 | 绿 | 自走 | 无 | 待做 |
| 12 | 依赖的项已删 | 绿 | 自走 | 99 | 待做 |
| 13 | 依赖只有井号 | 绿 | 自走 | # | 待做 |

另一张不算队列的表：

| 名称 | 值 |
|---|---|
| x | 待用户 |

目标 | # | 档 | 状态
:--|:-:|---|--:
无竖线表 | 6 | 自走 | 待用户（另一种写法）

说明 | 状态
没有分隔行 | 待用户
还是没有 | 待用户

```
| code | 状态 |
|---|---|
| x | 待用户 |
```

````markdown
```
| ex | 状态 |
|---|---|
| e1 | 待用户 |
```
| ex | 状态 |
|---|---|
| e2 | 待用户 |
````

~~~markdown
```powershell
```
~~~

| # | 目标 | 档 | 状态 |
|---|---|---|---|
| 7 | 围栏后的真表 | 看一眼 | 待用户（真的） |

    | ex | 状态 |
    |---|---|
    | e3 | 待用户 |

```
``` 不是结束
| ex | 状态 |
|---|---|
| e4 | 待用户 |
```
'@ | Set-Content -LiteralPath (Join-Path $a 'docs/queue.md') -Encoding utf8NoBOM
G -C $a add -A; G -C $a commit -q -m 'c1'
$c1 = (G -C $a rev-parse HEAD)
@"
reviewed-through: $c1

# 教训

## 规则一
原因：x
Seen：2（2026-10-29、2026-10-30）

## 规则二
Seen：1（2026-10-30）

## 规则三该升级
Seen：3（2026-10-28、2026-10-29、2026-10-30）

## 规则四已交出去
Seen：4（2026-10-27、2026-10-28、2026-10-29、2026-10-30）
升级：已写进 ai-dev-flow 的 docs/requests.md（2026-10-30）
"@ | Set-Content -LiteralPath (Join-Path $a 'LESSONS.md') -Encoding utf8NoBOM
@'
# 收到的请求

## 2026-10-30 已经转了
- **状态**：已转（队列 #3）

## 2026-10-31 还没转
- **现象**：x
- **状态**：待转

## 2026-11-01 忘了写状态
- **请求**：y

## 2026-11-02 处理完了
- **状态**：已处理（2.0.0）
'@ | Set-Content -LiteralPath (Join-Path $a 'docs/requests.md') -Encoding utf8NoBOM
G -C $a add -A; G -C $a commit -q -m 'c2 中文提交'
G -C $a branch merged-one
G -C $a worktree add -q (Join-Path $root 'wt-merged') merged-one
G -C $a worktree add -q --detach (Join-Path $root 'wt-detached') HEAD
G -C $a worktree add -q -b gone (Join-Path $root 'wt-gone') HEAD
Remove-Item -Recurse -Force (Join-Path $root 'wt-gone')
G -C $a switch -q -c side; G -C $a commit -q --allow-empty -m 'side only'; G -C $a switch -q main
Set-Content -LiteralPath (Join-Path $a 'scratch.txt') -Value 'x'
$null = New-Item -ItemType Directory -Force -Path (Join-Path $a '未跟踪 目录')
'1' | Set-Content -LiteralPath (Join-Path $a '未跟踪 目录/一.txt'); '2' | Set-Content -LiteralPath (Join-Path $a '未跟踪 目录/二.txt')
Add-Content -LiteralPath (Join-Path $a 'AGENTS.md') -Value 'edit'
"今天：合了 1 项`n北极星：7（昨天 5）`n返工：0 / 1`n要你做：无" | Set-Content -LiteralPath (Join-Path $a '.agents/digest/2026-10-30.md') -Encoding utf8NoBOM
"北极星：9（昨天 7）" | Set-Content -LiteralPath (Join-Path $a '.agents/digest/2026-10-31.md') -Encoding utf8NoBOM

$b = Join-Path $root 'b'
G init -q $b; G -C $b commit -q --allow-empty -m 'b1'

$cfg = Join-Path $root 'hq/projects.json'
$null = New-Item -ItemType Directory -Force -Path (Split-Path $cfg)
@{ projects = @(
    @{ name = '项目 A'; path = $a; status = '推进中'; priority = 1; trunk = 'main'; dependsOn = @('b', '不存在')
       goals = @(@{ text = '目标一'; items = @('1') }, @{ text = '目标二'; items = @('#4') }, @{ text = '手动勾的 <x>'; done = $true }) }
    @{ name = 'b'; path = $b; status = '维护'; priority = 2 }
    @{ name = 'gone'; path = (Join-Path $root 'nope'); status = '推进中'; priority = 3 }
    @{ name = 'paused'; path = $b; status = '暂停' }
    @{ name = 'paused-gone'; path = (Join-Path $root 'nope'); status = '暂停' }
) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfg -Encoding utf8NoBOM

try {
    (Get-Item -LiteralPath (Join-Path $a '.gitignore')).LastWriteTime = (Get-Date).AddMinutes(-5)
    $run = Join-Path $a '.agents/runs/r1/final.md'
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $run)
    'done' | Set-Content -LiteralPath $run
    $runTime = (Get-Date).AddMinutes(30)
    (Get-Item -LiteralPath $run).LastWriteTime = $runTime
    $index = Join-Path $a '.git/index'
    $indexBefore = (Get-FileHash -LiteralPath $index).Hash
    $j = pwsh -NoProfile -File $Script -Config $cfg -Json -Lessons | Out-String | ConvertFrom-Json
    Check 'exit 0' ($LASTEXITCODE -eq 0)
    Check 'project index not rewritten' ((Get-FileHash -LiteralPath $index).Hash -eq $indexBefore)
    $pa = $j.Projects | Where-Object Name -eq '项目 A'
    Check 'order: active by priority, then maintenance' (($j.Projects.Name -join ',') -eq '项目 A,gone,b')
    Check 'paused listed by name, missing path marked' (($j.Paused -join ',') -eq 'paused,paused-gone（路径不存在）')
    Check 'trust parsed' ($pa.Trust -eq 'L1')
    Check 'queue counts' ($pa.Queue.'完成' -eq 1 -and $pa.Queue.'待用户' -eq 4 -and $pa.Queue.'在做' -eq 1 -and $pa.Queue.'其他' -eq 1 -and $pa.Queue.'待做' -eq 6)
    Check 'tables without state column or separator row, and code blocks, ignored' ((($pa.Queue.PSObject.Properties.Value | Measure-Object -Sum).Sum) -eq 13)
    Check 'available: deps done, none, or deleted; not open, foreign or number-less' ($pa.Available -eq 3)
    Check 'last activity takes the newest of branches and runs' ($pa.LastActivity -eq $runTime.ToString('yyyy-MM-dd HH:mm'))
    Check 'doing and nonstandard items listed' ((($pa.Doing | ForEach-Object Id) -join ',') -eq '4' -and (($pa.Other | ForEach-Object Id) -join ',') -eq '5')
    Check 'not stalled while active' (-not ($pa.Problems -match '^可能停滞'))
    $pb0 = $j.Projects | Where-Object Name -eq 'b'
    Check 'last activity from commits when no runs' ($pb0.LastActivity -eq (G -C $b log -1 '--format=%cd' '--date=format:%Y-%m-%d %H:%M') -and $pb0.IdleMinutes -ge 0)
    Check 'waiting items with tier and detail' ((($pa.Waiting | ForEach-Object { "$($_.Id)/$($_.Tier)/$($_.Detail)" }) -join ';') -eq '2/看一眼/等你看截图;3/单向门/;6/自走/另一种写法;7/看一眼/真的')
    Check 'escaped pipe does not shift columns' ($pa.Queue.'完成' -eq 1)
    Check 'unknown state reported' ([bool]($pa.Problems | Where-Object { $_ -like '*#5*' }))
    Check 'unknown dependency reported' ([bool]($pa.Problems | Where-Object { $_ -like '*不存在*' }))
    Check 'unreviewed = 1' ($pa.Unreviewed -eq 1)
    Check 'new commits on trunk only' ($pa.NewCount -eq 2 -and -not ($pa.NewCommits -match 'side only'))
    Check 'chinese subject decoded' ([bool]($pa.NewCommits -match 'c2 中文提交'))
    Check 'lessons with seen' ((($pa.Lessons | ForEach-Object { "$($_.Seen):$($_.Title)" }) -join ';') -eq '2:规则一;1:规则二;3:规则三该升级;4:规则四已交出去')
    Check 'lessons due: seen 3 without an upgrade line, reported' ((($pa.LessonsDue | ForEach-Object { "$($_.Seen):$($_.Title)" }) -join ';') -eq '3:规则三该升级' -and [bool]($pa.Problems -match '^教训 Seen 达到 3 还没升级：规则三该升级（Seen 3）$'))
    Check 'requests: pending and missing state listed, transferred and handled not' ((($pa.Requests | ForEach-Object { "$($_.Title)=$($_.State)" }) -join ';') -eq '2026-10-31 还没转=待转;2026-11-01 忘了写状态=未写状态' -and [bool]($pa.Problems -match '^还没转进队列的请求 2 条：2026-10-31 还没转、2026-11-01 忘了写状态$'))
    Check 'latest digest lines' ($pa.Digest.Date -eq '2026-10-31' -and ($pa.Digest.Lines -join ';') -eq '北极星：9（昨天 7）')
    Check 'worktrees' ($pa.Worktrees -eq 3 -and $pa.WorktreesMerged -eq 2 -and $pa.WorktreesDetached -eq 1 -and $pa.WorktreesMissing -eq 1)
    Check 'merged branches exclude trunk' ($pa.BranchesMerged -eq 2)
    Check 'cleanup hint: not at or below the threshold' (-not ($pa.Problems -match 'cleanup.ps1'))
    $pOver = (pwsh -NoProfile -File $Script -Config $cfg -Project '项目 A' -CleanupOver 1 -Json | ConvertFrom-Json).Projects[0]
    Check 'cleanup hint: over the threshold, says what to run' ([bool]($pOver.Problems -match '已合进主干还没删.*分支 2 个.*cleanup\.ps1'))
    Check 'uncommitted vs untracked files' ($pa.Uncommitted -eq 1 -and $pa.Untracked -eq 3)
    $pg = $j.Projects | Where-Object Name -eq 'gone'
    Check 'missing path reported' ([bool]($pg.Problems | Where-Object { $_ -like '路径不存在*' }))
    $pb = $j.Projects | Where-Object Name -eq 'b'
    Check 'no queue reported' ([bool]($pb.Problems | Where-Object { $_ -like '没有队列文件*' }))

    $null = pwsh -NoProfile -File $Script -Config $cfg -Mark
    G -C $a commit -q --allow-empty -m 'after mark'
    (Get-Item -LiteralPath $run).LastWriteTime = (Get-Date).AddHours(-3)
    $j2 = pwsh -NoProfile -File $Script -Config $cfg -Json | Out-String | ConvertFrom-Json
    $pa2 = $j2.Projects | Where-Object Name -eq '项目 A'
    Check 'lessons due and requests without -Lessons' ($pa2.LessonsDue.Count -eq 1 -and $pa2.Requests.Count -eq 2 -and -not $pa2.Lessons)
    Check 'mark: only commits after it' ($pa2.NewCount -eq 1 -and $pa2.NewSince -like '自上次标记*')
    $j3 = pwsh -NoProfile -File $Script -Config $cfg -Json -Since '2000-01-01' | Out-String | ConvertFrom-Json
    Check 'stale only past -StaleMinutes' (-not (($j2.Projects | Where-Object Name -eq '项目 A').Problems -match '^可能停滞'))
    $js = pwsh -NoProfile -File $Script -Config $cfg -Json -StaleMinutes 0 | Out-String | ConvertFrom-Json
    Check 'stalled: active project with work in progress and no activity' ([bool](($js.Projects | Where-Object Name -eq '项目 A').Problems -match '^可能停滞：在做 1 项') -and -not (($js.Projects | Where-Object Name -eq 'b').Problems -match '^可能停滞'))
    Check '-Since overrides mark' ((($j3.Projects | Where-Object Name -eq '项目 A').NewCount) -eq 3)
    $j4 = pwsh -NoProfile -File $Script -Config $cfg -Json -Project paused | Out-String | ConvertFrom-Json
    Add-Content -LiteralPath (Join-Path $a 'docs/queue.md') -Value '' -Encoding utf8NoBOM
    G -C $a add docs/queue.md; G -C $a commit -q -m 'queue: claim'
    $ju = pwsh -NoProfile -File $Script -Config $cfg -Json -Project '项目 A' | Out-String | ConvertFrom-Json
    Check 'unreviewed: queue-only and empty commits not counted' ($ju.Projects[0].Unreviewed -eq 1)
    Set-Content -LiteralPath (Join-Path $a 'code.txt') -Value 'x' -Encoding utf8NoBOM
    Add-Content -LiteralPath (Join-Path $a 'docs/queue.md') -Value '' -Encoding utf8NoBOM
    G -C $a add code.txt docs/queue.md; G -C $a commit -q -m 'code and queue'
    $ju = pwsh -NoProfile -File $Script -Config $cfg -Json -Project '项目 A' | Out-String | ConvertFrom-Json
    Check 'unreviewed: a commit touching queue and other files counts' ($ju.Projects[0].Unreviewed -eq 2)
    Check '-Project includes paused' (($j4.Projects.Name -join ',') -eq 'paused' -and ($j4.Paused -join ',') -eq 'paused-gone（路径不存在）')
    $j5 = pwsh -NoProfile -File $Script -Config $cfg -Json -Project 'b, 项目 A' | Out-String | ConvertFrom-Json
    Check '-Project takes comma-separated names' (($j5.Projects.Name -join ',') -eq '项目 A,b')
    $null = pwsh -NoProfile -File $Script -Config $cfg -Project b extra 2>&1
    Check 'no positional parameters' ($LASTEXITCODE -ne 0)
    $empty = Join-Path $root 'hq/empty.json'
    Set-Content -LiteralPath $empty -Value '{}'
    $null = pwsh -NoProfile -File $Script -Config $empty 2>&1
    Check 'list without projects fails' ($LASTEXITCODE -ne 0)

    Push-Location (Split-Path $cfg)
    try { $j6 = & $Script -Config './projects.json' -Json | Out-String | ConvertFrom-Json } catch { $j6 = $null } finally { Pop-Location }
    Check 'relative -Config resolved against current location' ($j6 -and $j6.Projects.Count -eq 3)

    $t = pwsh -NoProfile -File $Script -Config $cfg | Out-String
    Check 'text summary line' ($t -match '推进中 2 · 维护 1 · 暂停 2；待用户合计 4（单向门 1 · 看一眼 2 · 自走 1）')
    Check 'text waiting line' ($t -match '待用户 #2 \[看一眼\] 看界面：等你看截图')
    Check 'maintenance is brief' ($t -notmatch '(?s)## b · 维护.*工作区')
    Check 'text available' ($t -match '可领 3')

    Check 'no shelved rows: no shelved count in text' ($t -notmatch '搁置')
    Check 'text hints for lessons due and pending requests' ($t -match '提示：教训 Seen 达到 3 还没升级：规则三该升级' -and $t -match '提示：还没转进队列的请求 2 条')
    Check 'all rows numbered: no missing-number hint' (-not ($pa.Problems -match '没有编号'))

    $c = Join-Path $root '项目 C'
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $c 'docs')
    G init -q $c
    @'
| # | 目标 | 依赖 | 状态 |
|---|---|---|---|
| 1 | 先放着 | 无 | 搁置（等数据） |
| 2 | 依赖搁置的项 | 1 | 待做 |
| 3 | 能领的项 | 无 | 待做 |
| 4 | 写法不对 | 无 | 暂停于安全点 |
| 5 | 做完了 | 无 | 完成 |
| 6 | 等别处 | 无 | 待用户（不急，等应用提出再开） |
| 7 | 长记录 | 无 | 待用户（LONGLOG） |
| 8 | 真问题一 | 无 | 待用户（要不要合并：推荐合并；等你说可以就合并、再做 #12） |
| 9 | 真问题二 | 无 | 待用户（要不要暂停 watch 的计划任务；A 简单但不急着要，推荐 A） |
| 10 | 用户先不改 | 无 | 待用户（用户："先不改，用一段时间再说"；等 2.6.1 用过一段时间、看停下的频率再定） |
| 11 | 真问题三 | 无 | 待用户（要不要合并：推荐合并，小问题合并后再说；要不要先停掉 watch；等您确认后合并） |
| 12 | 只写不急 | 无 | 待用户（不急） |

| 目标 | 状态 |
|---|---|
| 没编号等你 | 待用户（看报告） |
| 没编号在做 | 在做 |
| 没编号做完了 | 完成 |

| 项 | 状态 | 说明 / 提交 |
|---|---|---|
| 说明写在别列 | 待用户 | 本周暂停（用户：先停，等本周结果） |
| 说明只是历史 | 待用户（选 A 还是 B，推荐 A） | 11-01 搁置过，用户 11-05 恢复 |
'@ -replace 'LONGLOG', ('过程' * 160) | Set-Content -LiteralPath (Join-Path $c 'docs/queue.md') -Encoding utf8NoBOM
    G -C $c add -A; G -C $c commit -q -m 'c1'
    $cfgC = Join-Path $root 'projects-c.json'
    @{ projects = @(@{ name = '项目 C'; path = $c; status = '推进中' }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgC -Encoding utf8NoBOM
    $pc = (pwsh -NoProfile -File $Script -Config $cfgC -Json | ConvertFrom-Json).Projects[0]
    $tc = pwsh -NoProfile -File $Script -Config $cfgC | Out-String
    $slow = Join-Path $root 'slow'
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $slow 'docs'), (Join-Path $slow '.agents')
    G init -q $slow
    Set-Content -LiteralPath (Join-Path $slow '.gitignore') -Encoding utf8NoBOM -Value '.agents/'
    Set-Content -LiteralPath (Join-Path $slow 'AGENTS.md') -Encoding utf8NoBOM -Value '- **信任等级 L1**'
    $slowQ = { param($state) "| # | 目标 | 依赖 | 状态 |`n|---|---|---|---|`n| 1 | 别的事 | 无 | 待做 |`n| 2 | 快检提速：并行 | 无 | $state |" | Set-Content -LiteralPath (Join-Path $slow 'docs/queue.md') -Encoding utf8NoBOM }
    & $slowQ '完成'
    G -C $slow add -A; G -C $slow commit -q -m 's1'
    $cfgSlow = Join-Path $root 'projects-slow.json'
    $slowCfg = { param($status) @{ projects = @(@{ name = '慢'; path = $slow; status = $status }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgSlow -Encoding utf8NoBOM }
    $slowRun = { (pwsh -NoProfile -File $Script -Config $cfgSlow -All -Json | ConvertFrom-Json).Projects[0] }
    $slowHint = { param($q) [bool](@($q.Problems) -match '快检最近一次') }
    & $slowCfg '推进中'
    Check 'slow verify: no record, no hint' (-not (& $slowHint (& $slowRun)))
    Set-Content -LiteralPath (Join-Path $slow '.agents/verify-last.json') -Encoding utf8NoBOM -Value '{"head":"abc","seconds":601,"date":"2026-11-08"}'
    $q = & $slowRun
    Check 'slow verify: over 10 minutes, only a finished speed-up item: hint' ((& $slowHint $q) -and $q.VerifySeconds -eq 601)
    $page = Join-Path $root 'out/status-slow.html'
    & $slowQ '待做'
    Check 'slow verify: a speed-up item waiting: no hint' (-not (& $slowHint (& $slowRun)))
    & $slowQ '在做（r2）'
    Check 'slow verify: a speed-up item in progress: no hint' (-not (& $slowHint (& $slowRun)))
    & $slowQ '完成'
    Set-Content -LiteralPath (Join-Path $slow '.agents/verify-last.json') -Encoding utf8NoBOM -Value '{"head":"abc","seconds":600,"date":"2026-11-08"}'
    Check 'slow verify: exactly 10 minutes: no hint' (-not (& $slowHint (& $slowRun)))
    Set-Content -LiteralPath (Join-Path $slow '.agents/verify-last.json') -Encoding utf8NoBOM -Value '{"head":"abc","seconds":1200,"date":"2026-11-08"}'
    & $slowCfg '维护'
    Check 'slow verify: project not being pushed: no hint' (-not (& $slowHint (& $slowRun)))
    & $slowCfg '推进中'
    Set-Content -LiteralPath (Join-Path $slow 'AGENTS.md') -Encoding utf8NoBOM -Value "- **信任等级 L1**`n- **快检提速阈值**：30 分钟（要跑宿主软件）"
    Check 'slow verify: threshold in AGENTS.md wins' (-not (& $slowHint (& $slowRun)))
    Set-Content -LiteralPath (Join-Path $slow 'AGENTS.md') -Encoding utf8NoBOM -Value "- **信任等级 L1**`n- **快检提速阈值**：15 分钟"
    Check 'slow verify: threshold in AGENTS.md also lowers the bar' (& $slowHint (& $slowRun))
    Set-Content -LiteralPath (Join-Path $slow '.agents/verify-last.json') -Encoding utf8NoBOM -Value '{"seconds":'
    $q = & $slowRun
    Check 'slow verify: broken record is ignored' (-not (& $slowHint $q) -and $null -eq $q.VerifySeconds)
    Check 'verify unknown: broken record is reported as unknown' ([bool](@($q.Problems) -match '^快检用时未知：.*读不出'))

    # 快检提醒补全：提速项挂着不动、用时未知、超过阈值 2 倍
    $stall = Join-Path $root 'stall'
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $stall 'docs'), (Join-Path $stall '.agents')
    G init -q $stall
    Set-Content -LiteralPath (Join-Path $stall '.gitignore') -Encoding utf8NoBOM -Value '.agents/'
    Set-Content -LiteralPath (Join-Path $stall 'AGENTS.md') -Encoding utf8NoBOM -Value '- **信任等级 L1**'
    $stallQ = { param($goal) "| # | 目标 | 依赖 | 状态 |`n|---|---|---|---|`n| 1 | 别的事 | 无 | 待做 |`n| 7 | $goal | 无 | 待做 |" | Set-Content -LiteralPath (Join-Path $stall 'docs/queue.md') -Encoding utf8NoBOM }
    & $stallQ '快检提速：并行'
    $old = (Get-Date).AddDays(-5).ToString('yyyy-MM-ddTHH:mm:ss')
    $env:GIT_AUTHOR_DATE = $old; $env:GIT_COMMITTER_DATE = $old
    try { G -C $stall add -A; G -C $stall commit -q -m 'queue: add #7 speed up verify' } finally { Remove-Item Env:GIT_AUTHOR_DATE, Env:GIT_COMMITTER_DATE }
    Set-Content -LiteralPath (Join-Path $stall 'a.txt') -Encoding utf8NoBOM -Value 'x'
    G -C $stall add -A; G -C $stall commit -q -m 'other work #1, not #70'
    $cfgStall = Join-Path $root 'projects-stall.json'
    $stallCfg = { param($status) @{ projects = @(@{ name = '提速挂着'; path = $stall; status = $status }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgStall -Encoding utf8NoBOM }
    $stallRun = { param([string[]]$more) (pwsh -NoProfile -File $Script -Config $cfgStall -All -Json @more | ConvertFrom-Json).Projects[0] }
    $stallRec = { param($sec, $date) Set-Content -LiteralPath (Join-Path $stall '.agents/verify-last.json') -Encoding utf8NoBOM -Value "{`"head`":`"abc`",`"seconds`":$sec,`"date`":`"$date`"}" }
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $stallHint = { param($q) @(@($q.Problems) -match '^快检提速项挂着不动') }
    $unknownHint = { param($q) @(@($q.Problems) -match '^快检用时未知') }
    & $stallCfg '推进中'
    $q = & $stallRun
    Check 'verify unknown: no verify-last.json: hint' ((& $unknownHint $q).Count -eq 1 -and [bool]((& $unknownHint $q) -match '没有 \.agents/verify-last\.json.*dispatch'))
    & $stallRec 1200 $today
    $q = & $stallRun
    Check 'speed-up stalled: item untouched for 5 days: hint with only the current time when no note has one' ((& $stallHint $q).Count -eq 1 -and [bool]((& $stallHint $q) -match '#7 已 5 天没有提交提到它.*取不到.*现在 1200 秒') -and @($q.SpeedUpStalled.Ids) -contains '7' -and $null -eq $q.SpeedUpStalled.FromSeconds)
    Check 'verify unknown: fresh record: no hint' (-not (& $unknownHint $q).Count -and $q.VerifyDate -eq $today -and $q.VerifyLimitMinutes -eq 10)
    Check 'verify red: exactly 2x the threshold: not red' (-not $q.VerifySlowRed -and -not (@($q.Problems) -match '2 倍'))
    $first = (G -C $stall rev-list --max-parents=0 HEAD) | Select-Object -First 1
    G -C $stall notes --ref=verify add -m '覆盖：x；跑了：verify → 退出 0，快检用时：700 秒；没跑：无' $first
    $q = & $stallRun
    Check 'speed-up stalled: growth from the verify note at the start' ([bool]((& $stallHint $q) -match '从 700 秒.*到现在 1200 秒，涨了 500 秒') -and $q.SpeedUpStalled.FromSeconds -eq 700)
    Set-Content -LiteralPath (Join-Path $stall 'b.txt') -Encoding utf8NoBOM -Value 'x'
    G -C $stall add -A; G -C $stall commit -q -m 'verify: run groups in parallel (#7)'
    $q = & $stallRun
    Check 'speed-up stalled: a recent commit mentions the item: no hint' (-not (& $stallHint $q).Count -and $null -eq $q.SpeedUpStalled -and -not (@($q.Problems) -match '^快检最近一次'))
    & $stallRec 1201 $today
    $q = & $stallRun
    Check 'verify red: over 2x the threshold: flagged even with a fresh speed-up item' ($q.VerifySlowRed -eq $true -and [bool](@($q.Problems) -match '^快检超过阈值 2 倍：.*20 分钟.*阈值 10 分钟；合并照常'))
    $page = Join-Path $root 'out/status-red.html'
    & $stallRec 1201 (Get-Date).AddDays(-8).ToString('yyyy-MM-dd')
    $q = & $stallRun
    Check 'verify unknown: record older than 7 days: hint' ([bool]((& $unknownHint $q) -match '是 \d{4}-\d{2}-\d{2} 的，超过 7 天'))

    $alias = Join-Path $root 'alias'
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $alias 'docs')
    G init -q $alias
    @'
| # | 目标 | 依赖 | 状态 |
|---|---|---|---|
| 1 | 甲 | 无 | 已合并（11-06） |
| 2 | 乙 | 无 | 已完成 |
| 3 | 丙 | 无 | 进行中（r2） |
| 4 | 丁 | 无 | 暂停（等数据） |
| 5 | 戊 | 无 | 暂停于安全点 |
| 6 | 己 | 无 | 部分已定：选了 A |
| 7 | 依赖暂停的项 | 4 | 待做 |
| 8 | 依赖已合并的项 | 1 | 待做 |
| 9 | 庚 | 无 | 已完成部分 |
| 10 | 辛 | 无 | 暂停在安全点 |
| 11 | 壬 | 无 | 暂停（于安全点） |
| 12 | 癸 | 无 | 已合并到分支，待验证 |
| 13 | 子 | 无 | 已完成 部分 |
| 14 | 丑 | 无 | 已合并（到分支，待验证） |
| 15 | 寅 | 无 | 暂停（要不要继续，等你定） |
| 16 | 卯 | 无 | 已合并（未验证） |
| 17 | 辰 | 无 | 已完成（第一阶段） |
| 18 | 巳 | 无 | 暂停（待重派） |
'@ | Set-Content -LiteralPath (Join-Path $alias 'docs/queue.md') -Encoding utf8NoBOM
    G -C $alias add -A; G -C $alias commit -q -m 'a1'
    $cfgAlias = Join-Path $root 'projects-alias.json'
    @{ projects = @(@{ name = '写法'; path = $alias; status = '推进中' }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgAlias -Encoding utf8NoBOM
    $pAlias = (pwsh -NoProfile -File $Script -Config $cfgAlias -Json | ConvertFrom-Json).Projects[0]
    Check 'state aliases: counted as the standard state' ($pAlias.Queue.'完成' -eq 2 -and $pAlias.Queue.'在做' -eq 1 -and $pAlias.Queue.'搁置' -eq 1 -and (($pAlias.Doing | ForEach-Object Detail) -join ',') -eq 'r2')
    Check 'state aliases: pause at a safe point and unclear words are still reported' ((($pAlias.Other | ForEach-Object Id) -join ',') -eq '5,6,9,10,11,12,13,14,15,16,17,18' -and [bool]($pAlias.Problems -match '认不出.*#5.*#6') -and -not ($pAlias.Problems -match '认不出.*#[1-4]（'))
    Check 'state aliases: dependencies follow the standard state' ($pAlias.Next.Id -contains '8' -and $pAlias.Next.Id -notcontains '7')

    # 搁置文件：docs/queue-shelved.md 和主队列一起算
    $sh = Join-Path $root 'shelf'
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $sh 'docs')
    G init -q $sh
    $shQueue = @'
| # | 目标 | 依赖 | 状态 |
|---|---|---|---|
| 1 | 甲 | 无 | 完成 |
| 2 | 依赖搁置的项 | 3 | 待做 |
| 4 | 没有依赖 | 无 | 待做 |
'@
    Set-Content -LiteralPath (Join-Path $sh 'docs/queue.md') -Encoding utf8NoBOM -Value $shQueue
    @'
# 搁置

| # | 目标 | 依赖 | 状态 |
|---|---|---|---|
| 3 | 放着的项 | 无 | 搁置（等上线） |
| 5 | 放错地方的项 | 无 | 待做 |
'@ | Set-Content -LiteralPath (Join-Path $sh 'docs/queue-shelved.md') -Encoding utf8NoBOM
    G -C $sh add -A; G -C $sh commit -q -m 's1'
    Set-Content -LiteralPath (Join-Path $sh 'LESSONS.md') -Encoding utf8NoBOM -Value "reviewed-through: $(git -C $sh rev-parse HEAD)"
    G -C $sh add -A; G -C $sh commit -q -m 's2'
    Add-Content -LiteralPath (Join-Path $sh 'docs/queue-shelved.md') -Encoding utf8NoBOM -Value '| 6 | 又放一项 | 无 | 搁置 |'
    G -C $sh add -A; G -C $sh commit -q -m 's3 shelf only'
    $cfgShelf = Join-Path $root 'projects-shelf.json'
    @{ projects = @(@{ name = '搁置文件'; path = $sh; status = '推进中' }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgShelf -Encoding utf8NoBOM
    $pSh = (pwsh -NoProfile -File $Script -Config $cfgShelf -Json | ConvertFrom-Json).Projects[0]
    Check 'shelf file: a dependency there is not met' ($pSh.Available -eq 1 -and (($pSh.Next | ForEach-Object Id) -join ',') -eq '4' -and -not @($pSh.Items | Where-Object { $_.Id -eq '2' -and $_.Claimable }).Count)
    Check 'shelf file: its rows are listed and counted' ((($pSh.Items | ForEach-Object Id) -join ',') -eq '1,2,4,3,5,6' -and $pSh.Queue.'搁置' -eq 2 -and @($pSh.Items | Where-Object { $_.Id -eq '3' -and $_.State -eq '搁置' }).Count)
    Check 'shelf file: a row there that is not shelved is reported and not claimable' ([bool]($pSh.Problems -match 'queue-shelved\.md 里有不是搁置的项：#5；移回 docs/queue\.md') -and -not ($pSh.Problems -match '不是搁置的项：.*#[36]') -and -not @($pSh.Items | Where-Object { $_.Id -eq '5' -and $_.Claimable }).Count)
    Check 'shelf file: no duplicate ids, no duplicate hint' (-not ($pSh.Problems -match '都有的编号|没有带「状态」列'))
    $shelfText = Get-Content -LiteralPath (Join-Path $sh 'docs/queue-shelved.md') -Raw -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $sh 'docs/queue.md') -Encoding utf8NoBOM -Value ($shQueue.TrimEnd() + "`n| 3 | 忘了删的旧行 | 无 | 待做 |")
    $pShD = (pwsh -NoProfile -File $Script -Config $cfgShelf -Json | ConvertFrom-Json).Projects[0]
    Check 'shelf file: an id in both files is reported' ([bool]($pShD.Problems -match '^docs/queue\.md 和 queue-shelved\.md 里都有的编号：#3；'))
    Set-Content -LiteralPath (Join-Path $sh 'docs/queue.md') -Encoding utf8NoBOM -Value $shQueue
    Set-Content -LiteralPath (Join-Path $sh 'docs/queue-shelved.md') -Encoding utf8NoBOM -Value ($shelfText -replace '\| 状态 \|', '| 状況 |')
    $pShB = (pwsh -NoProfile -File $Script -Config $cfgShelf -Json | ConvertFrom-Json).Projects[0]
    Check 'shelf file: no table there is reported and a dependency found nowhere stays unmet' ([bool]($pShB.Problems -match '^queue-shelved\.md 里没有带「状态」列的表') -and (($pShB.Next | ForEach-Object Id) -join ',') -eq '4')
    Set-Content -LiteralPath (Join-Path $sh 'docs/queue-shelved.md') -Encoding utf8NoBOM -Value "# 搁置`n`n| # | 目标 | 依赖 | 状态 |`n|---|---|---|---|"
    $pShH = (pwsh -NoProfile -File $Script -Config $cfgShelf -Json | ConvertFrom-Json).Projects[0]
    Check 'shelf file: only a header is fine, a dependency found nowhere counts as done' (-not ($pShH.Problems -match '没有带「状态」列') -and (($pShH.Next | ForEach-Object Id) -join ',') -eq '2,4')
    Set-Content -LiteralPath (Join-Path $sh 'docs/queue-shelved.md') -Encoding utf8NoBOM -Value ''
    $pShE = (pwsh -NoProfile -File $Script -Config $cfgShelf -Json | ConvertFrom-Json).Projects[0]
    Check 'shelf file: an empty one counts as none' (-not ($pShE.Problems -match '没有带「状态」列') -and (($pShE.Next | ForEach-Object Id) -join ',') -eq '2,4')
    Set-Content -LiteralPath (Join-Path $sh 'docs/queue-shelved.md') -Encoding utf8NoBOM -Value $shelfText
    Check 'shelf file: commits touching only it are not counted as unreviewed' ($pSh.Unreviewed -eq 1)
    Remove-Item -LiteralPath (Join-Path $sh 'docs/queue-shelved.md')
    $pSh0 = (pwsh -NoProfile -File $Script -Config $cfgShelf -Json | ConvertFrom-Json).Projects[0]
    Check 'shelf file: without it, a missing dependency counts as done as before' ($pSh0.Available -eq 2 -and (($pSh0.Next | ForEach-Object Id) -join ',') -eq '2,4' -and $pSh0.Queue.'搁置' -eq 0 -and -not ($pSh0.Problems -match '不是搁置'))
    # 待放行：会话自己加、还没放行的项，不算可领，依赖它的也没满足，文本列出
    $rl = Join-Path $root 'release'
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $rl 'docs')
    G init -q $rl
    @'
| # | 目标 | 依赖 | 状态 |
|---|---|---|---|
| 1 | 用户要的 | 无 | 待做 |
| 2 | 复盘自己加的 | 无 | 待放行（复盘 11-12 加；不挂本周目标） |
| 3 | 依赖待放行的项 | 2 | 待做 |
'@ | Set-Content -LiteralPath (Join-Path $rl 'docs/queue.md') -Encoding utf8NoBOM
    G -C $rl add -A; G -C $rl commit -q -m 'r1'
    $cfgRel = Join-Path $root 'projects-release.json'
    @{ projects = @(@{ name = '待放行'; path = $rl; status = '推进中' }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgRel -Encoding utf8NoBOM
    $pRl = (pwsh -NoProfile -File $Script -Config $cfgRel -Json | ConvertFrom-Json).Projects[0]
    Check 'pending release: counted as its own state, not unknown' ($pRl.Queue.'待放行' -eq 1 -and $pRl.Queue.'其他' -eq 0 -and -not ($pRl.Problems -match '认不出'))
    Check 'pending release: not claimable, and blocks what depends on it' ($pRl.Available -eq 1 -and (($pRl.Next | ForEach-Object Id) -join ',') -eq '1' -and -not @($pRl.Items | Where-Object { $_.Id -in '2', '3' -and $_.Claimable }).Count)
    Check 'pending release: listed with its note' ((($pRl.Pending | ForEach-Object Id) -join ',') -eq '2' -and $pRl.Pending[0].Detail -eq '复盘 11-12 加；不挂本周目标')
    $tRl = pwsh -NoProfile -File $Script -Config $cfgRel | Out-String
    Check 'pending release: text lists it' ($tRl -match '待放行 1' -and $tRl -match '  待放行 #2 复盘自己加的：复盘 11-12 加')
    Check 'shelved: counted, not reported as unknown' ($pc.Queue.'搁置' -eq 1 -and $pc.Queue.'其他' -eq 1 -and -not ($pc.Problems -match '先放着|等数据') -and $tc -match '搁置 1')
    Check 'shelved: still an unknown state next to it is reported' ([bool]($pc.Problems -match '认不出.*#4'))
    Check 'shelved: not available, and blocks what depends on it' ($pc.Available -eq 1 -and $pc.Next[0].Id -eq '3')
    Check 'no number: open rows reported, done rows not' ([bool]($pc.Problems -match '没有编号的项：没编号等你、没编号在做、说明写在别列、说明只是历史$'))
    Check 'no lessons or requests file: nothing due, no hint' (-not $pc.LessonsDue -and -not $pc.Requests -and -not ($pc.Problems -match '教训|请求'))
    Check 'no number: no lone # in the text' ($tc -match '待用户 没编号等你：看报告' -and $tc -notmatch '# 没编号' -and $tc -notmatch '待用户 #\s')
    Check 'no runs dir: no dead runs' (@($pc.DeadRuns).Count -eq 0 -and -not ($pc.Problems -match '运行死了'))
    Check 'waiting hints: shelved-like, process log, plain ask untouched' ((($pc.Waiting | ForEach-Object { "$($_.Id)=$($_.Hint)" }) -join ';') -eq '6=像搁置;7=过程记录;8=;9=;10=像搁置;11=;12=像搁置;=;=像搁置;=' -and [bool]($pc.Problems -match '^待用户项像是搁置.*：#6、#10、#12、说明写在别列；') -and [bool]($pc.Problems -match '^待用户项的状态格写成了过程记录.*：#7；'))
    Check 'waiting hints: none on ordinary asks' (-not ($pa.Problems -match '^待用户项'))

    $dd = Join-Path $root '项目 D'
    G init -q $dd; G -C $dd commit -q --allow-empty -m 'd1'
    $self = Get-Process -Id $PID
    $gone = Start-Process -FilePath $self.Path -ArgumentList '-NoProfile -Command exit' -PassThru -WindowStyle Hidden
    $gone.WaitForExit()
    foreach ($case in @(@{ n = 'dead'; pid = $gone.Id; started = (Get-Date) }, @{ n = 'alive'; pid = $PID; started = $self.StartTime },
                        @{ n = 'reused'; pid = $PID; started = $self.StartTime.AddHours(-3) }, @{ n = 'old-dead'; pid = $gone.Id; started = (Get-Date).AddDays(-10) },
                        @{ n = 'finished'; pid = $gone.Id; started = (Get-Date); exit = $true },
                        @{ n = 'superseded'; pid = $gone.Id; started = (Get-Date).AddHours(-2); branch = 'b1' }, @{ n = 'redo'; pid = $gone.Id; started = (Get-Date).AddHours(-1); branch = 'b1'; exit = $true },
                        @{ n = 'last-on-branch'; pid = $gone.Id; started = (Get-Date).AddHours(-1); branch = 'b2' }, @{ n = 'earlier-on-branch'; pid = $gone.Id; started = (Get-Date).AddHours(-2); branch = 'b2'; exit = $true })) {
        $rd = Join-Path $dd ".agents/runs/$($case.n)"
        $null = New-Item -ItemType Directory -Force -Path $rd
        @{ Name = $case.n; Branch = $case.branch; Pid = $case.pid; Started = $case.started.ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $rd 'meta.json') -Encoding utf8NoBOM
        if ($case.exit) { '{"ExitCode":0}' | Set-Content -LiteralPath (Join-Path $rd 'exit.json') }
    }
    $cfgD = Join-Path $root 'projects-d.json'
    @{ projects = @(@{ name = '项目 D'; path = $dd; status = '推进中' }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgD -Encoding utf8NoBOM
    $pd = (pwsh -NoProfile -File $Script -Config $cfgD -Json | ConvertFrom-Json).Projects[0]
    Check 'dead runs: no exit record and process gone or reused; not alive, finished, older than 7 days or redone on the same branch' (@($pd.DeadRuns).Count -eq 3 -and (@($pd.DeadRuns | Sort-Object) -join ',') -eq 'dead,last-on-branch,reused')
    Check 'dead runs: reported as a hint' (@($pd.Problems | Where-Object { $_ -match '^派出去的运行死了（没有退出记录，进程也不在）：' -and $_ -match '\bdead\b' -and $_ -match 'reused' -and $_ -match 'last-on-branch' -and $_ -notmatch 'superseded' }).Count -eq 1)

    $notify = Join-Path (Split-Path $Script) 'notify.ps1'
    $ncfg = Join-Path $root 'hq/notify.json'
    '{ "bark": "https://example.invalid/secret-key", "barkLevels": ["user", "stuck"] }' | Set-Content -LiteralPath $ncfg
    $n1 = pwsh -NoProfile -File $notify -Config $ncfg -Title 'p' -Body 'b' -Level done -DryRun | Out-String
    $n2 = pwsh -NoProfile -File $notify -Config $ncfg -Title 'p' -Body 'b' -Level stuck -DryRun | Out-String
    Check 'notify: done stays on the desktop, stuck goes to the phone' ($n1 -match 'bark: no' -and $n2 -match 'bark: yes' -and $n2 -match 'title: 🔴 p')
    Check 'notify: dry run never prints the key' ($n1 + $n2 -notmatch 'secret-key')
    $n3 = '{"cwd":"C:\\x\\项目 A","message":"needs permission"}' | pwsh -NoProfile -File $notify -Config $ncfg -Hook -DryRun | Out-String
    Check 'notify: hook event gives project and message, desktop only' ($n3 -match 'title: 项目 A' -and $n3 -match 'body: needs permission' -and $n3 -match 'bark: no')
    $null = pwsh -NoProfile -File $notify -Config $ncfg -Title 'p' -Level urgent -DryRun 2>&1
    Check 'notify: unknown level fails' ($LASTEXITCODE -ne 0)
    $n4 = '{"cwd":"C:\\x\\项目 A","message":"Claude is waiting for your input","notification_type":"idle_prompt"}' | pwsh -NoProfile -File $notify -Config $ncfg -Hook -DryRun | Out-String
    Check 'notify: idle reminder is dropped' ($n4 -match 'skip: idle_prompt' -and $n4 -notmatch 'toast:')
    $n5 = '{"cwd":"C:\\x\\项目 A","message":"x","notification_type":"quota_auto_resume_stale"}' | pwsh -NoProfile -File $notify -Config $ncfg -Hook -DryRun | Out-String
    Check 'notify: missed auto-resume goes to the phone in plain words' ($n5 -match 'bark: yes' -and $n5 -match 'title: 🔴 项目 A' -and $n5 -match 'body: 额度已经重置.*按回车')
    $n6 = '{"cwd":"C:\\x\\项目 A","message":"Claude needs your permission","notification_type":"permission_prompt"}' | pwsh -NoProfile -File $notify -Config $ncfg -Hook -DryRun | Out-String
    Check 'notify: permission prompt stays on the desktop' ($n6 -match 'toast: yes' -and $n6 -match 'bark: no' -and $n6 -match 'body: Claude needs your permission')
    $n7 = '{"cwd":"C:\\x\\项目 A","message":"Bash 要你批准","notification_type":"agent_needs_input"}' | pwsh -NoProfile -File $notify -Config $ncfg -Hook -DryRun | Out-String
    Check 'notify: background session waiting on you goes to the phone and says where to answer' ($n7 -match 'bark: yes' -and $n7 -match 'title: 🟡 项目 A' -and $n7 -match 'body: 后台会话在等你：Bash 要你批准.*claude agents')
    $n8 = '{"cwd":"C:\\x\\项目 A","message":"done","notification_type":"agent_completed"}' | pwsh -NoProfile -File $notify -Config $ncfg -Hook -DryRun | Out-String
    Check 'notify: background session finished stays on the desktop' ($n8 -match 'toast: yes' -and $n8 -match 'bark: no')

    # 有活没人做：有可领的项、没有在做的、超过 -IdleHours 没动静才提示；有待用户项照样提示；同一次只推一次
    $idleRepo = Join-Path $root 'idle'
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $idleRepo 'docs')
    G init -q $idleRepo
    @'
| # | 目标 | 依赖 | 状态 |
|---|---|---|---|
| 1 | 能领的项 | 无 | 待做 |
| 2 | 等你定的 | 无 | 待用户（选 A 还是 B，推荐 A） |
'@ | Set-Content -LiteralPath (Join-Path $idleRepo 'docs/queue.md') -Encoding utf8NoBOM
    $env:GIT_COMMITTER_DATE = (Get-Date).AddHours(-20).ToString('yyyy-MM-ddTHH:mm:ss')
    G -C $idleRepo add -A; G -C $idleRepo commit -q -m 'i1'
    $blocked = Join-Path $root 'idle-none'
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $blocked 'docs')
    G init -q $blocked
    @'
| # | 目标 | 依赖 | 状态 |
|---|---|---|---|
| 1 | 等你定的 | 无 | 待用户（定） |
| 2 | 依赖没满足 | 1 | 待做 |
'@ | Set-Content -LiteralPath (Join-Path $blocked 'docs/queue.md') -Encoding utf8NoBOM
    G -C $blocked add -A; G -C $blocked commit -q -m 'n1'
    Remove-Item Env:GIT_COMMITTER_DATE
    $cfgIdle = Join-Path $root 'projects-idle.json'
    @{ projects = @(@{ name = '空着的'; path = $idleRepo; status = '推进中' }, @{ name = '没可领'; path = $blocked; status = '推进中' }, @{ name = '刚动过'; path = $sh; status = '推进中' }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgIdle -Encoding utf8NoBOM
    $pIdle = (pwsh -NoProfile -File $Script -Config $cfgIdle -Json | ConvertFrom-Json).Projects
    Check 'unattended: claimable, nobody on it, over 12 hours, flagged even with an ask' ([bool](@($pIdle[0].Problems) -match '^有活没人做：1 项可领，没有在做的，已 20 小时没有动静') -and @($pIdle[0].Waiting).Count -eq 1)
    Check 'unattended: nothing claimable, not flagged' (-not (@($pIdle[1].Problems) -match '有活没人做'))
    Check 'unattended: recent activity, not flagged' ($pIdle[2].Available -ge 1 -and -not (@($pIdle[2].Problems) -match '有活没人做'))
    $pIdle24 = (pwsh -NoProfile -File $Script -Config $cfgIdle -Json -IdleHours 24 | ConvertFrom-Json).Projects
    Check 'unattended: the threshold can be raised' (-not (@($pIdle24[0].Problems) -match '有活没人做'))
    # 决定回流：docs/decision-log.md 里上次标记以来的决定列出来，写错的提示
    $dl = Join-Path $root 'declog'
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $dl 'docs')
    G init -q $dl
    Set-Content -LiteralPath (Join-Path $dl 'docs/queue.md') -Encoding utf8NoBOM -Value "| # | 目标 | 依赖 | 状态 |`n|---|---|---|---|`n| 1 | 甲 | 无 | 待做 |"
    $dOld = (Get-Date).AddDays(-10).ToString('yyyy-MM-dd'); $dMid = (Get-Date).AddDays(-3).ToString('yyyy-MM-dd'); $dNew = (Get-Date).ToString('yyyy-MM-dd')
    @"
# 用户的决定

一行一条，新的写在后面。

- $dOld（评分口径）：过关标准改成 95% 原话："先按 95% 来"
- $dMid（上线范围）：先不做手机端 原话：“手机端以后再说”
- $dNew（换路线）：改用新识别路线 原话："按新路线做"
- 2026-13-40（预算）：日期写错 原话："x"
- $dNew 少了类别和原话
- 2026/11/13（换路线）：日期写成斜杠 原话："按 A 做"
- **$dNew**（子系统）：日期加粗 原话："拆"
1. $dNew（预算）：编号列表 原话："再给两天"
- 普通的说明，不是决定
- 记的时候把用户原话抄全，不要改写
- （子系统）：没写日期 原话："y"
"@ | Set-Content -LiteralPath (Join-Path $dl 'docs/decision-log.md') -Encoding utf8NoBOM
    G -C $dl add -A; G -C $dl commit -q -m 'd1'
    $dlHq = Join-Path $root 'declog-hq'
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $dlHq '.agents')
    @{ projects = @(@{ name = '决定'; path = $dl; status = '推进中' }, @{ name = '没记录'; path = $idleRepo; status = '推进中' }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dlHq 'projects.json') -Encoding utf8NoBOM
    $pDl = (pwsh -NoProfile -File $Script -Config (Join-Path $dlHq 'projects.json') -Json | ConvertFrom-Json).Projects
    Check 'decisions: without a mark, the last 7 days are listed with kind and quote' ((($pDl[0].Decisions | ForEach-Object { "$($_.Date)|$($_.Kind)|$($_.Text)|$($_.Quote)" }) -join ';') -eq "$dMid|上线范围|先不做手机端|手机端以后再说;$dNew|换路线|改用新识别路线|按新路线做")
    Check 'decisions: lines it cannot read are reported by line' ([bool](@($pDl[0].Problems) -match '^docs/decision-log\.md 里认不出的决定：第 8 行、第 9 行、第 10 行、第 11 行、第 12 行、第 15 行；'))
    Check 'decisions: no log file, nothing listed and no hint' (-not @($pDl[1].Decisions).Count -and -not (@($pDl[1].Problems) -match 'decision-log'))
    @{ '决定' = @{ head = (git -C $dl rev-parse HEAD); time = (Get-Date).AddDays(-1).ToString('yyyy-MM-dd HH:mm') } } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dlHq '.agents/status-marks.json') -Encoding utf8NoBOM
    $pDlM = (pwsh -NoProfile -File $Script -Config (Join-Path $dlHq 'projects.json') -Json | ConvertFrom-Json).Projects[0]
    Check 'decisions: after a mark only those from the mark day on' ((($pDlM.Decisions | ForEach-Object Date) -join ',') -eq $dNew)
    $tDl = pwsh -NoProfile -File $Script -Config (Join-Path $dlHq 'projects.json') | Out-String
    Check 'decisions: text lists them' ($tDl -match "  新决定 $dNew（换路线）改用新识别路线 原话：`"按新路线做`"")

    $watch = Join-Path (Split-Path $Script) 'watch.ps1'
    $wstate = Join-Path $root 'watch-state.json'
    $w = pwsh -NoProfile -File $watch -Config $cfg -State $wstate -StaleMinutes 0 -IdleHours 0 -GoalHours 0 -DryRun | Out-String
    Check 'watch dry run exits zero' ($LASTEXITCODE -eq 0)
    Check 'watch dry run announces trunk check' ($w -match '会拉起 trunk-check.ps1')
    Check 'watch dry run sends no notifications' ($w -notmatch 'toast:|bark:|title:')
    Check 'watch dry run writes no state' (-not (Test-Path $wstate))
    $w = pwsh -NoProfile -File $watch -NoTrunkCheck -DryRun | Out-String
    Check 'watch dry run respects NoTrunkCheck' ($LASTEXITCODE -eq 0 -and $w -match '不会拉起 trunk-check.ps1')
    $null = pwsh -NoProfile -File $Script -Config (Join-Path $root 'missing.json') 2>&1
    Check 'missing config fails' ($LASTEXITCODE -ne 0)
    $null = pwsh -NoProfile -File $Script -Config $cfg -Project nobody 2>&1
    Check 'unknown -Project fails' ($LASTEXITCODE -ne 0)
}
finally {
    if ($Keep) { "kept: $root" } else {
    Get-ChildItem -LiteralPath $root -Recurse -Force | ForEach-Object { $_.Attributes = 'Normal' }
    Remove-Item -LiteralPath $root -Recurse -Force }
}
if ($fail) { "$fail check(s) failed"; exit 1 } else { 'all checks passed'; exit 0 }

