[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Config,
    [string]$Lock,
    [string]$Rerun,
    [switch]$DryRun,
    [switch]$NotifyDryRun
)
# 本机待跑只取当前最新主干；文档沿用绿树不等待。
# trunkIdleMinutes=30：连续空闲后跑；trunkNightWindow="02:00-06:00"：夜里忙也跑；
# trunkMaxAgeHours=24：超过此时间未跑（含从未跑）且本轮不忙就跑；-Rerun 绕过等待。
# -Lock 旁 trunk-check-idle.json 记录忙闲与连续空闲起点，trunk-check-local.json 记录本机尝试时间，
# trunk-check-pending.json 为同树同类等待日志去重；DryRun 不写这些文件，打印所有待跑的决策。
# 本机 setup/verify 用 BelowNormal，缺省环境 AI_DEV_FLOW_TRUNK=1、AI_DEV_FLOW_TRUNK_PARALLEL=
# trunkParallel（默认逻辑核一半至少 1）；保底忙时设 AI_DEV_FLOW_MACHINE_BUSY=1，不覆盖继承环境。
# 测试可用 AI_DEV_FLOW_TRUNK_NOW 注入本机时间。
# 合并后在后台跑全量（ai-dev-flow modules/land.md 第 6 节，队列 #66、#71）：一轮最多跑一个项目，全机一次只跑一个全量。
# 清单里没暂停且写了 trunkVerify 的项目，在干净分离 worktree 跑 trunkSetup 和 trunkVerify。
# 按清单顺序找第一个"主干这棵树、这条全量命令账上还没有记录"的（verify-ledger.ps1：绿的、红的都算有记录，红的不重跑）：
# 主干不写就用主检出当前所在的分支（和 status.ps1 一样）。项目的 .agents/ 没被 Git 忽略的不跑（记不了账，会每轮重跑），status.ps1 提示。
# 跑完记不进账或上轮本机进程被杀（inflight 文件检测）的，
# 这棵树+命令记进 -Lock 旁边的 trunk-check-norecord.txt，不再自动重跑（amend/rebase 保留同一棵树也不重跑），推一次手机（可用 -Rerun 重跑）。
# 跑绿了把用时写进 <项目>/.agents/verify-last.json（source 写 trunk-check）；红了在 <项目>/.agents/trunk-red.json 留记录并推一次手机。
# 不叠跑：-Lock 文件（默认 %LOCALAPPDATA%\ai-dev-flow\trunk-check.lock）用独占新建拿锁，里面记持锁进程的 PID 和启动时间，进程不在了或启动时间对不上算陈旧锁；
#   pwsh -NoProfile -File trunk-check.ps1 -Config <总览仓库>/projects.json [-DryRun]
#   -Rerun <项目名>  这个项目主干这棵树红过或上次中断/记不进账的也重跑一次（skills/next/SKILL.md 第 1 节第 5 步）；绿过的不跑
#   -DryRun  打印每个待跑项目本轮的决策和原因，不写状态、不跑、不发通知
#   -NotifyDryRun  通知只打印不发（传 -DryRun 给 notify.ps1，测试用）
# 退出码：0 这轮跑完或没有要跑的；1 脚本自己出错；全量红了也是 0（结果在账上和通知里）。
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$here = $PSScriptRoot
$ledgerScript = Join-Path $here 'verify-ledger.ps1'

if (-not $Config) { $Config = Join-Path (Split-Path $here -Parent) 'projects.json' }
if (-not $Lock) { $Lock = Join-Path $env:LOCALAPPDATA 'ai-dev-flow/trunk-check.lock' }
if (-not (Test-Path -LiteralPath $Config)) { throw "没有清单：$Config" }
$cfgDir = Split-Path (Resolve-Path -LiteralPath $Config).Path
$lockDir = Split-Path $Lock
$noRecord = Join-Path $lockDir 'trunk-check-norecord.txt'
$inFlight = Join-Path $lockDir 'trunk-check-inflight.txt'

function Notify([string]$title, [string]$body) {
    $nArgs = @('-Title', $title, '-Body', $body, '-Level', 'stuck')
    if ($NotifyDryRun) { $nArgs += '-DryRun' }
    & pwsh -NoProfile -File (Join-Path $here 'notify.ps1') @nArgs
}

function Get-CmdKey([string]$cmd) {
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($cmd))).ToLowerInvariant()
}

# 锁：内容是"PID|进程启动时间（UTC ticks）"。进程不在了、启动时间对不上（PID 被别的进程复用）、内容读不出，都算陈旧锁。
function Test-LockLive {
    if (-not (Test-Path -LiteralPath $Lock)) { return $false }
    $parts = "$(Get-Content -LiteralPath $Lock -Raw -ErrorAction SilentlyContinue)".Trim() -split '\|'
    $id = 0; $ticks = 0L
    if ($parts.Count -ne 2 -or -not [int]::TryParse($parts[0], [ref]$id) -or -not [long]::TryParse($parts[1], [ref]$ticks)) { return $false }
    $pr = Get-Process -Id $id -ErrorAction SilentlyContinue
    if (-not $pr) { return $false }
    try { $pr.StartTime.ToUniversalTime().Ticks -eq $ticks } catch { $false }
}
function Enter-Lock {
    $null = New-Item -ItemType Directory -Force -Path $lockDir
    if ((Test-Path -LiteralPath $Lock) -and -not (Test-LockLive)) { Remove-Item -LiteralPath $Lock -ErrorAction SilentlyContinue }
    try { $fs = [IO.File]::Open($Lock, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read) } catch { return $false }
    try { $b = [Text.Encoding]::ASCII.GetBytes("$PID|$((Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks)"); $fs.Write($b, 0, $b.Length) } finally { $fs.Dispose() }
    $true
}

# 按命令 token 匹配，忽略引号和连续空白；不把参数中的单词当子串匹配。
function Normalize-TrunkCommand([string]$Command) {
    $Command = $Command -replace '^\s*(?:"[^"]*[\\/]pwsh\.exe"|[^\s"]*[\\/]pwsh\.exe)', 'pwsh' -replace '^pwsh\.exe\b', 'pwsh'
    (($Command -replace '["'']', '' -replace '\\', '/' -replace '(?<=^|\s)\./', '' -replace '\s+', ' ').Trim()).ToLowerInvariant()
}
function Find-TrunkProcesses($Processes, $Commands, [int]$SelfId) {
    $excluded = [Collections.Generic.HashSet[int]]::new()
    $null = $excluded.Add($SelfId)
    do {
        $changed = $false
        foreach ($pr in $Processes) {
            if ($excluded.Contains([int]$pr.ParentProcessId) -and $excluded.Add([int]$pr.ProcessId)) { $changed = $true }
        }
    } while ($changed)
    foreach ($pr in $Processes) {
        if ($excluded.Contains([int]$pr.ProcessId)) { continue }
        $line = Normalize-TrunkCommand "$($pr.CommandLine)"
        $match = if ($env:AI_DEV_FLOW_BUSY_MARK) { $line.Contains($env:AI_DEV_FLOW_BUSY_MARK.ToLowerInvariant()) } else {
            $line -match 'verify-ledger\.ps1.*-command' -or @($Commands | Where-Object {
                $cmd = Normalize-TrunkCommand $_
                $cmd -and (' ' + $line + ' ').Contains(' ' + $cmd + ' ')
            }).Count -gt 0
        }
        if ($match) { "进程 $($pr.ProcessId)：$($pr.CommandLine)" }
    }
}
function Get-TrunkCpuBusy($Samples, [double]$Limit) {
    $avg = ($Samples | Measure-Object -Average).Average
    if ($avg -ge $Limit) { "CPU 三秒平均 $([math]::Round($avg, 1))%，阈值 $Limit%" }
}
function Get-LocalBusy {
    $processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $hits = @(Find-TrunkProcesses $processes @($cfg.projects | Where-Object { $_.trunkVerify -is [string] } | ForEach-Object { $_.trunkVerify }) $PID)
    if ($hits) { return $hits }
    # 测试夹具用独立进程标记隔离真实负载；生产取三次一秒 CPU 样本的均值。
    if (-not $env:AI_DEV_FLOW_BUSY_MARK) {
        $limit = if ($null -ne $cfg.trunkCpuThreshold) { [double]$cfg.trunkCpuThreshold } else { 75 }
        if ($limit -le 0 -or $limit -gt 100) { throw 'trunkCpuThreshold 必须大于 0 且不超过 100' }
        $samples = @(1..3 | ForEach-Object {
            Start-Sleep -Seconds 1
            (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop).PercentProcessorTime
        })
        Get-TrunkCpuBusy $samples $limit
    }
}
function Get-TrunkNumber([string]$Key, [double]$Default, [double]$Minimum) {
    $value = 0.0
    if ($null -eq $cfg.$Key) { return $Default }
    if (-not [double]::TryParse("$($cfg.$Key)", [ref]$value) -or [double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt $Minimum -or ($Key -eq 'trunkParallel' -and $value -ne [math]::Floor($value))) {
        Write-Warning "$Key 配置错误，使用默认值 $Default"
        return $Default
    }
    $value
}
function Read-TrunkState([string]$File) {
    try { $v = Get-Content -LiteralPath $File -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop; if ($v -is [System.Collections.IDictionary]) { return $v } } catch { }; @{}
}
function Save-TrunkState([string]$File, $Value) {
    try { $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $File -Encoding utf8NoBOM }
    catch { Write-Warning "无法保存主干调度状态，将在后续轮次重新观察：$($_.Exception.Message)" }
}
# watch 每 15 分钟观察；容许 10 分钟调度延迟。超过 25 分钟的采样间隙不算连续空闲。
function Update-LocalObservation {
    $script:now = if ($env:AI_DEV_FLOW_TRUNK_NOW) { [datetime]::Parse($env:AI_DEV_FLOW_TRUNK_NOW) } else { Get-Date }
    $script:night = if ($start -lt $end) { $now.TimeOfDay -ge $start -and $now.TimeOfDay -lt $end } else { $now.TimeOfDay -ge $start -or $now.TimeOfDay -lt $end }
    $script:busyNow = @(Get-LocalBusy)
    $state = Read-TrunkState $idleFile
    $script:idleSince = $now
    $previous = [datetime]::MinValue; $since = [datetime]::MinValue
    if (-not $busyNow -and $state.busy -eq $false -and [datetime]::TryParse("$($state.observed)", [ref]$previous) -and [datetime]::TryParse("$($state.idleSince)", [ref]$since) -and $since -le $previous -and $previous -le $now -and ($now - $previous).TotalMinutes -le 25) { $script:idleSince = $since }
    if (-not $DryRun) { Save-TrunkState $idleFile @{ observed=$now.ToString('o'); busy=[bool]$busyNow; idleSince=$idleSince.ToString('o') } }
    $script:localEnvironment = @{ PYTHONUTF8='1'; PYTHONIOENCODING='utf-8'; AI_DEV_FLOW_TRUNK='1'; AI_DEV_FLOW_TRUNK_PARALLEL="$parallel" }
    if ($busyNow) { $script:localEnvironment.AI_DEV_FLOW_MACHINE_BUSY = '1' }
}
function Get-LocalDecision($Pick) {
    if ($Rerun) { return @{ Run=$true; Kind='manual'; Reason='手动重跑' } }
    if ($night) { return @{ Run=$true; Kind='night'; Reason='保底时段' } }
    if ($busyNow) { return @{ Run=$false; Kind='busy'; Reason="跳过：本机忙：$($busyNow -join '；')，等下一轮" } }
    $last = [datetime]::MinValue
    foreach ($e in @(Get-TrunkEntries $Pick.Path | Where-Object { $_.where -like '主干后台 本机*' })) {
        $t = [datetime]::MinValue
        if ([datetime]::TryParse("$($e.time)", [ref]$t) -and $t -gt $last) { $last = $t }
    }
    $t = [datetime]::MinValue
    if ([datetime]::TryParse("$($localHistory[$Pick.Path])", [ref]$t) -and $t -gt $last) { $last = $t }
    if (($now - $last).TotalHours -gt $maxAge) { return @{ Run=$true; Kind='age'; Reason="超过 $maxAge 小时未跑，本轮不忙" } }
    $minutes = [math]::Max(0, ($now - $idleSince).TotalMinutes)
    if ($minutes -ge $idleMinutes) { return @{ Run=$true; Kind='idle'; Reason="已连续空闲 $([int]$minutes)/$idleMinutes 分钟" } }
    @{ Run=$false; Kind='idle'; Reason="等空档：已连续空闲 $([int]$minutes)/$idleMinutes 分钟" }
}
function Write-Pending($Pick, $Decision) {
    "$($Pick.Name) 待跑：$($Decision.Reason)"
    if ($DryRun) { return }
    $key = "$($Pick.Path)|$($Pick.Tree)|$($Decision.Kind)"
    if (-not $pendingHistory.ContainsKey($key)) {
        Write-TrunkLog (Join-Path $Pick.Path '.agents/trunk-check.log') @("待跑：$($Decision.Reason)") $true
        $pendingHistory[$key] = $true
        Save-TrunkState $pendingFile $pendingHistory
    }
}
function Get-TrunkEntries([string]$Path) {
    $common = git -C $Path rev-parse --path-format=absolute --git-common-dir
    $main = if ((Split-Path $common -Leaf) -eq '.git') { Split-Path $common } else { $Path }
    $file = Join-Path $main '.agents/verify-ledger.jsonl'
    if (Test-Path -LiteralPath $file -PathType Leaf) {
        Get-Content -LiteralPath $file -Encoding UTF8 | ForEach-Object { try { $_ | ConvertFrom-Json -ErrorAction Stop } catch { } }
    }
}
function Get-DocumentGreen([string]$Path, [string]$Tree, [string]$Command) {
    # 最后一笔同命令红账是屏障，不跨过它继承更早的绿。
    $green = @(Get-TrunkEntries $Path | Where-Object { $_.command -ceq $Command }) | Select-Object -Last 1
    if ($green -and $green.result -ne 'green') { return }
    if (-not $green) { return }
    $null = git -C $Path cat-file -e "$($green.tree)^{tree}" 2>$null
    if ($LASTEXITCODE) { return }
    # --no-renames 同时检查改名前后的路径，删除脚本也不会漏掉。
    $paths = @(git -C $Path -c core.quotepath=false diff --no-renames --name-only $green.tree $Tree -- 2>$null)
    if ($LASTEXITCODE -or @($paths | Where-Object { $_ -notmatch '\.(md|markdown)$' }).Count) { return }
    $green
}
function Invoke-LocalVerify([string]$Command, [int]$TimeoutSeconds, $OutputLines) {
    $si = [Diagnostics.ProcessStartInfo]::new()
    $si.FileName = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
    $si.UseShellExecute = $false
    $si.CreateNoWindow = $true
    $si.WorkingDirectory = (Get-Location).Path
    $si.RedirectStandardOutput = $true; $si.RedirectStandardError = $true
    $utf8 = [Text.UTF8Encoding]::new($false)
    $si.StandardOutputEncoding = $utf8; $si.StandardErrorEncoding = $utf8
    if (-not $localEnvironment) { $localEnvironment = @{ PYTHONUTF8='1'; PYTHONIOENCODING='utf-8' } }
    foreach ($entry in $localEnvironment.GetEnumerator()) {
        if (-not $si.Environment.ContainsKey($entry.Key)) { $si.Environment[$entry.Key] = $entry.Value }
    }
    # 前置初始化保留原命令文本，项目仍可自行覆盖编码。
    $encodingPrelude = '(Get-Process -Id $PID).PriorityClass = ''BelowNormal''; [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); [Console]::InputEncoding = [Text.UTF8Encoding]::new($false); $OutputEncoding = [Text.UTF8Encoding]::new($false);' + "`n"
    foreach ($arg in @('-NoProfile', '-Command', ($encodingPrelude + $Command))) { $si.ArgumentList.Add($arg) }
    $proc = [Diagnostics.Process]::new(); $proc.StartInfo = $si
    try {
        $null = $proc.Start()
        $stdout = $proc.StandardOutput.ReadToEndAsync(); $stderr = $proc.StandardError.ReadToEndAsync()
        # 0 表示 setup 不受全量命令预算限制；仍使用同样的优先级和环境。
        $timedOut = $false
        if ($TimeoutSeconds -gt 0) { $timedOut = -not $proc.WaitForExit($TimeoutSeconds * 1000) }
        else { $proc.WaitForExit() }
        if ($timedOut) { $proc.Kill($true); $proc.WaitForExit() }
        foreach ($line in (($stdout.GetAwaiter().GetResult() + "`n" + $stderr.GetAwaiter().GetResult()) -split '\r?\n')) {
            if ($line) { $OutputLines.Add($line) }
        }
        if ($timedOut) { $OutputLines.Add("__TRUNK_LOCAL_BUDGET_TIMEOUT__=$TimeoutSeconds"); return 124 }
        return $proc.ExitCode
    } finally { $proc.Dispose() }
}
function Test-TimeoutOnly([int]$Code, $Lines, [string]$Where) {
    if ($Code -eq 0 -or $Where -match 'trunkSetup') { return $false }
    $text = $Lines -join "`n"
    if ($Code -eq 124 -and $Where -eq '主干后台 本机（预算超时）') {
        return $text -match '(?m)^__TRUNK_LOCAL_BUDGET_TIMEOUT__=\d+$' -and $text -notmatch '(?im)^\s*(?:FAIL(?:ED)?\b|ERROR\b|Traceback\b|[\w.]+(?:Error|Exception):)';
    }
    if ($text -match '(?m)^FAIL(?:\b|:)' ) { return $false }
    # 仅接受 pytest 的完整短摘要，每条失败都要带明确异常类型。未知输出保持 red。
    $failures = @($Lines | Where-Object { $_ -match '^(FAILED|ERROR)\s+\S+.* - ' })
    $summaries = [regex]::Matches($text, '(?m)^=+ (.+) in [\d.]+s.*=+$')
    if (-not $summaries.Count -or -not $failures.Count) {
        $us = [regex]::Matches($text, '(?m)^FAILED \(errors=(\d+)\)\s*$')
        $blocks = [regex]::Matches($text, '(?ms)^ERROR: [^\r\n]+\r?\n-+\r?\n(.*?)(?=^=+|^-+\r?\nRan |\z)')
        $uTotal = 0; foreach ($u in $us) { $uTotal += [int]$u.Groups[1].Value }
        if (-not $us.Count -or $Code -ne 1 -or $blocks.Count -ne $uTotal) { return $false }
        foreach ($block in $blocks) {
            $body = $block.Groups[1].Value.Trim()
            if ($body -notmatch '(?m)^(subprocess\.)?TimeoutExpired: [^\r\n]+$' -or $body -match '(?m)^(?!subprocess\.TimeoutExpired:|TimeoutExpired:)[\w.]+(Error|Exception):') { return $false }
        }
        return $blocks.Count -gt 0
    }
    $counts = @($summaries | ForEach-Object { [regex]::Matches($_.Groups[1].Value, '(\d+) (failed|error|errors)\b') })
    $total = 0; foreach ($m in $counts) { $total += [int]$m.Groups[1].Value }
    $Code -eq 1 -and $total -eq $failures.Count -and @($failures | Where-Object { $_ -notmatch '^(FAILED|ERROR)\s+\S+ - (subprocess\.)?TimeoutExpired:' }).Count -eq 0
}

function Write-TrunkLog([string]$logPath, [System.Collections.IEnumerable]$lines, [bool]$append) {
    try {
        $dir = Split-Path -Parent $logPath
        if ($dir) { $null = New-Item -ItemType Directory -Force -Path $dir }
        $enc = [Text.UTF8Encoding]::new($false)
        if ($append) { [IO.File]::AppendAllLines($logPath, [string[]]$lines, $enc) }
        else { [IO.File]::WriteAllLines($logPath, [string[]]$lines, $enc) }
    } catch { }
}

function Complete-LedgerAndEffects {
    param(
        $Pick,
        [string]$VerifyCmd,
        [int]$Code,
        [int]$Sec,
        [string]$Where,
        [string]$LogPath,
        [System.Collections.Generic.List[string]]$OutLines,
        [bool]$AppendLog,
        [ref]$RecordedRef,
        [switch]$Inherited
    )
    $OutLines.Add("退出码 $Code，$Sec 秒")
    Write-TrunkLog $LogPath $OutLines $AppendLog
    if (Test-TimeoutOnly $Code $OutLines $Where) {
        $attemptFile = Join-Path $Pick.Path '.agents/trunk-timeouts.json'
        $key = "$($Pick.Tree)|$(Get-CmdKey $VerifyCmd)"
        $attempt = try { Get-Content -LiteralPath $attemptFile -Raw | ConvertFrom-Json } catch { $null }
        $n = if ($attempt -and $attempt.key -eq $key) { [int]$attempt.count + 1 } else { 1 }
        @{ key = $key; count = $n; head = $Pick.Sha } | ConvertTo-Json | Set-Content -LiteralPath $attemptFile -Encoding utf8NoBOM
        if ($n -lt 3) {
            $msg = "机器忙，没跑成：仅超时（$n/3），下一轮重跑"
            $OutLines.Add($msg)
            Write-TrunkLog $LogPath $OutLines $AppendLog
            "$($Pick.Name)：$msg"
            if ($RecordedRef) { $RecordedRef.Value = $false }
            return
        }
    }
    $res = if ($Code -eq 0) { 'green' } else { 'red' }
    $null = pwsh -NoProfile -File $ledgerScript -Repo $Pick.Path -Record -Rev $Pick.Sha -Result $res -For $VerifyCmd -Seconds $Sec -Where $Where
    $lj = try { (pwsh -NoProfile -File $ledgerScript -Repo $Pick.Path -Check -Rev $Pick.Sha -For $VerifyCmd -Json) -join "`n" | ConvertFrom-Json } catch { $null }
    $recorded = [bool]($lj -and $lj.last -and $lj.last.result -eq $res -and $lj.last.where -eq $Where)
    "$($Pick.Name) 主干 $($Pick.Sha.Substring(0, 7))：$res（$Sec 秒）$(if (-not $recorded) { '，记不进账' })"
    $short = $Pick.Sha.Substring(0, 7)
    $redMark = Join-Path $Pick.Path '.agents/trunk-red.json'
    if (-not $recorded) {
        $nrKey = "$($Pick.Path)|$($Pick.Tree)|$(Get-CmdKey $VerifyCmd)"
        Add-Content -LiteralPath $noRecord -Value $nrKey -Encoding UTF8
        Notify "$($Pick.Name) 主干全量记不进账" "主干 $short 跑完是 $res，可账上没记下（.agents/verify-ledger.jsonl 写不进）。这棵树不再自动跑，输出在 .agents/trunk-check.log"
    }
    elseif ($res -eq 'green' -and -not $Inherited) {
        Remove-Item -LiteralPath $redMark -ErrorAction SilentlyContinue
        try {
            [ordered]@{ head = $Pick.Sha; seconds = $Sec; date = (Get-Date).ToString('yyyy-MM-dd'); source = 'trunk-check' } | ConvertTo-Json |
                Set-Content -LiteralPath (Join-Path $Pick.Path '.agents/verify-last.json') -Encoding utf8NoBOM
        } catch { }
    }
    elseif ($res -ne 'green') {
        try {
            [ordered]@{ project = $Pick.Name; head = $Pick.Sha; command = $VerifyCmd; config = (Resolve-Path -LiteralPath $Config).Path; log = '.agents/trunk-check.log'; date = (Get-Date).ToString('yyyy-MM-dd HH:mm') } | ConvertTo-Json |
                Set-Content -LiteralPath $redMark -Encoding utf8NoBOM
        } catch { }
        $tail = (@($OutLines) | Where-Object { $_ -match 'FAIL|失败|退出 [1-9]|exit [1-9]|超时' } | Select-Object -First 3) -join '；'
        Notify "$($Pick.Name) 主干全量红了" "主干 $short 合并后全量没过$(if ($tail) { "：$tail" })。在那个项目发 /next，会先修；输出在 .agents/trunk-check.log"
    }
    if ($RecordedRef) { $RecordedRef.Value = $recorded }
}

if ($DryRun) { if (Test-LockLive) { "跳过：另一轮全量还在跑（$Lock）"; exit 0 } }
elseif (-not (Enter-Lock)) { "跳过：另一轮全量还在跑（$Lock）"; exit 0 }
try {
    if (-not $DryRun -and (Test-Path -LiteralPath $inFlight)) {
        $dangling = @(Get-Content -LiteralPath $inFlight -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
        Remove-Item -LiteralPath $inFlight -Force -ErrorAction SilentlyContinue
        $existingSkip = @(if (Test-Path -LiteralPath $noRecord) { Get-Content -LiteralPath $noRecord -Encoding UTF8 })
        foreach ($entry in $dangling) {
            $parts = $entry -split '\|', 5
            if ($parts.Count -ge 3) {
                $key = "$($parts[0])|$($parts[1])|$($parts[2])"
                if ($key -notin $existingSkip) {
                    Add-Content -LiteralPath $noRecord -Value $key -Encoding UTF8
                    $existingSkip += $key
                }
                $pname = if ($parts.Count -ge 4 -and $parts[3]) { $parts[3] } else { Split-Path -Leaf $parts[0] }
                $shaVal = if ($parts.Count -ge 5 -and $parts[4]) { $parts[4] } else { $parts[1] }
                $shortSha = $shaVal.Substring(0, [Math]::Min(7, $shaVal.Length))
                Notify "$pname 主干全量上次中途中断" "主干 $shortSha 上一轮执行时进程被中断，账上未记绿。这棵树不再自动重跑，可用 -Rerun 重跑"
            }
        }
    }

    $skipped = @(if (Test-Path -LiteralPath $noRecord) { Get-Content -LiteralPath $noRecord -Encoding UTF8 })
    $cfg = Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json
    $idleMinutes = Get-TrunkNumber 'trunkIdleMinutes' 30 0
    $maxAge = Get-TrunkNumber 'trunkMaxAgeHours' 24 0
    $parallel = Get-TrunkNumber 'trunkParallel' ([math]::Max(1, [math]::Floor([Environment]::ProcessorCount / 2))) 1
    $window = if ($null -eq $cfg.trunkNightWindow) { '02:00-06:00' } else { "$($cfg.trunkNightWindow)" }
    if ($window -notmatch '^([01]\d|2[0-3]):[0-5]\d-([01]\d|2[0-3]):[0-5]\d$') { Write-Warning 'trunkNightWindow 配置错误，使用默认值 02:00-06:00'; $window = '02:00-06:00' }
    $start, $end = $window.Split('-') | ForEach-Object { [timespan]::Parse($_) }
    $idleFile = Join-Path $lockDir 'trunk-check-idle.json'
    $localFile = Join-Path $lockDir 'trunk-check-local.json'
    $pendingFile = Join-Path $lockDir 'trunk-check-pending.json'
    Update-LocalObservation
    $localHistory = Read-TrunkState $localFile
    $pendingHistory = Read-TrunkState $pendingFile
    $why = [Collections.Generic.List[string]]::new()
    $ranAny = $false
    $localBusyBlocked = $false

    foreach ($p in @($cfg.projects)) {
        if ($p.status -eq '暂停') { continue }
        $localVerify = if ($p.trunkVerify -is [string]) { $p.trunkVerify } elseif ($null -eq $p.trunkVerify) { '' } else { "$($p.trunkVerify)" }
        $effectiveVerify = $localVerify
        if (-not $effectiveVerify) { continue }
        if ($Rerun -and $p.name -ne $Rerun) { continue }
        $path = if ([IO.Path]::IsPathRooted($p.path)) { $p.path } else { Join-Path $cfgDir $p.path }
        if (-not (Test-Path -LiteralPath $path)) { $why.Add("$($p.name)：目录不在"); continue }
        $null = git -C $path check-ignore -q .agents/verify-ledger.jsonl 2>$null
        if ($LASTEXITCODE) { $why.Add("$($p.name)：.agents/ 没被 Git 忽略，记不了账"); continue }
        $trunk = if ($p.trunk) { $p.trunk } else { git -C $path rev-parse --abbrev-ref HEAD 2>$null }
        $sha = git -C $path rev-parse --verify --quiet "$trunk^{commit}" 2>$null
        if ($LASTEXITCODE -or -not $sha) { $why.Add("$($p.name)：找不到主干 $trunk"); continue }
        $sha = "$sha".Trim()
        $tree = git -C $path rev-parse --verify --quiet "$sha^{tree}" 2>$null
        if ($LASTEXITCODE -or -not $tree) { $why.Add("$($p.name)：找不到主干树 $trunk"); continue }
        $tree = "$tree".Trim()

        $effCmdKey = Get-CmdKey $effectiveVerify
        if (-not $Rerun -and "$path|$tree|$effCmdKey" -in $skipped) {
            $why.Add("$($p.name)：主干 $($sha.Substring(0, 7)) 上次跑完记不进账或曾中断，不再跑")
            continue
        }
        $lj = try { (pwsh -NoProfile -File $ledgerScript -Repo $path -Check -Rev $sha -For $effectiveVerify -Json) -join "`n" | ConvertFrom-Json } catch { $null }
        if ($lj -and $lj.last -and -not ($Rerun -and $lj.last.result -eq 'red')) {
            $why.Add("$($p.name)：主干 $($sha.Substring(0, 7)) 账上是 $($lj.last.result)")
            continue
        }
        $pick = [pscustomobject]@{
            Name        = $p.name
            Path        = $path
            Trunk       = $trunk
            Sha         = $sha
            Tree        = $tree
            Verify      = $effectiveVerify
            LocalVerify = $localVerify
            TimeoutSeconds = if ($null -ne $p.trunkTimeoutSeconds) { [int]$p.trunkTimeoutSeconds } else { 1800 }
            Setup       = [string]$p.trunkSetup
        }

        if ($pick.TimeoutSeconds -lt 1 -or $pick.TimeoutSeconds -gt 86400) { throw 'trunkTimeoutSeconds 必须在 1..86400 秒之间' }
        $inherited = if (-not $Rerun) { Get-DocumentGreen $path $tree $effectiveVerify }
        if ($inherited) {
            $source = "主干后台 沿用 树 $($inherited.tree) 提交 $($inherited.commit)"
            if ($DryRun) { "会沿用：$($pick.Name) $source"; $ranAny = $true; continue }
            $recorded = $false
            $inheritOut = [Collections.Generic.List[string]]::new()
            $inheritOut.Add($source)
            Complete-LedgerAndEffects -Pick $pick -VerifyCmd $effectiveVerify -Code 0 -Sec $(if ($null -ne $inherited.seconds) { [int]$inherited.seconds } else { -1 }) -Inherited -Where $source -LogPath (Join-Path $path '.agents/trunk-check.log') -OutLines $inheritOut -AppendLog $true -RecordedRef ([ref]$recorded)
            $ranAny = $true
            break
        }

        $decision = Get-LocalDecision $pick
        if (-not $decision.Run) { Write-Pending $pick $decision; $localBusyBlocked = $true; continue }
        if ($DryRun) {
            "会跑：$($pick.Name) $($pick.Sha.Substring(0,7))：$($decision.Reason)"
            $ranAny = $true
            continue
        }

        $log = Join-Path $pick.Path '.agents/trunk-check.log'
        $out = [Collections.Generic.List[string]]::new()
        $out.Add("$(Get-Date -Format 'yyyy-MM-dd HH:mm') $($pick.Name) 主干 $($pick.Sha)")
        $runLocal = $true
        $appendLog = $false

        if ($runLocal) {
            $ranAny = $true
            $localHistory[$pick.Path] = $now.ToString('o')
            Save-TrunkState $localFile $localHistory
            $localCmdKey = Get-CmdKey $pick.LocalVerify
            [IO.File]::WriteAllText($inFlight, "$($pick.Path)|$($pick.Tree)|$localCmdKey|$($pick.Name)|$($pick.Sha)`n", [Text.UTF8Encoding]::new($false))
            $wt = Join-Path $pick.Path '.agents/trunk-check'
            if (Test-Path -LiteralPath $wt) { $null = git -C $pick.Path worktree remove --force $wt 2>$null; if (Test-Path -LiteralPath $wt) { Remove-Item -LiteralPath $wt -Recurse -Force } }
            $null = git -C $pick.Path worktree prune 2>$null
            $null = git -C $pick.Path worktree add -q --detach $wt $pick.Sha 2>&1
            if ($LASTEXITCODE) { throw "开不出 worktree：$wt" }
            try {
                $sw = [Diagnostics.Stopwatch]::StartNew()
                $code = 0; $where = '主干后台 本机'
                Push-Location -LiteralPath $wt
                try {
                    if ($pick.Setup) {
                        $out.Add("> $($pick.Setup)")
                        $setupCode = Invoke-LocalVerify $pick.Setup 0 $out
                        if ($setupCode) { $code = $setupCode; $where = "主干后台 本机（trunkSetup 退出 $code）" }
                    }
                    if (-not $code) {
                        $out.Add("> $($pick.LocalVerify)")
                        $sw.Restart()
                        $code = Invoke-LocalVerify $pick.LocalVerify $pick.TimeoutSeconds $out
                        $sw.Stop()
                        if ($code -eq 124 -and $out.Contains("__TRUNK_LOCAL_BUDGET_TIMEOUT__=$($pick.TimeoutSeconds)")) { $where = '主干后台 本机（预算超时）' }
                    }
                }
                finally { Pop-Location }
                $sec = [int][math]::Round($sw.Elapsed.TotalSeconds)
                $recorded = $false
                Complete-LedgerAndEffects -Pick $pick -VerifyCmd $pick.LocalVerify -Code $code -Sec $sec -Where $where -LogPath $log -OutLines $out -AppendLog $appendLog -RecordedRef ([ref]$recorded)
                Remove-Item -LiteralPath $inFlight -Force -ErrorAction SilentlyContinue
                if ($Rerun -and $recorded) {
                    $nrKey = "$($pick.Path)|$($pick.Tree)|$localCmdKey"
                    $keep = @($skipped | Where-Object { $_ -ne $nrKey })
                    if ($keep.Count -ne $skipped.Count) { [IO.File]::WriteAllLines($noRecord, $keep, [Text.UTF8Encoding]::new($false)) }
                }
            }
            finally { $null = git -C $pick.Path worktree remove --force $wt 2>$null }
            break
        }
    }

    if (-not $ranAny) {
        if ($localBusyBlocked) { exit 0 }
        "没有要跑的：$(if ($why.Count) { $why -join '；' } else { '没有配了 trunkVerify、没暂停的项目' })"; exit 0
    }
}
finally { if (-not $DryRun) { Remove-Item -LiteralPath $Lock -ErrorAction SilentlyContinue } }
exit 0
